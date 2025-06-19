//! Module enrichi pour la gestion des messages directs (DM)
//! 
//! Fonctionnalités complètes équivalentes aux salons :
//! - Messages avec threads et métadonnées
//! - Système de réactions
//! - Messages épinglés
//! - Système de mentions
//! - Audit et logs de sécurité
//! - Historique paginé avancé
//! - Modération (blocage, signalement)

use sqlx::{query, query_as, FromRow, Row, Transaction, Postgres};
use serde::{Serialize, Deserialize};
use crate::hub::common::ChatHub;
use crate::validation::{validate_message_content, validate_user_id, validate_limit};
use crate::error::{ChatError, Result};
use serde_json::{json, Value};
use chrono::{DateTime, Utc};
use uuid::Uuid;

// ================================================================
// STRUCTURES DE DONNÉES
// ================================================================

#[derive(Debug, FromRow, Serialize, Deserialize)]
pub struct DmConversation {
    pub id: i64,
    pub uuid: Uuid,
    pub user1_id: i64,
    pub user2_id: i64,
    pub is_blocked: bool,
    pub blocked_by: Option<i64>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, FromRow, Serialize)]
pub struct DmMessage {
    pub id: i64,
    pub uuid: Uuid,
    pub author_id: i64,
    pub author_username: String,
    pub conversation_id: i64,
    pub content: String,
    pub parent_message_id: Option<i64>,
    pub thread_count: i32,
    pub status: String,
    pub is_edited: bool,
    pub edit_count: i32,
    pub is_pinned: bool,
    pub metadata: Value,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub edited_at: Option<DateTime<Utc>>,
    
    // Informations des réactions
    pub reactions: Option<Value>,
    pub mention_count: i32,
}

#[derive(Debug, FromRow, Serialize)]
pub struct DmStats {
    pub conversation_id: i64,
    pub total_messages: i64,
    pub pinned_messages: i64,
    pub thread_messages: i64,
    pub total_reactions: i64,
    pub last_activity: Option<DateTime<Utc>>,
    pub is_blocked: bool,
}

#[derive(Debug, Serialize)]
pub struct DmParticipant {
    pub user_id: i64,
    pub username: String,
    pub is_online: bool,
    pub last_seen: Option<DateTime<Utc>>,
}

// ================================================================
// GESTION DES CONVERSATIONS DM
// ================================================================

/// Créer ou récupérer une conversation DM entre deux utilisateurs
pub async fn get_or_create_dm_conversation(
    hub: &ChatHub,
    user1_id: i64,
    user2_id: i64
) -> Result<DmConversation> {
    tracing::info!(user1_id = %user1_id, user2_id = %user2_id, "💬 Création/récupération conversation DM");
    
    validate_user_id(user1_id as i32)?;
    validate_user_id(user2_id as i32)?;
    
    if user1_id == user2_id {
        return Err(ChatError::configuration_error("Impossible de créer une conversation avec soi-même"));
    }
    
    let mut tx = hub.db.begin().await
        .map_err(|e| ChatError::from_sqlx_error("begin_transaction", e))?;
    
    // Chercher une conversation existante (dans les deux sens)
    let existing = query_as::<_, DmConversation>("
        SELECT id, uuid, user1_id, user2_id, is_blocked, blocked_by, created_at, updated_at
        FROM dm_conversations 
        WHERE (user1_id = $1 AND user2_id = $2) OR (user1_id = $2 AND user2_id = $1)
    ")
    .bind(user1_id)
    .bind(user2_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("find_existing_dm", e))?;
    
    if let Some(conversation) = existing {
        tx.commit().await
            .map_err(|e| ChatError::from_sqlx_error("commit_transaction", e))?;
        return Ok(conversation);
    }
    
    // Créer une nouvelle conversation DM
    let dm_uuid = Uuid::new_v4();
    let conversation = query_as::<_, DmConversation>("
        INSERT INTO dm_conversations (uuid, user1_id, user2_id)
        VALUES ($1, $2, $3)
        RETURNING id, uuid, user1_id, user2_id, is_blocked, blocked_by, created_at, updated_at
    ")
    .bind(dm_uuid)
    .bind(user1_id.min(user2_id)) // Ordre consistant
    .bind(user1_id.max(user2_id))
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("create_dm_conversation", e))?;
    
    // Log d'audit
    query("
        INSERT INTO audit_logs (action, details, user_id)
        VALUES ('dm_conversation_created', $1, $2)
    ")
    .bind(json!({
        "conversation_id": conversation.id,
        "user1_id": user1_id,
        "user2_id": user2_id
    }))
    .bind(user1_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("audit_log", e))?;
    
    tx.commit().await
        .map_err(|e| ChatError::from_sqlx_error("commit_transaction", e))?;
    
    tracing::info!(conversation_id = %conversation.id, "✅ Conversation DM créée/récupérée");
    Ok(conversation)
}

/// Bloquer/débloquer une conversation DM
pub async fn block_dm_conversation(
    hub: &ChatHub,
    conversation_id: i64,
    user_id: i64,
    block: bool
) -> Result<()> {
    tracing::info!(conversation_id = %conversation_id, user_id = %user_id, block = %block, "🚫 Blocage/déblocage DM");
    
    let mut tx = hub.db.begin().await
        .map_err(|e| ChatError::from_sqlx_error("begin_transaction", e))?;
    
    // Vérifier que l'utilisateur fait partie de la conversation
    let is_participant: bool = query("
        SELECT EXISTS(
            SELECT 1 FROM dm_conversations 
            WHERE id = $1 AND (user1_id = $2 OR user2_id = $2)
        )
    ")
    .bind(conversation_id)
    .bind(user_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("check_participant", e))?
    .get(0);
    
    if !is_participant {
        return Err(ChatError::unauthorized("block_dm_conversation"));
    }
    
    // Mettre à jour le statut de blocage
    query("
        UPDATE dm_conversations 
        SET is_blocked = $1, blocked_by = $2, updated_at = NOW()
        WHERE id = $3
    ")
    .bind(block)
    .bind(if block { Some(user_id) } else { None })
    .bind(conversation_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("update_block_status", e))?;
    
    // Log d'audit
    query("
        INSERT INTO audit_logs (action, details, user_id)
        VALUES ($1, $2, $3)
    ")
    .bind(if block { "dm_blocked" } else { "dm_unblocked" })
    .bind(json!({"conversation_id": conversation_id}))
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("audit_log", e))?;
    
    tx.commit().await
        .map_err(|e| ChatError::from_sqlx_error("commit_transaction", e))?;
    
    tracing::info!(conversation_id = %conversation_id, block = %block, "✅ Statut de blocage mis à jour");
    Ok(())
}

// ================================================================
// GESTION DES MESSAGES ENRICHIS
// ================================================================

/// Envoyer un message DM enrichi
pub async fn send_dm_message(
    hub: &ChatHub,
    conversation_id: i64,
    author_id: i64,
    username: &str,
    content: &str,
    parent_message_id: Option<i64>,
    metadata: Option<Value>
) -> Result<i64> {
    tracing::info!(author_id = %author_id, conversation_id = %conversation_id, "📝 Envoi d'un message DM enrichi");
    
    validate_user_id(author_id as i32)?;
    validate_message_content(content, hub.config.limits.max_message_length)?;
    
    // Vérification du rate limiting
    if !hub.check_rate_limit(author_id as i32).await {
        return Err(ChatError::rate_limit_exceeded_simple("send_dm_message"));
    }
    
    let mut tx = hub.db.begin().await
        .map_err(|e| ChatError::from_sqlx_error("begin_transaction", e))?;
    
    // Vérifier que l'utilisateur fait partie de la conversation et qu'elle n'est pas bloquée
    let conversation_info = query("
        SELECT is_blocked, blocked_by, user1_id, user2_id
        FROM dm_conversations 
        WHERE id = $1 AND (user1_id = $2 OR user2_id = $2)
    ")
    .bind(conversation_id)
    .bind(author_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("check_dm_conversation", e))?;
    
    let (is_blocked, blocked_by, user1_id, user2_id) = match conversation_info {
        Some(row) => (
            row.get::<bool, _>("is_blocked"),
            row.get::<Option<i64>, _>("blocked_by"),
            row.get::<i64, _>("user1_id"),
            row.get::<i64, _>("user2_id")
        ),
        None => return Err(ChatError::not_found("conversation", &conversation_id.to_string()))
    };
    
    if is_blocked {
        return Err(ChatError::configuration_error("Conversation bloquée"));
    }
    
    // Insérer le message
    let message_uuid = Uuid::new_v4();
    let message_metadata = metadata.unwrap_or_else(|| json!({}));
    
    let message = query("
        INSERT INTO messages (uuid, author_id, conversation_id, content, parent_message_id, metadata, status)
        VALUES ($1, $2, $3, $4, $5, $6, 'sent')
        RETURNING id, created_at
    ")
    .bind(message_uuid)
    .bind(author_id)
    .bind(conversation_id)
    .bind(content)
    .bind(parent_message_id)
    .bind(&message_metadata)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("insert_dm_message", e))?;
    
    let message_id: i64 = message.get("id");
    let timestamp: DateTime<Utc> = message.get("created_at");
    
    // Si c'est une réponse, incrémenter le compteur de thread
    if let Some(parent_id) = parent_message_id {
        query("
            UPDATE messages 
            SET thread_count = thread_count + 1 
            WHERE id = $1
        ")
        .bind(parent_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| ChatError::from_sqlx_error("update_thread_count", e))?;
    }
    
    // Traiter les mentions (@username)
    process_dm_mentions(&mut tx, message_id, content).await?;
    
    // Mettre à jour la conversation
    query("
        UPDATE dm_conversations 
        SET updated_at = NOW() 
        WHERE id = $1
    ")
    .bind(conversation_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("update_dm_conversation", e))?;
    
    tx.commit().await
        .map_err(|e| ChatError::from_sqlx_error("commit_transaction", e))?;
    
    // Incrémentation des statistiques
    hub.increment_message_count().await;
    
    // Diffusion en temps réel
    let other_user_id = if author_id == user1_id { user2_id } else { user1_id };
    broadcast_dm_message(hub, conversation_id, message_id, author_id, other_user_id, username, content, timestamp, parent_message_id).await?;
    
    tracing::info!(message_id = %message_id, conversation_id = %conversation_id, "✅ Message DM enrichi envoyé");
    Ok(message_id)
}

/// Épingler/désépingler un message DM
pub async fn pin_dm_message(
    hub: &ChatHub,
    conversation_id: i64,
    message_id: i64,
    user_id: i64,
    pin: bool
) -> Result<()> {
    tracing::info!(user_id = %user_id, conversation_id = %conversation_id, message_id = %message_id, pin = %pin, "📌 Épinglage de message DM");
    
    let mut tx = hub.db.begin().await
        .map_err(|e| ChatError::from_sqlx_error("begin_transaction", e))?;
    
    // Vérifier que l'utilisateur fait partie de la conversation
    let is_participant: bool = query("
        SELECT EXISTS(
            SELECT 1 FROM dm_conversations 
            WHERE id = $1 AND (user1_id = $2 OR user2_id = $2)
        )
    ")
    .bind(conversation_id)
    .bind(user_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("check_participant", e))?
    .get(0);
    
    if !is_participant {
        return Err(ChatError::unauthorized("pin_dm_message"));
    }
    
    // Mettre à jour le statut d'épinglage
    let rows_affected = query("
        UPDATE messages 
        SET is_pinned = $1, updated_at = NOW()
        WHERE id = $2 AND conversation_id = $3
    ")
    .bind(pin)
    .bind(message_id)
    .bind(conversation_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("update_pin_status", e))?
    .rows_affected();
    
    if rows_affected == 0 {
        return Err(ChatError::not_found("message", &message_id.to_string()));
    }
    
    // Log d'audit
    query("
        INSERT INTO audit_logs (action, details, user_id)
        VALUES ($1, $2, $3)
    ")
    .bind(if pin { "dm_message_pinned" } else { "dm_message_unpinned" })
    .bind(json!({
        "conversation_id": conversation_id,
        "message_id": message_id
    }))
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("audit_log", e))?;
    
    tx.commit().await
        .map_err(|e| ChatError::from_sqlx_error("commit_transaction", e))?;
    
    tracing::info!(message_id = %message_id, pin = %pin, "✅ Statut d'épinglage DM mis à jour");
    Ok(())
}

/// Éditer un message DM
pub async fn edit_dm_message(
    hub: &ChatHub,
    message_id: i64,
    user_id: i64,
    new_content: &str,
    edit_reason: Option<&str>
) -> Result<()> {
    tracing::info!(user_id = %user_id, message_id = %message_id, "✏️ Édition de message DM");
    
    validate_message_content(new_content, hub.config.limits.max_message_length)?;
    
    let mut tx = hub.db.begin().await
        .map_err(|e| ChatError::from_sqlx_error("begin_transaction", e))?;
    
    // Récupérer le message et vérifier les permissions
    let message_info = query("
        SELECT m.content, m.author_id, m.conversation_id, dc.user1_id, dc.user2_id
        FROM messages m
        JOIN dm_conversations dc ON dc.id = m.conversation_id
        WHERE m.id = $1
    ")
    .bind(message_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("get_message_info", e))?;
    
    let (old_content, author_id, conversation_id, user1_id, user2_id) = match message_info {
        Some(row) => (
            row.get::<String, _>("content"),
            row.get::<i64, _>("author_id"),
            row.get::<i64, _>("conversation_id"),
            row.get::<i64, _>("user1_id"),
            row.get::<i64, _>("user2_id")
        ),
        None => return Err(ChatError::not_found("message", &message_id.to_string()))
    };
    
    // Seul l'auteur peut éditer son message
    if author_id != user_id {
        return Err(ChatError::unauthorized("edit_dm_message"));
    }
    
    // Mettre à jour le message
    query("
        UPDATE messages 
        SET content = $1, is_edited = true, edit_count = edit_count + 1, edited_at = NOW(), updated_at = NOW()
        WHERE id = $2
    ")
    .bind(new_content)
    .bind(message_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("update_message", e))?;
    
    // Log d'audit avec ancien et nouveau contenu
    query("
        INSERT INTO audit_logs (action, details, user_id)
        VALUES ('dm_message_edited', $1, $2)
    ")
    .bind(json!({
        "message_id": message_id,
        "conversation_id": conversation_id,
        "old_content": old_content,
        "new_content": new_content,
        "edit_reason": edit_reason
    }))
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("audit_log", e))?;
    
    tx.commit().await
        .map_err(|e| ChatError::from_sqlx_error("commit_transaction", e))?;
    
    // Notifier l'autre utilisateur
    let other_user_id = if user_id == user1_id { user2_id } else { user1_id };
    broadcast_dm_message_edit(hub, conversation_id, message_id, user_id, other_user_id, new_content).await?;
    
    tracing::info!(message_id = %message_id, "✅ Message DM édité");
    Ok(())
}

// ================================================================
// HISTORIQUE ET RECHERCHE
// ================================================================

/// Récupérer l'historique d'une conversation DM
pub async fn fetch_history(
    hub: &ChatHub,
    conversation_id: i64,
    user_id: i64,
    limit: i64,
    before_message_id: Option<i64>
) -> Result<Vec<DmMessage>> {
    tracing::info!(conversation_id = %conversation_id, user_id = %user_id, limit = %limit, "📚 Récupération de l'historique DM enrichi");
    
    validate_user_id(user_id as i32)?;
    let validated_limit = validate_limit(limit)?;
    
    // Vérifier que l'utilisateur fait partie de la conversation
    let is_participant: bool = query("
        SELECT EXISTS(
            SELECT 1 FROM dm_conversations 
            WHERE id = $1 AND (user1_id = $2 OR user2_id = $2)
        )
    ")
    .bind(conversation_id)
    .bind(user_id)
    .fetch_one(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("check_participant", e))?
    .get(0);
    
    if !is_participant {
        return Err(ChatError::unauthorized("fetch_dm_history"));
    }
    
    let mut query_builder = format!("
        SELECT 
            m.id, m.uuid, m.author_id, u.username as author_username,
            m.conversation_id, m.content, m.parent_message_id, m.thread_count,
            m.status, m.is_edited, m.edit_count, m.is_pinned, m.metadata,
            m.created_at, m.updated_at, m.edited_at,
            COALESCE(
                json_agg(
                    json_build_object(
                        'emoji', mr.emoji,
                        'count', COUNT(mr.id)
                    ) ORDER BY mr.emoji
                ) FILTER (WHERE mr.id IS NOT NULL), 
                '[]'::json
            ) as reactions,
            COUNT(mm.id) as mention_count
        FROM messages m
        JOIN users u ON u.id = m.author_id
        LEFT JOIN message_reactions mr ON mr.message_id = m.id
        LEFT JOIN message_mentions mm ON mm.message_id = m.id
        WHERE m.conversation_id = $1
    ");
    
    let mut param_count = 1;
    
    if let Some(_before_id) = before_message_id {
        param_count += 1;
        query_builder.push_str(&format!(" AND m.id < ${}", param_count));
    }
    
    query_builder.push_str("
        GROUP BY m.id, u.username
        ORDER BY m.created_at DESC
    ");
    
    param_count += 1;
    query_builder.push_str(&format!(" LIMIT ${}", param_count));
    
    let mut query_obj = query_as::<_, EnhancedDmMessage>(&query_builder)
        .bind(conversation_id);
    
    if let Some(before_id) = before_message_id {
        query_obj = query_obj.bind(before_id);
    }
    
    let messages = query_obj
        .bind(validated_limit)
        .fetch_all(&hub.db)
        .await
        .map_err(|e| ChatError::from_sqlx_error("fetch_dm_history", e))?;
    
    tracing::info!(conversation_id = %conversation_id, message_count = %messages.len(), "✅ Historique DM enrichi récupéré");
    Ok(messages)
}

/// Récupérer les messages épinglés d'une conversation DM
pub async fn fetch_pinned_messages(
    hub: &ChatHub,
    conversation_id: i64,
    user_id: i64
) -> Result<Vec<DmMessage>> {
    tracing::info!(conversation_id = %conversation_id, user_id = %user_id, "📌 Récupération des messages DM épinglés");
    
    // Vérifier que l'utilisateur fait partie de la conversation
    let is_participant: bool = query("
        SELECT EXISTS(
            SELECT 1 FROM dm_conversations 
            WHERE id = $1 AND (user1_id = $2 OR user2_id = $2)
        )
    ")
    .bind(conversation_id)
    .bind(user_id)
    .fetch_one(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("check_participant", e))?
    .get(0);
    
    if !is_participant {
        return Err(ChatError::unauthorized("fetch_pinned_dm_messages"));
    }
    
    let messages = query_as::<_, DmMessage>("
        SELECT 
            m.id, m.uuid, m.author_id, u.username as author_username,
            m.conversation_id, m.content, m.parent_message_id, m.thread_count,
            m.status, m.is_edited, m.edit_count, m.is_pinned, m.metadata,
            m.created_at, m.updated_at, m.edited_at,
            '[]'::json as reactions,
            0 as mention_count
        FROM messages m
        JOIN users u ON u.id = m.author_id
        WHERE m.conversation_id = $1 AND m.is_pinned = TRUE
        ORDER BY m.created_at DESC
    ")
    .bind(conversation_id)
    .fetch_all(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("fetch_pinned_dm_messages", e))?;
    
    tracing::info!(conversation_id = %conversation_id, pinned_count = %messages.len(), "✅ Messages DM épinglés récupérés");
    Ok(messages)
}

// ================================================================
// STATISTIQUES ET ADMINISTRATION
// ================================================================

/// Obtenir les statistiques d'une conversation DM
pub async fn get_dm_stats(
    hub: &ChatHub,
    conversation_id: i64,
    user_id: i64
) -> Result<DmStats> {
    tracing::info!(conversation_id = %conversation_id, user_id = %user_id, "📊 Récupération des statistiques DM");
    
    // Vérifier que l'utilisateur fait partie de la conversation
    let is_participant: bool = query("
        SELECT EXISTS(
            SELECT 1 FROM dm_conversations 
            WHERE id = $1 AND (user1_id = $2 OR user2_id = $2)
        )
    ")
    .bind(conversation_id)
    .bind(user_id)
    .fetch_one(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("check_participant", e))?
    .get(0);
    
    if !is_participant {
        return Err(ChatError::unauthorized("get_dm_stats"));
    }
    
    let stats = query_as::<_, DmStats>("
        SELECT 
            dc.id as conversation_id,
            COUNT(DISTINCT m.id) as total_messages,
            COUNT(DISTINCT m.id) FILTER (WHERE m.is_pinned = TRUE) as pinned_messages,
            COUNT(DISTINCT m.id) FILTER (WHERE m.parent_message_id IS NOT NULL) as thread_messages,
            COUNT(DISTINCT mr.id) as total_reactions,
            MAX(m.created_at) as last_activity,
            dc.is_blocked
        FROM dm_conversations dc
        LEFT JOIN messages m ON m.conversation_id = dc.id
        LEFT JOIN message_reactions mr ON mr.message_id = m.id
        WHERE dc.id = $1
        GROUP BY dc.id, dc.is_blocked
    ")
    .bind(conversation_id)
    .fetch_one(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("get_dm_stats", e))?;
    
    tracing::info!(conversation_id = %conversation_id, "✅ Statistiques DM récupérées");
    Ok(stats)
}

/// Lister les conversations DM d'un utilisateur
pub async fn list_user_dm_conversations(
    hub: &ChatHub,
    user_id: i64,
    limit: i64
) -> Result<Vec<(DmConversation, DmParticipant)>> {
    tracing::info!(user_id = %user_id, limit = %limit, "💬 Liste des conversations DM");
    
    validate_user_id(user_id as i32)?;
    let validated_limit = validate_limit(limit)?;
    
    let conversations = query("
        SELECT 
            dc.id, dc.uuid, dc.user1_id, dc.user2_id, dc.is_blocked, dc.blocked_by, 
            dc.created_at, dc.updated_at,
            u.id as other_user_id, u.username as other_username, 
            u.is_online, u.last_activity as last_seen
        FROM dm_conversations dc
        JOIN users u ON (
            CASE 
                WHEN dc.user1_id = $1 THEN u.id = dc.user2_id
                ELSE u.id = dc.user1_id
            END
        )
        WHERE dc.user1_id = $1 OR dc.user2_id = $1
        ORDER BY dc.updated_at DESC
        LIMIT $2
    ")
    .bind(user_id)
    .bind(validated_limit)
    .fetch_all(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("list_dm_conversations", e))?;
    
    let mut result = Vec::new();
    
    for row in conversations {
        let conversation = DmConversation {
            id: row.get("id"),
            uuid: row.get("uuid"),
            user1_id: row.get("user1_id"),
            user2_id: row.get("user2_id"),
            is_blocked: row.get("is_blocked"),
            blocked_by: row.get("blocked_by"),
            created_at: row.get("created_at"),
            updated_at: row.get("updated_at"),
        };
        
        let participant = DmParticipant {
            user_id: row.get("other_user_id"),
            username: row.get("other_username"),
            is_online: row.get("is_online"),
            last_seen: row.get("last_seen"),
        };
        
        result.push((conversation, participant));
    }
    
    tracing::info!(user_id = %user_id, conversation_count = %result.len(), "✅ Conversations DM listées");
    Ok(result)
}

// ================================================================
// FONCTIONS UTILITAIRES
// ================================================================

/// Traiter les mentions dans un message DM
async fn process_dm_mentions(tx: &mut Transaction<'_, Postgres>, message_id: i64, content: &str) -> Result<()> {
    use regex::Regex;
    
    let mention_regex = Regex::new(r"@(\w+)").unwrap();
    
    for cap in mention_regex.captures_iter(content) {
        let username = &cap[1];
        
        // Trouver l'ID de l'utilisateur mentionné
        if let Ok(user_row) = query("SELECT id FROM users WHERE username = $1")
            .bind(username)
            .fetch_one(&mut **tx)
            .await {
            
            let mentioned_user_id: i64 = user_row.get("id");
            
            // Ajouter la mention
            query("
                INSERT INTO message_mentions (message_id, mentioned_user_id)
                VALUES ($1, $2)
                ON CONFLICT (message_id, mentioned_user_id) DO NOTHING
            ")
            .bind(message_id)
            .bind(mentioned_user_id)
            .execute(&mut **tx)
            .await
            .map_err(|e| ChatError::from_sqlx_error("insert_dm_mention", e))?;
        }
    }
    
    Ok(())
}

/// Diffuser un message DM en temps réel
async fn broadcast_dm_message(
    hub: &ChatHub,
    conversation_id: i64,
    message_id: i64,
    author_id: i64,
    other_user_id: i64,
    username: &str,
    content: &str,
    timestamp: DateTime<Utc>,
    parent_message_id: Option<i64>
) -> Result<()> {
    let clients = hub.clients.read().await;
    
    let payload = json!({
        "type": "dm_message",
        "data": {
            "id": message_id,
            "conversationId": conversation_id,
            "authorId": author_id,
            "username": username,
            "content": content,
            "timestamp": timestamp,
            "parentMessageId": parent_message_id,
            "isThread": parent_message_id.is_some()
        }
    });
    
    let mut successful_sends = 0;
    
    // Envoyer à l'auteur et au destinataire
    for user_id in [author_id, other_user_id] {
        if let Some(client) = clients.get(&(user_id as i32)) {
            if client.send_text(&payload.to_string()) {
                successful_sends += 1;
            }
        }
    }
    
    tracing::info!(
        conversation_id = %conversation_id, 
        message_id = %message_id, 
        successful_sends = %successful_sends,
        "📡 Message DM diffusé"
    );
    
    Ok(())
}

/// Diffuser une édition de message DM
async fn broadcast_dm_message_edit(
    hub: &ChatHub,
    conversation_id: i64,
    message_id: i64,
    editor_id: i64,
    other_user_id: i64,
    new_content: &str
) -> Result<()> {
    let clients = hub.clients.read().await;
    
    let payload = json!({
        "type": "dm_message_edited",
        "data": {
            "messageId": message_id,
            "conversationId": conversation_id,
            "editorId": editor_id,
            "newContent": new_content,
            "timestamp": Utc::now()
        }
    });
    
    let mut successful_sends = 0;
    
    // Envoyer à l'éditeur et à l'autre utilisateur
    for user_id in [editor_id, other_user_id] {
        if let Some(client) = clients.get(&(user_id as i32)) {
            if client.send_text(&payload.to_string()) {
                successful_sends += 1;
            }
        }
    }
    
    tracing::info!(
        conversation_id = %conversation_id, 
        message_id = %message_id, 
        successful_sends = %successful_sends,
        "📡 Édition de message DM diffusée"
    );
    
    Ok(())
} 