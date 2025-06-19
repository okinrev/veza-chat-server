//! Module de gestion des logs d'audit et de sécurité
//! 
//! Fonctionnalités :
//! - Audit des actions utilisateur
//! - Logs de sécurité et modération
//! - Historique des modifications
//! - Rapports d'activité
//! - Surveillance des patterns suspects

use sqlx::{query, query_as, FromRow, Row};
use serde::{Serialize, Deserialize};
use crate::hub::common::ChatHub;
use crate::validation::{validate_user_id, validate_limit};
use crate::error::{ChatError, Result};
use serde_json::{json, Value};
use chrono::{DateTime, Utc, Duration};
use std::collections::HashMap;

// ================================================================
// STRUCTURES DE DONNÉES
// ================================================================

#[derive(Debug, FromRow, Serialize, Deserialize)]
pub struct AuditLog {
    pub id: i64,
    pub action: String,
    pub details: Value,
    pub user_id: Option<i64>,
    pub ip_address: Option<String>,
    pub user_agent: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, FromRow, Serialize)]
pub struct SecurityEvent {
    pub id: i64,
    pub event_type: String,
    pub severity: String,
    pub description: String,
    pub user_id: Option<i64>,
    pub ip_address: Option<String>,
    pub metadata: Value,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
pub struct ActivityReport {
    pub period_start: DateTime<Utc>,
    pub period_end: DateTime<Utc>,
    pub total_actions: i64,
    pub unique_users: i64,
    pub actions_by_type: HashMap<String, i64>,
    pub top_users: Vec<UserActivity>,
    pub security_events: i64,
}

#[derive(Debug, FromRow, Serialize)]
pub struct UserActivity {
    pub user_id: i64,
    pub username: String,
    pub action_count: i64,
    pub last_activity: DateTime<Utc>,
}

#[derive(Debug, FromRow, Serialize)]
pub struct RoomAuditSummary {
    pub room_id: i64,
    pub room_name: String,
    pub total_messages: i64,
    pub deleted_messages: i64,
    pub pinned_messages: i64,
    pub member_changes: i64,
    pub moderation_actions: i64,
    pub last_activity: Option<DateTime<Utc>>,
}

// ================================================================
// ENREGISTREMENT DES LOGS D'AUDIT
// ================================================================

/// Enregistrer une action d'audit
pub async fn log_action(
    hub: &ChatHub,
    action: &str,
    details: Value,
    user_id: Option<i64>,
    ip_address: Option<&str>,
    user_agent: Option<&str>
) -> Result<i64> {
    tracing::debug!(action = %action, user_id = ?user_id, "📝 Enregistrement d'action d'audit");
    
    let audit_id = query("
        INSERT INTO audit_logs (action, details, user_id, ip_address, user_agent)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id
    ")
    .bind(action)
    .bind(&details)
    .bind(user_id)
    .bind(ip_address)
    .bind(user_agent)
    .fetch_one(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("insert_audit_log", e))?
    .get::<i64, _>("id");
    
    tracing::info!(action = %action, audit_id = %audit_id, "✅ Action d'audit enregistrée");
    Ok(audit_id)
}

/// Enregistrer un événement de sécurité
pub async fn log_security_event(
    hub: &ChatHub,
    event_type: &str,
    severity: &str,
    description: &str,
    user_id: Option<i64>,
    ip_address: Option<&str>,
    metadata: Value
) -> Result<i64> {
    tracing::warn!(
        event_type = %event_type, 
        severity = %severity, 
        user_id = ?user_id,
        "🚨 Enregistrement d'événement de sécurité"
    );
    
    let event_id = query("
        INSERT INTO security_events (event_type, severity, description, user_id, ip_address, metadata)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id
    ")
    .bind(event_type)
    .bind(severity)
    .bind(description)
    .bind(user_id)
    .bind(ip_address)
    .bind(&metadata)
    .fetch_one(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("insert_security_event", e))?
    .get::<i64, _>("id");
    
    tracing::warn!(event_type = %event_type, event_id = %event_id, "🚨 Événement de sécurité enregistré");
    Ok(event_id)
}

// ================================================================
// LOGS SPÉCIFIQUES AUX SALONS
// ================================================================

/// Logger la création d'un salon
pub async fn log_room_created(
    hub: &ChatHub,
    room_id: i64,
    room_name: &str,
    owner_id: i64,
    is_public: bool
) -> Result<()> {
    log_action(
        hub,
        "room_created",
        json!({
            "room_id": room_id,
            "room_name": room_name,
            "is_public": is_public
        }),
        Some(owner_id),
        None,
        None
    ).await?;
    
    Ok(())
}

/// Logger l'ajout/suppression d'un membre
pub async fn log_member_change(
    hub: &ChatHub,
    room_id: i64,
    room_name: &str,
    target_user_id: i64,
    action_user_id: Option<i64>,
    action: &str, // "joined", "left", "kicked", "banned"
    reason: Option<&str>
) -> Result<()> {
    let mut details = json!({
        "room_id": room_id,
        "room_name": room_name,
        "target_user_id": target_user_id,
        "action": action
    });
    
    if let Some(reason) = reason {
        details["reason"] = json!(reason);
    }
    
    log_action(
        hub,
        &format!("member_{}", action),
        details,
        action_user_id,
        None,
        None
    ).await?;
    
    Ok(())
}

/// Logger la modification d'un message
pub async fn log_message_modified(
    hub: &ChatHub,
    message_id: i64,
    room_id: i64,
    author_id: i64,
    action: &str, // "edited", "deleted", "pinned", "unpinned"
    old_content: Option<&str>,
    new_content: Option<&str>,
    moderator_id: Option<i64>
) -> Result<()> {
    let mut details = json!({
        "message_id": message_id,
        "room_id": room_id,
        "author_id": author_id,
        "action": action
    });
    
    if let Some(old) = old_content {
        details["old_content"] = json!(old);
    }
    if let Some(new) = new_content {
        details["new_content"] = json!(new);
    }
    
    log_action(
        hub,
        &format!("message_{}", action),
        details,
        moderator_id.or(Some(author_id)),
        None,
        None
    ).await?;
    
    Ok(())
}

/// Logger les actions de modération
pub async fn log_moderation_action(
    hub: &ChatHub,
    room_id: i64,
    moderator_id: i64,
    target_user_id: i64,
    action: &str, // "warn", "mute", "unmute", "kick", "ban", "unban"
    duration: Option<Duration>,
    reason: &str
) -> Result<()> {
    let mut details = json!({
        "room_id": room_id,
        "target_user_id": target_user_id,
        "action": action,
        "reason": reason
    });
    
    if let Some(duration) = duration {
        details["duration_seconds"] = json!(duration.num_seconds());
    }
    
    log_action(
        hub,
        &format!("moderation_{}", action),
        details.clone(),
        Some(moderator_id),
        None,
        None
    ).await?;
    
    // Aussi enregistrer comme événement de sécurité si c'est une action sévère
    match action {
        "ban" | "kick" => {
            log_security_event(
                hub,
                "moderation_action",
                "medium",
                &format!("Utilisateur {} par modérateur {}: {}", action, moderator_id, reason),
                Some(target_user_id),
                None,
                details
            ).await?;
        }
        _ => {}
    }
    
    Ok(())
}

// ================================================================
// CONSULTATION DES LOGS
// ================================================================

/// Récupérer les logs d'audit d'un salon
pub async fn get_room_audit_logs(
    hub: &ChatHub,
    room_id: i64,
    requesting_user_id: i64,
    limit: i64,
    before_date: Option<DateTime<Utc>>
) -> Result<Vec<AuditLog>> {
    tracing::info!(room_id = %room_id, user_id = %requesting_user_id, "📚 Récupération des logs d'audit du salon");
    
    validate_user_id(requesting_user_id as i32)?;
    let validated_limit = validate_limit(limit)?;
    
    // Vérifier que l'utilisateur a les permissions pour voir les logs
    check_audit_permissions(hub, room_id, requesting_user_id).await?;
    
    let mut query_str = format!("
        SELECT id, action, details, user_id, ip_address, user_agent, created_at
        FROM audit_logs
        WHERE (details->>'room_id')::bigint = $1
    ");
    
    let mut param_count = 1;
    
    if let Some(_before) = before_date {
        param_count += 1;
        query_str.push_str(&format!(" AND created_at < ${}", param_count));
    }
    
    query_str.push_str(" ORDER BY created_at DESC");
    
    param_count += 1;
    query_str.push_str(&format!(" LIMIT ${}", param_count));
    
    let mut query_obj = query_as::<_, AuditLog>(&query_str).bind(room_id);
    
    if let Some(before) = before_date {
        query_obj = query_obj.bind(before);
    }
    
    let logs = query_obj
        .bind(validated_limit)
        .fetch_all(&hub.db)
        .await
        .map_err(|e| ChatError::from_sqlx_error("get_room_audit_logs", e))?;
    
    tracing::info!(room_id = %room_id, log_count = %logs.len(), "✅ Logs d'audit du salon récupérés");
    Ok(logs)
}

/// Récupérer les événements de sécurité d'un salon
pub async fn get_room_security_events(
    hub: &ChatHub,
    room_id: i64,
    requesting_user_id: i64,
    severity_filter: Option<&str>,
    limit: i64
) -> Result<Vec<SecurityEvent>> {
    tracing::info!(room_id = %room_id, user_id = %requesting_user_id, "🚨 Récupération des événements de sécurité du salon");
    
    validate_user_id(requesting_user_id as i32)?;
    let validated_limit = validate_limit(limit)?;
    
    // Vérifier les permissions
    check_audit_permissions(hub, room_id, requesting_user_id).await?;
    
    let mut query_str = format!("
        SELECT id, event_type, severity, description, user_id, ip_address, metadata, created_at
        FROM security_events
        WHERE (metadata->>'room_id')::bigint = $1
    ");
    
    let mut param_count = 1;
    
    if let Some(_severity) = severity_filter {
        param_count += 1;
        query_str.push_str(&format!(" AND severity = ${}", param_count));
    }
    
    query_str.push_str(" ORDER BY created_at DESC");
    
    param_count += 1;
    query_str.push_str(&format!(" LIMIT ${}", param_count));
    
    let mut query_obj = query_as::<_, SecurityEvent>(&query_str).bind(room_id);
    
    if let Some(severity) = severity_filter {
        query_obj = query_obj.bind(severity);
    }
    
    let events = query_obj
        .bind(validated_limit)
        .fetch_all(&hub.db)
        .await
        .map_err(|e| ChatError::from_sqlx_error("get_room_security_events", e))?;
    
    tracing::info!(room_id = %room_id, event_count = %events.len(), "✅ Événements de sécurité du salon récupérés");
    Ok(events)
}

/// Générer un rapport d'activité pour un salon
pub async fn generate_room_activity_report(
    hub: &ChatHub,
    room_id: i64,
    requesting_user_id: i64,
    period_days: i32
) -> Result<ActivityReport> {
    tracing::info!(room_id = %room_id, user_id = %requesting_user_id, period_days = %period_days, "📊 Génération du rapport d'activité");
    
    validate_user_id(requesting_user_id as i32)?;
    
    // Vérifier les permissions
    check_audit_permissions(hub, room_id, requesting_user_id).await?;
    
    let period_start = Utc::now() - Duration::days(period_days as i64);
    let period_end = Utc::now();
    
    // Statistiques générales
    let total_actions: i64 = query("
        SELECT COUNT(*) FROM audit_logs
        WHERE (details->>'room_id')::bigint = $1 
        AND created_at BETWEEN $2 AND $3
    ")
    .bind(room_id)
    .bind(period_start)
    .bind(period_end)
    .fetch_one(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("count_total_actions", e))?
    .get(0);
    
    let unique_users: i64 = query("
        SELECT COUNT(DISTINCT user_id) FROM audit_logs
        WHERE (details->>'room_id')::bigint = $1 
        AND created_at BETWEEN $2 AND $3
        AND user_id IS NOT NULL
    ")
    .bind(room_id)
    .bind(period_start)
    .bind(period_end)
    .fetch_one(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("count_unique_users", e))?
    .get(0);
    
    // Actions par type
    let actions_by_type_raw = query_as::<_, (String, i64)>("
        SELECT action, COUNT(*) as count
        FROM audit_logs
        WHERE (details->>'room_id')::bigint = $1 
        AND created_at BETWEEN $2 AND $3
        GROUP BY action
        ORDER BY count DESC
    ")
    .bind(room_id)
    .bind(period_start)
    .bind(period_end)
    .fetch_all(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("get_actions_by_type", e))?;
    
    let actions_by_type: HashMap<String, i64> = actions_by_type_raw.into_iter().collect();
    
    // Utilisateurs les plus actifs
    let top_users = query_as::<_, UserActivity>("
        SELECT 
            al.user_id, 
            u.username, 
            COUNT(*) as action_count,
            MAX(al.created_at) as last_activity
        FROM audit_logs al
        JOIN users u ON u.id = al.user_id
        WHERE (al.details->>'room_id')::bigint = $1 
        AND al.created_at BETWEEN $2 AND $3
        AND al.user_id IS NOT NULL
        GROUP BY al.user_id, u.username
        ORDER BY action_count DESC
        LIMIT 10
    ")
    .bind(room_id)
    .bind(period_start)
    .bind(period_end)
    .fetch_all(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("get_top_users", e))?;
    
    // Événements de sécurité
    let security_events: i64 = query("
        SELECT COUNT(*) FROM security_events
        WHERE (metadata->>'room_id')::bigint = $1 
        AND created_at BETWEEN $2 AND $3
    ")
    .bind(room_id)
    .bind(period_start)
    .bind(period_end)
    .fetch_one(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("count_security_events", e))?
    .get(0);
    
    let report = ActivityReport {
        period_start,
        period_end,
        total_actions,
        unique_users,
        actions_by_type,
        top_users,
        security_events,
    };
    
    tracing::info!(room_id = %room_id, total_actions = %total_actions, "✅ Rapport d'activité généré");
    Ok(report)
}

/// Obtenir un résumé d'audit pour un salon
pub async fn get_room_audit_summary(
    hub: &ChatHub,
    room_id: i64,
    requesting_user_id: i64
) -> Result<RoomAuditSummary> {
    tracing::info!(room_id = %room_id, user_id = %requesting_user_id, "📋 Récupération du résumé d'audit du salon");
    
    validate_user_id(requesting_user_id as i32)?;
    check_audit_permissions(hub, room_id, requesting_user_id).await?;
    
    let summary = query_as::<_, RoomAuditSummary>("
        SELECT 
            c.id as room_id,
            c.name as room_name,
            COUNT(DISTINCT m.id) as total_messages,
            COUNT(DISTINCT m.id) FILTER (WHERE m.status = 'deleted') as deleted_messages,
            COUNT(DISTINCT m.id) FILTER (WHERE m.is_pinned = TRUE) as pinned_messages,
            COUNT(DISTINCT al.id) FILTER (WHERE al.action LIKE 'member_%') as member_changes,
            COUNT(DISTINCT al.id) FILTER (WHERE al.action LIKE 'moderation_%') as moderation_actions,
            MAX(m.created_at) as last_activity
        FROM conversations c
        LEFT JOIN messages m ON m.conversation_id = c.id
        LEFT JOIN audit_logs al ON (al.details->>'room_id')::bigint = c.id
        WHERE c.id = $1
        GROUP BY c.id, c.name
    ")
    .bind(room_id)
    .fetch_one(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("get_room_audit_summary", e))?;
    
    tracing::info!(room_id = %room_id, "✅ Résumé d'audit du salon récupéré");
    Ok(summary)
}

// ================================================================
// DÉTECTION D'ANOMALIES
// ================================================================

/// Détecter des patterns suspects d'activité
pub async fn detect_suspicious_patterns(
    hub: &ChatHub,
    room_id: i64,
    hours_lookback: i32
) -> Result<Vec<SecurityEvent>> {
    tracing::info!(room_id = %room_id, hours = %hours_lookback, "🔍 Détection de patterns suspects");
    
    let lookback_time = Utc::now() - Duration::hours(hours_lookback as i64);
    
    // Détecter les utilisateurs avec trop d'actions en peu de temps
    let suspicious_users = query("
        SELECT 
            user_id,
            COUNT(*) as action_count,
            COUNT(DISTINCT action) as unique_actions
        FROM audit_logs
        WHERE (details->>'room_id')::bigint = $1 
        AND created_at > $2
        AND user_id IS NOT NULL
        GROUP BY user_id
        HAVING COUNT(*) > 50 OR COUNT(DISTINCT action) > 10
    ")
    .bind(room_id)
    .bind(lookback_time)
    .fetch_all(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("detect_suspicious_users", e))?;
    
    let mut events = Vec::new();
    
    for row in suspicious_users {
        let user_id: i64 = row.get("user_id");
        let action_count: i64 = row.get("action_count");
        let unique_actions: i64 = row.get("unique_actions");
        
        let event_id = log_security_event(
            hub,
            "suspicious_activity",
            "medium",
            &format!("Activité suspecte détectée: {} actions, {} types différents en {} heures", 
                    action_count, unique_actions, hours_lookback),
            Some(user_id),
            None,
            json!({
                "room_id": room_id,
                "action_count": action_count,
                "unique_actions": unique_actions,
                "detection_window_hours": hours_lookback
            })
        ).await?;
        
        // Récupérer l'événement créé pour le retourner
        if let Ok(event) = query_as::<_, SecurityEvent>("
            SELECT id, event_type, severity, description, user_id, ip_address, metadata, created_at
            FROM security_events WHERE id = $1
        ")
        .bind(event_id)
        .fetch_one(&hub.db)
        .await {
            events.push(event);
        }
    }
    
    tracing::info!(room_id = %room_id, suspicious_events = %events.len(), "🔍 Détection terminée");
    Ok(events)
}

// ================================================================
// FONCTIONS UTILITAIRES
// ================================================================

/// Vérifier si un utilisateur a les permissions pour consulter les logs d'audit
async fn check_audit_permissions(hub: &ChatHub, room_id: i64, user_id: i64) -> Result<()> {
    let user_role: Option<String> = query("
        SELECT role FROM conversation_members 
        WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL
    ")
    .bind(room_id)
    .bind(user_id)
    .fetch_optional(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("check_audit_permissions", e))?
    .map(|row| row.get("role"));
    
    match user_role.as_deref() {
        Some("owner") | Some("moderator") => Ok(()),
        _ => {
            // Vérifier si c'est un admin global
            let is_admin: bool = query("
                SELECT role = 'admin' OR role = 'super_admin' 
                FROM users WHERE id = $1
            ")
            .bind(user_id)
            .fetch_one(&hub.db)
            .await
            .map_err(|e| ChatError::from_sqlx_error("check_global_admin", e))?
            .get(0);
            
            if is_admin {
                Ok(())
            } else {
                Err(ChatError::unauthorized("access_audit_logs"))
            }
        }
    }
} 