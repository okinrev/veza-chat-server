//! Module enrichi pour la gestion des salons de chat
//! 
//! Fonctionnalités complètes :
//! - Gestion des membres avec rôles
//! - Historique complet des messages
//! - Système de mentions
//! - Réactions aux messages
//! - Messages épinglés
//! - Threads de discussion
//! - Audit et logs de sécurité
//! - Gestion des permissions
//! - Modération intégrée

use sqlx::{query, query_as, FromRow, Row, Transaction, Postgres};
use serde::{Serialize, Deserialize};
use crate::hub::common::ChatHub;
use crate::validation::{validate_room_name, validate_message_content, validate_limit, validate_user_id};
use crate::error::{ChatError, Result};
use serde_json::{json, Value};
use chrono::{DateTime, Utc};
use uuid::Uuid;

// ================================================================
// STRUCTURES DE DONNÉES
// ================================================================

#[derive(Debug, FromRow, Serialize, Deserialize)]
pub struct Room {
    pub id: i64,
    pub uuid: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub owner_id: i64,
    pub is_public: bool,
    pub is_archived: bool,
    pub max_members: Option<i32>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, FromRow, Serialize, Deserialize)]
pub struct RoomMember {
    pub id: i64,
    pub conversation_id: i64,
    pub user_id: i64,
    pub role: String,
    pub joined_at: DateTime<Utc>,
    pub left_at: Option<DateTime<Utc>>,
    pub is_muted: bool,
}

#[derive(Debug, FromRow, Serialize)]
pub struct RoomMessage {
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
pub struct RoomStats {
    pub room_id: i64,
    pub room_name: String,
    pub total_messages: i64,
    pub total_members: i64,
    pub active_members: i64,
    pub last_activity: Option<DateTime<Utc>>,
    pub pinned_messages: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RoomPermissions {
    pub can_send_messages: bool,
    pub can_pin_messages: bool,
    pub can_delete_messages: bool,
    pub can_manage_members: bool,
    pub can_edit_room: bool,
}

// ================================================================
// GESTION DES SALONS
// ================================================================

/// Crée un nouveau salon de chat
pub async fn create_room(
    hub: &ChatHub,
    owner_id: i64,
    name: &str,
    description: Option<&str>,
    is_public: bool,
    max_members: Option<i32>
) -> Result<Room> {
    tracing::info!(owner_id = %owner_id, name = %name, is_public = %is_public, "🏗️ Création d'un nouveau salon");
    
    validate_room_name(name)?;
    validate_user_id(owner_id as i32)?;
    
    let room_uuid = Uuid::new_v4();
    
    let mut tx = hub.db.begin().await
        .map_err(|e| ChatError::from_sqlx_error("begin_transaction", e))?;
    
    // Créer la conversation
    let conversation = query_as::<_, Room>("
        INSERT INTO conversations (uuid, type, name, description, owner_id, is_public, max_members)
        VALUES ($1, 'public_room', $2, $3, $4, $5, $6)
        RETURNING id, uuid, name, description, owner_id, is_public, is_archived, max_members, created_at, updated_at
    ")
    .bind(room_uuid)
    .bind(name)
    .bind(description)
    .bind(owner_id)
    .bind(is_public)
    .bind(max_members)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("create_conversation", e))?;
    
    // Ajouter le propriétaire comme premier membre
    query("
        INSERT INTO conversation_members (conversation_id, user_id, role)
        VALUES ($1, $2, 'owner')
    ")
    .bind(conversation.id)
    .bind(owner_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("add_owner_member", e))?;
    
    // Log d'audit
    query("
        INSERT INTO audit_logs (action, details, user_id)
        VALUES ('room_created', $1, $2)
    ")
    .bind(json!({
        "room_id": conversation.id,
        "room_name": name,
        "is_public": is_public,
        "max_members": max_members
    }))
    .bind(owner_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("audit_log", e))?;
    
    tx.commit().await
        .map_err(|e| ChatError::from_sqlx_error("commit_transaction", e))?;
    
    tracing::info!(room_id = %conversation.id, name = %name, "✅ Salon créé avec succès");
    Ok(conversation)
}

/// Rejoindre un salon
pub async fn join_room(hub: &ChatHub, room_id: i64, user_id: i64) -> Result<()> {
    tracing::info!(user_id = %user_id, room_id = %room_id, "👥 Tentative de rejoindre le salon");
    
    validate_user_id(user_id as i32)?;
    
    let mut tx = hub.db.begin().await
        .map_err(|e| ChatError::from_sqlx_error("begin_transaction", e))?;
    
    // Vérifier que le salon existe et n'est pas archivé
    let room: Room = query_as("
        SELECT id, uuid, name, description, owner_id, is_public, is_archived, max_members, created_at, updated_at
        FROM conversations 
        WHERE id = $1 AND type = 'public_room' AND NOT is_archived
    ")
    .bind(room_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| ChatError::not_found("salon", &room_id.to_string()))?;
    
    // Vérifier si l'utilisateur est déjà membre
    let is_member: bool = query("
        SELECT EXISTS(
            SELECT 1 FROM conversation_members 
            WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL
        )
    ")
    .bind(room_id)
    .bind(user_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("check_membership", e))?
    .get(0);
    
    if is_member {
        return Err(ChatError::configuration_error("Utilisateur déjà membre du salon"));
    }
    
    // Vérifier la limite de membres
    if let Some(max_members) = room.max_members {
        let current_count: i64 = query("
            SELECT COUNT(*) FROM conversation_members 
            WHERE conversation_id = $1 AND left_at IS NULL
        ")
        .bind(room_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|e| ChatError::from_sqlx_error("count_members", e))?
        .get(0);
        
        if current_count >= max_members as i64 {
            return Err(ChatError::configuration_error("Salon plein"));
        }
    }
    
    // Ajouter le membre
    query("
        INSERT INTO conversation_members (conversation_id, user_id, role)
        VALUES ($1, $2, 'member')
        ON CONFLICT (conversation_id, user_id) 
        DO UPDATE SET left_at = NULL, joined_at = NOW()
    ")
    .bind(room_id)
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("add_member", e))?;
    
    // Log d'audit
    query("
        INSERT INTO audit_logs (action, details, user_id)
        VALUES ('room_joined', $1, $2)
    ")
    .bind(json!({
        "room_id": room_id,
        "room_name": room.name
    }))
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("audit_log", e))?;
    
    tx.commit().await
        .map_err(|e| ChatError::from_sqlx_error("commit_transaction", e))?;
    
    tracing::info!(user_id = %user_id, room_id = %room_id, "✅ Utilisateur a rejoint le salon");
    Ok(())
}

/// Quitter un salon
pub async fn leave_room(hub: &ChatHub, room_id: i64, user_id: i64) -> Result<()> {
    tracing::info!(user_id = %user_id, room_id = %room_id, "🚪 Tentative de quitter le salon");
    
    let mut tx = hub.db.begin().await
        .map_err(|e| ChatError::from_sqlx_error("begin_transaction", e))?;
    
    // Marquer comme parti
    let rows_affected = query("
        UPDATE conversation_members 
        SET left_at = NOW() 
        WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL
    ")
    .bind(room_id)
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("leave_room", e))?
    .rows_affected();
    
    if rows_affected == 0 {
        return Err(ChatError::not_found("membre", &user_id.to_string()));
    }
    
    // Log d'audit
    query("
        INSERT INTO audit_logs (action, details, user_id)
        VALUES ('room_left', $1, $2)
    ")
    .bind(json!({"room_id": room_id}))
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("audit_log", e))?;
    
    tx.commit().await
        .map_err(|e| ChatError::from_sqlx_error("commit_transaction", e))?;
    
    tracing::info!(user_id = %user_id, room_id = %room_id, "✅ Utilisateur a quitté le salon");
    Ok(())
}

// ================================================================
// GESTION DES MESSAGES
// ================================================================

/// Envoyer un message dans un salon
pub async fn send_room_message(
    hub: &ChatHub,
    room_id: i64,
    author_id: i64,
    username: &str,
    content: &str,
    parent_message_id: Option<i64>,
    metadata: Option<Value>
) -> Result<i64> {
    tracing::info!(author_id = %author_id, room_id = %room_id, "📝 Envoi d'un message dans le salon");
    
    validate_user_id(author_id as i32)?;
    validate_message_content(content, hub.config.limits.max_message_length)?;
    
    // Vérification du rate limiting
    if !hub.check_rate_limit(author_id as i32).await {
        return Err(ChatError::rate_limit_exceeded_simple("send_message"));
    }
    
    let mut tx = hub.db.begin().await
        .map_err(|e| ChatError::from_sqlx_error("begin_transaction", e))?;
    
    // Vérifier que l'utilisateur est membre du salon
    let is_member: bool = query("
        SELECT EXISTS(
            SELECT 1 FROM conversation_members 
            WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL
        )
    ")
    .bind(room_id)
    .bind(author_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("check_membership", e))?
    .get(0);
    
    if !is_member {
        return Err(ChatError::unauthorized("send_room_message"));
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
    .bind(room_id)
    .bind(content)
    .bind(parent_message_id)
    .bind(&message_metadata)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("insert_message", e))?;
    
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
    process_mentions(&mut tx, message_id, content).await?;
    
    tx.commit().await
        .map_err(|e| ChatError::from_sqlx_error("commit_transaction", e))?;
    
    // Incrémentation des statistiques
    hub.increment_message_count().await;
    
    // Diffusion en temps réel
    broadcast_room_message(hub, room_id, message_id, author_id, username, content, timestamp, parent_message_id).await?;
    
    tracing::info!(message_id = %message_id, room_id = %room_id, "✅ Message envoyé dans le salon");
    Ok(message_id)
}

/// Épingler/désépingler un message
pub async fn pin_message(hub: &ChatHub, room_id: i64, message_id: i64, user_id: i64, pin: bool) -> Result<()> {
    tracing::info!(user_id = %user_id, room_id = %room_id, message_id = %message_id, pin = %pin, "📌 Épinglage de message");
    
    let mut tx = hub.db.begin().await
        .map_err(|e| ChatError::from_sqlx_error("begin_transaction", e))?;
    
    // Vérifier les permissions (propriétaire ou modérateur)
    let user_role: Option<String> = query("
        SELECT role FROM conversation_members 
        WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL
    ")
    .bind(room_id)
    .bind(user_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("check_role", e))?
    .map(|row| row.get("role"));
    
    match user_role.as_deref() {
        Some("owner") | Some("moderator") => {},
        _ => return Err(ChatError::unauthorized("pin_message"))
    }
    
    // Mettre à jour le statut d'épinglage
    let rows_affected = query("
        UPDATE messages 
        SET is_pinned = $1, updated_at = NOW()
        WHERE id = $2 AND conversation_id = $3
    ")
    .bind(pin)
    .bind(message_id)
    .bind(room_id)
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
    .bind(if pin { "message_pinned" } else { "message_unpinned" })
    .bind(json!({
        "room_id": room_id,
        "message_id": message_id
    }))
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("audit_log", e))?;
    
    tx.commit().await
        .map_err(|e| ChatError::from_sqlx_error("commit_transaction", e))?;
    
    tracing::info!(message_id = %message_id, pin = %pin, "✅ Statut d'épinglage mis à jour");
    Ok(())
}

// ================================================================
// HISTORIQUE ET RECHERCHE
// ================================================================

/// Récupérer l'historique complet d'un salon
pub async fn fetch_room_history(
    hub: &ChatHub,
    room_id: i64,
    user_id: i64,
    limit: i64,
    before_message_id: Option<i64>
) -> Result<Vec<RoomMessage>> {
    tracing::info!(room_id = %room_id, user_id = %user_id, limit = %limit, "📚 Récupération de l'historique du salon");
    
    validate_user_id(user_id as i32)?;
    let validated_limit = validate_limit(limit)?;
    
    // Vérifier que l'utilisateur est membre
    let is_member: bool = query("
        SELECT EXISTS(
            SELECT 1 FROM conversation_members 
            WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL
        )
    ")
    .bind(room_id)
    .bind(user_id)
    .fetch_one(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("check_membership", e))?
    .get(0);
    
    if !is_member {
        return Err(ChatError::unauthorized("fetch_room_history"));
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
    
    let mut query_obj = query_as::<_, EnhancedRoomMessage>(&query_builder)
        .bind(room_id);
    
    if let Some(before_id) = before_message_id {
        query_obj = query_obj.bind(before_id);
    }
    
    let messages = query_obj
        .bind(validated_limit)
        .fetch_all(&hub.db)
        .await
        .map_err(|e| ChatError::from_sqlx_error("fetch_room_history", e))?;
    
    tracing::info!(room_id = %room_id, message_count = %messages.len(), "✅ Historique du salon récupéré");
    Ok(messages)
}

/// Récupérer les messages épinglés d'un salon
pub async fn fetch_pinned_messages(hub: &ChatHub, room_id: i64, user_id: i64) -> Result<Vec<RoomMessage>> {
    tracing::info!(room_id = %room_id, user_id = %user_id, "📌 Récupération des messages épinglés");
    
    // Vérifier membership
    let is_member: bool = query("
        SELECT EXISTS(
            SELECT 1 FROM conversation_members 
            WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL
        )
    ")
    .bind(room_id)
    .bind(user_id)
    .fetch_one(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("check_membership", e))?
    .get(0);
    
    if !is_member {
        return Err(ChatError::unauthorized("fetch_pinned_messages"));
    }
    
    let messages = query_as::<_, RoomMessage>("
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
    .bind(room_id)
    .fetch_all(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("fetch_pinned_messages", e))?;
    
    tracing::info!(room_id = %room_id, pinned_count = %messages.len(), "✅ Messages épinglés récupérés");
    Ok(messages)
}

// ================================================================
// STATISTIQUES ET ADMINISTRATION
// ================================================================

/// Obtenir les statistiques d'un salon
pub async fn get_room_stats(hub: &ChatHub, room_id: i64) -> Result<RoomStats> {
    tracing::info!(room_id = %room_id, "📊 Récupération des statistiques du salon");
    
    let stats = query_as::<_, RoomStats>("
        SELECT 
            c.id as room_id,
            c.name as room_name,
            COUNT(DISTINCT m.id) as total_messages,
            COUNT(DISTINCT cm.user_id) FILTER (WHERE cm.left_at IS NULL) as total_members,
            COUNT(DISTINCT cm.user_id) FILTER (WHERE cm.left_at IS NULL AND u.last_activity > NOW() - INTERVAL '1 hour') as active_members,
            MAX(m.created_at) as last_activity,
            COUNT(DISTINCT m.id) FILTER (WHERE m.is_pinned = TRUE) as pinned_messages
        FROM conversations c
        LEFT JOIN conversation_members cm ON cm.conversation_id = c.id
        LEFT JOIN users u ON u.id = cm.user_id
        LEFT JOIN messages m ON m.conversation_id = c.id
        WHERE c.id = $1
        GROUP BY c.id, c.name
    ")
    .bind(room_id)
    .fetch_one(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("get_room_stats", e))?;
    
    tracing::info!(room_id = %room_id, "✅ Statistiques du salon récupérées");
    Ok(stats)
}

/// Lister les membres d'un salon
pub async fn list_room_members(hub: &ChatHub, room_id: i64, requesting_user_id: i64) -> Result<Vec<RoomMember>> {
    tracing::info!(room_id = %room_id, requesting_user = %requesting_user_id, "👥 Récupération de la liste des membres");
    
    // Vérifier que l'utilisateur est membre
    let is_member: bool = query("
        SELECT EXISTS(
            SELECT 1 FROM conversation_members 
            WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL
        )
    ")
    .bind(room_id)
    .bind(requesting_user_id)
    .fetch_one(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("check_membership", e))?
    .get(0);
    
    if !is_member {
        return Err(ChatError::unauthorized("list_room_members"));
    }
    
    let members = query_as::<_, RoomMember>("
        SELECT id, conversation_id, user_id, role, joined_at, left_at, is_muted
        FROM conversation_members
        WHERE conversation_id = $1 AND left_at IS NULL
        ORDER BY 
            CASE role 
                WHEN 'owner' THEN 1 
                WHEN 'moderator' THEN 2 
                ELSE 3 
            END,
            joined_at ASC
    ")
    .bind(room_id)
    .fetch_all(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("list_room_members", e))?;
    
    tracing::info!(room_id = %room_id, member_count = %members.len(), "✅ Liste des membres récupérée");
    Ok(members)
}

// ================================================================
// FONCTIONS UTILITAIRES
// ================================================================

/// Traiter les mentions dans un message
async fn process_mentions(tx: &mut Transaction<'_, Postgres>, message_id: i64, content: &str) -> Result<()> {
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
            .map_err(|e| ChatError::from_sqlx_error("insert_mention", e))?;
        }
    }
    
    Ok(())
}

/// Diffuser un message en temps réel aux membres du salon
async fn broadcast_room_message(
    hub: &ChatHub,
    room_id: i64,
    message_id: i64,
    author_id: i64,
    username: &str,
    content: &str,
    timestamp: DateTime<Utc>,
    parent_message_id: Option<i64>
) -> Result<()> {
    let clients = hub.clients.read().await;
    
    // Récupérer la liste des membres connectés
    let member_ids: Vec<i64> = query("
        SELECT user_id 
        FROM conversation_members 
        WHERE conversation_id = $1 AND left_at IS NULL
    ")
    .bind(room_id)
    .fetch_all(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("get_room_members", e))?
    .into_iter()
    .map(|row| row.get::<i64, _>("user_id"))
    .collect();
    
    let payload = json!({
        "type": "room_message",
        "data": {
            "id": message_id,
            "roomId": room_id,
            "authorId": author_id,
            "username": username,
            "content": content,
            "timestamp": timestamp,
            "parentMessageId": parent_message_id,
            "isThread": parent_message_id.is_some()
        }
    });
    
    let mut successful_sends = 0;
    let mut failed_sends = 0;
    
    for user_id in member_ids {
        if let Some(client) = clients.get(&(user_id as i32)) {
            if client.send_text(&payload.to_string()) {
                successful_sends += 1;
            } else {
                failed_sends += 1;
            }
        } else {
            failed_sends += 1;
        }
    }
    
    tracing::info!(
        room_id = %room_id, 
        message_id = %message_id, 
        successful_sends = %successful_sends, 
        failed_sends = %failed_sends,
        "📡 Message diffusé aux membres du salon"
    );
    
    Ok(())
} 