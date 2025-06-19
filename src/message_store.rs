use crate::error::{ChatError, Result};
use chrono::{DateTime, Utc};
use serde::{Serialize, Deserialize};
use sqlx::PgPool;
use std::collections::HashMap;

/// Types de messages différenciés
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum MessageType {
    RoomMessage,
    DirectMessage,
    SystemMessage,
}

/// Statut des messages
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum MessageStatus {
    Sent,
    Delivered,
    Read,
    Edited,
    Deleted,
}

/// Message unifié avec séparation logique
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub id: i64,
    pub message_type: MessageType,
    pub content: String,
    pub author_id: i32,
    pub author_username: String,
    
    // Pour les messages de salon
    pub room_id: Option<String>,
    
    // Pour les messages directs
    pub recipient_id: Option<i32>,
    pub recipient_username: Option<String>,
    
    // Métadonnées communes
    pub created_at: DateTime<Utc>,
    pub updated_at: Option<DateTime<Utc>>,
    pub status: MessageStatus,
    pub is_pinned: bool,
    pub is_edited: bool,
    pub original_content: Option<String>, // Contenu original avant édition
    
    // Thread/réponse
    pub parent_message_id: Option<i64>,
    pub thread_count: i32,
    
    // Réactions
    pub reactions: HashMap<String, Vec<i32>>, // emoji -> liste d'user_ids
    
    // Attachments
    pub attachments: Vec<MessageAttachment>,
    
    // Mentions
    pub mentions: Vec<i32>, // user_ids mentionnés
    
    // Métadonnées de modération
    pub is_flagged: bool,
    pub moderation_notes: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageAttachment {
    pub id: i64,
    pub filename: String,
    pub original_filename: String,
    pub mime_type: String,
    pub size_bytes: i64,
    pub url: String,
    pub thumbnail_url: Option<String>,
    pub uploaded_at: DateTime<Utc>,
}

/// Gestionnaire de stockage de messages séparé
pub struct MessageStore {
    db: PgPool,
}

impl MessageStore {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    // ================================================
    // MESSAGES DE SALON
    // ================================================
    
    /// Envoyer un message dans un salon
    pub async fn send_room_message(
        &self,
        room_id: &str,
        author_id: i32,
        author_username: &str,
        content: &str,
        parent_message_id: Option<i64>,
        mentions: Vec<i32>,
    ) -> Result<Message> {
        let now = Utc::now();
        
        let message_id = sqlx::query_scalar!(
            r#"
            INSERT INTO messages (
                message_type, content, author_id, author_username, 
                room_id, created_at, status, parent_message_id
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING id
            "#,
            "room_message" as _,
            content,
            author_id,
            author_username,
            room_id,
            now,
            "sent" as _,
            parent_message_id
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?;

        // Insérer les mentions
        for user_id in &mentions {
            sqlx::query!(
                "INSERT INTO message_mentions (message_id, user_id, created_at) VALUES ($1, $2, $3)",
                message_id,
                user_id,
                now
            )
            .execute(&self.db)
            .await
            .map_err(ChatError::Database)?;
        }

        // Mettre à jour le thread si c'est une réponse
        if let Some(parent_id) = parent_message_id {
            sqlx::query!(
                "UPDATE messages SET thread_count = thread_count + 1 WHERE id = $1",
                parent_id
            )
            .execute(&self.db)
            .await
            .map_err(ChatError::Database)?;
        }

        self.get_message_by_id(message_id).await
    }

    /// Récupérer l'historique d'un salon avec pagination
    pub async fn get_room_history(
        &self,
        room_id: &str,
        limit: i64,
        before_id: Option<i64>,
        include_threads: bool,
    ) -> Result<Vec<Message>> {
        let mut query = r#"
            SELECT m.*, 
                   COALESCE(array_agg(mm.user_id) FILTER (WHERE mm.user_id IS NOT NULL), ARRAY[]::int[]) as mention_ids
            FROM messages m
            LEFT JOIN message_mentions mm ON m.id = mm.message_id
            WHERE m.room_id = $1 
              AND m.message_type = 'room_message'
              AND m.status != 'deleted'
        "#.to_string();

        if !include_threads {
            query.push_str(" AND m.parent_message_id IS NULL");
        }

        if let Some(before_id) = before_id {
            query.push_str(&format!(" AND m.id < {}", before_id));
        }

        query.push_str(" GROUP BY m.id ORDER BY m.created_at DESC");
        query.push_str(&format!(" LIMIT {}", limit));

        let rows = sqlx::query(&query)
            .bind(room_id)
            .fetch_all(&self.db)
            .await
            .map_err(ChatError::Database)?;

        let mut messages = Vec::new();
        for row in rows {
            let message = self.row_to_message(row).await?;
            messages.push(message);
        }

        Ok(messages)
    }

    /// Épingler/désépingler un message dans un salon
    pub async fn pin_room_message(
        &self,
        message_id: i64,
        room_id: &str,
        moderator_id: i32,
        is_pinned: bool,
    ) -> Result<()> {
        // Vérifier que le message appartient au salon
        let exists = sqlx::query_scalar!(
            "SELECT EXISTS(SELECT 1 FROM messages WHERE id = $1 AND room_id = $2)",
            message_id,
            room_id
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?
        .unwrap_or(false);

        if !exists {
            return Err(ChatError::configuration_error("Message non trouvé dans ce salon".to_string()));
        }

        // Limiter le nombre de messages épinglés (max 10 par salon)
        if is_pinned {
            let pinned_count = sqlx::query_scalar!(
                "SELECT COUNT(*) FROM messages WHERE room_id = $1 AND is_pinned = true",
                room_id
            )
            .fetch_one(&self.db)
            .await
            .map_err(ChatError::Database)?
            .unwrap_or(0);

            if pinned_count >= 10 {
                return Err(ChatError::configuration_error("Limite de messages épinglés atteinte (10 par salon)".to_string()));
            }
        }

        sqlx::query!(
            "UPDATE messages SET is_pinned = $1, updated_at = $2 WHERE id = $3",
            is_pinned,
            Utc::now(),
            message_id
        )
        .execute(&self.db)
        .await
        .map_err(ChatError::Database)?;

        // Log de l'action
        sqlx::query!(
            r#"
            INSERT INTO moderation_log (
                moderator_id, target_type, target_id, action, details, created_at
            ) VALUES ($1, 'message', $2, $3, $4, $5)
            "#,
            moderator_id,
            message_id,
            if is_pinned { "pin" } else { "unpin" },
            format!("Message {} dans le salon {}", if is_pinned { "épinglé" } else { "désépinglé" }, room_id),
            Utc::now()
        )
        .execute(&self.db)
        .await
        .map_err(ChatError::Database)?;

        Ok(())
    }

    /// Récupérer les messages épinglés d'un salon
    pub async fn get_pinned_messages(&self, room_id: &str) -> Result<Vec<Message>> {
        let rows = sqlx::query!(
            r#"
            SELECT m.*, 
                   COALESCE(array_agg(mm.user_id) FILTER (WHERE mm.user_id IS NOT NULL), ARRAY[]::int[]) as mention_ids
            FROM messages m
            LEFT JOIN message_mentions mm ON m.id = mm.message_id
            WHERE m.room_id = $1 
              AND m.is_pinned = true 
              AND m.status != 'deleted'
            GROUP BY m.id
            ORDER BY m.created_at DESC
            "#,
            room_id
        )
        .fetch_all(&self.db)
        .await
        .map_err(ChatError::Database)?;

        let mut messages = Vec::new();
        for row in rows {
            let message = self.row_to_message_from_detailed_query(row).await?;
            messages.push(message);
        }

        Ok(messages)
    }

    // ================================================
    // MESSAGES DIRECTS (DM)
    // ================================================
    
    /// Envoyer un message direct
    pub async fn send_direct_message(
        &self,
        author_id: i32,
        author_username: &str,
        recipient_id: i32,
        recipient_username: &str,
        content: &str,
        parent_message_id: Option<i64>,
    ) -> Result<Message> {
        // Vérifier que l'utilisateur n'est pas bloqué
        let is_blocked = self.is_user_blocked(author_id, recipient_id).await?;
        if is_blocked {
            return Err(ChatError::PermissionDenied("Utilisateur bloqué".to_string()));
        }

        let now = Utc::now();
        
        let message_id = sqlx::query_scalar!(
            r#"
            INSERT INTO messages (
                message_type, content, author_id, author_username, 
                recipient_id, recipient_username, created_at, status, parent_message_id
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            RETURNING id
            "#,
            "direct_message" as _,
            content,
            author_id,
            author_username,
            recipient_id,
            recipient_username,
            now,
            "sent" as _,
            parent_message_id
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?;

        // Mettre à jour le thread si c'est une réponse
        if let Some(parent_id) = parent_message_id {
            sqlx::query!(
                "UPDATE messages SET thread_count = thread_count + 1 WHERE id = $1",
                parent_id
            )
            .execute(&self.db)
            .await
            .map_err(ChatError::Database)?;
        }

        self.get_message_by_id(message_id).await
    }

    /// Récupérer l'historique des messages directs entre deux utilisateurs
    pub async fn get_dm_history(
        &self,
        user1_id: i32,
        user2_id: i32,
        limit: i64,
        before_id: Option<i64>,
    ) -> Result<Vec<Message>> {
        let mut query = r#"
            SELECT m.*,
                   ARRAY[]::int[] as mention_ids
            FROM messages m
            WHERE m.message_type = 'direct_message'
              AND m.status != 'deleted'
              AND (
                  (m.author_id = $1 AND m.recipient_id = $2) OR
                  (m.author_id = $2 AND m.recipient_id = $1)
              )
        "#.to_string();

        if let Some(before_id) = before_id {
            query.push_str(&format!(" AND m.id < {}", before_id));
        }

        query.push_str(" ORDER BY m.created_at DESC");
        query.push_str(&format!(" LIMIT {}", limit));

        let rows = sqlx::query(&query)
            .bind(user1_id)
            .bind(user2_id)
            .fetch_all(&self.db)
            .await
            .map_err(ChatError::Database)?;

        let mut messages = Vec::new();
        for row in rows {
            let message = self.row_to_message(row).await?;
            messages.push(message);
        }

        Ok(messages)
    }

    /// Marquer un message DM comme lu
    pub async fn mark_dm_as_read(&self, message_id: i64, user_id: i32) -> Result<()> {
        // Vérifier que l'utilisateur est le destinataire
        let is_recipient = sqlx::query_scalar!(
            "SELECT EXISTS(SELECT 1 FROM messages WHERE id = $1 AND recipient_id = $2)",
            message_id,
            user_id
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?
        .unwrap_or(false);

        if !is_recipient {
            return Err(ChatError::PermissionDenied("Non autorisé à marquer ce message comme lu".to_string()));
        }

        sqlx::query!(
            "UPDATE messages SET status = 'read', updated_at = $1 WHERE id = $2",
            Utc::now(),
            message_id
        )
        .execute(&self.db)
        .await
        .map_err(ChatError::Database)?;

        Ok(())
    }

    /// Récupérer les conversations DM d'un utilisateur
    pub async fn get_dm_conversations(&self, user_id: i32) -> Result<Vec<DMConversation>> {
        let rows = sqlx::query!(
            r#"
            SELECT 
                CASE 
                    WHEN author_id = $1 THEN recipient_id 
                    ELSE author_id 
                END as other_user_id,
                CASE 
                    WHEN author_id = $1 THEN recipient_username 
                    ELSE author_username 
                END as other_username,
                MAX(created_at) as last_message_at,
                COUNT(*) FILTER (WHERE recipient_id = $1 AND status != 'read') as unread_count,
                (SELECT content FROM messages m2 
                 WHERE m2.message_type = 'direct_message' 
                   AND ((m2.author_id = $1 AND m2.recipient_id = other_user_id) OR 
                        (m2.author_id = other_user_id AND m2.recipient_id = $1))
                   AND m2.status != 'deleted'
                 ORDER BY m2.created_at DESC LIMIT 1) as last_message_content
            FROM messages
            WHERE message_type = 'direct_message'
              AND (author_id = $1 OR recipient_id = $1)
              AND status != 'deleted'
            GROUP BY other_user_id, other_username
            ORDER BY last_message_at DESC
            "#,
            user_id
        )
        .fetch_all(&self.db)
        .await
        .map_err(ChatError::Database)?;

        let mut conversations = Vec::new();
        for row in rows {
            conversations.push(DMConversation {
                other_user_id: row.other_user_id,
                other_username: row.other_username,
                last_message_at: row.last_message_at,
                unread_count: row.unread_count.unwrap_or(0) as u32,
                last_message_preview: row.last_message_content,
            });
        }

        Ok(conversations)
    }

    // ================================================
    // RÉACTIONS
    // ================================================
    
    /// Ajouter une réaction à un message
    pub async fn add_reaction(
        &self,
        message_id: i64,
        user_id: i32,
        emoji: &str,
    ) -> Result<()> {
        // Vérifier que le message existe
        let message_exists = sqlx::query_scalar!(
            "SELECT EXISTS(SELECT 1 FROM messages WHERE id = $1 AND status != 'deleted')",
            message_id
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?
        .unwrap_or(false);

        if !message_exists {
            return Err(ChatError::configuration_error("Message non trouvé".to_string()));
        }

        // Vérifier que la réaction n'existe pas déjà
        let reaction_exists = sqlx::query_scalar!(
            "SELECT EXISTS(SELECT 1 FROM message_reactions WHERE message_id = $1 AND user_id = $2 AND emoji = $3)",
            message_id,
            user_id,
            emoji
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?
        .unwrap_or(false);

        if reaction_exists {
            return Err(ChatError::ReactionAlreadyExists);
        }

        // Ajouter la réaction
        sqlx::query!(
            "INSERT INTO message_reactions (message_id, user_id, emoji, created_at) VALUES ($1, $2, $3, $4)",
            message_id,
            user_id,
            emoji,
            Utc::now()
        )
        .execute(&self.db)
        .await
        .map_err(ChatError::Database)?;

        Ok(())
    }

    /// Supprimer une réaction
    pub async fn remove_reaction(
        &self,
        message_id: i64,
        user_id: i32,
        emoji: &str,
    ) -> Result<()> {
        let deleted = sqlx::query!(
            "DELETE FROM message_reactions WHERE message_id = $1 AND user_id = $2 AND emoji = $3",
            message_id,
            user_id,
            emoji
        )
        .execute(&self.db)
        .await
        .map_err(ChatError::Database)?
        .rows_affected();

        if deleted == 0 {
            return Err(ChatError::ReactionNotFound);
        }

        Ok(())
    }

    /// Récupérer les réactions d'un message
    pub async fn get_message_reactions(&self, message_id: i64) -> Result<HashMap<String, Vec<i32>>> {
        let rows = sqlx::query!(
            "SELECT emoji, user_id FROM message_reactions WHERE message_id = $1 ORDER BY created_at",
            message_id
        )
        .fetch_all(&self.db)
        .await
        .map_err(ChatError::Database)?;

        let mut reactions: HashMap<String, Vec<i32>> = HashMap::new();
        for row in rows {
            reactions.entry(row.emoji).or_insert_with(Vec::new).push(row.user_id);
        }

        Ok(reactions)
    }

    // ================================================
    // ÉDITION ET SUPPRESSION
    // ================================================
    
    /// Éditer un message
    pub async fn edit_message(
        &self,
        message_id: i64,
        user_id: i32,
        new_content: &str,
    ) -> Result<Message> {
        // Vérifier que l'utilisateur est l'auteur
        let message = sqlx::query!(
            "SELECT author_id, content FROM messages WHERE id = $1 AND status != 'deleted'",
            message_id
        )
        .fetch_optional(&self.db)
        .await
        .map_err(ChatError::Database)?;

        let message = message.ok_or_else(|| ChatError::configuration_error("Message non trouvé".to_string()))?;

        if message.author_id != user_id {
            return Err(ChatError::PermissionDenied("Seul l'auteur peut éditer ce message".to_string()));
        }

        // Sauvegarder l'ancien contenu si c'est la première édition
        let original_content = if message.content != new_content {
            Some(message.content)
        } else {
            None
        };

        sqlx::query!(
            r#"
            UPDATE messages 
            SET content = $1, 
                updated_at = $2, 
                is_edited = true,
                original_content = COALESCE(original_content, $3)
            WHERE id = $4
            "#,
            new_content,
            Utc::now(),
            original_content,
            message_id
        )
        .execute(&self.db)
        .await
        .map_err(ChatError::Database)?;

        self.get_message_by_id(message_id).await
    }

    /// Supprimer un message (soft delete)
    pub async fn delete_message(
        &self,
        message_id: i64,
        user_id: i32,
        is_moderator: bool,
    ) -> Result<()> {
        // Vérifier les permissions
        if !is_moderator {
            let is_author = sqlx::query_scalar!(
                "SELECT EXISTS(SELECT 1 FROM messages WHERE id = $1 AND author_id = $2)",
                message_id,
                user_id
            )
            .fetch_one(&self.db)
            .await
            .map_err(ChatError::Database)?
            .unwrap_or(false);

            if !is_author {
                return Err(ChatError::PermissionDenied("Seul l'auteur ou un modérateur peut supprimer ce message".to_string()));
            }
        }

        sqlx::query!(
            "UPDATE messages SET status = 'deleted', updated_at = $1 WHERE id = $2",
            Utc::now(),
            message_id
        )
        .execute(&self.db)
        .await
        .map_err(ChatError::Database)?;

        Ok(())
    }

    // ================================================
    // RECHERCHE
    // ================================================
    
    /// Rechercher dans les messages
    pub async fn search_messages(
        &self,
        query: &str,
        user_id: i32,
        room_id: Option<&str>,
        limit: i64,
    ) -> Result<Vec<Message>> {
        let search_query = if let Some(room_id) = room_id {
            // Recherche dans un salon spécifique
            r#"
            SELECT m.*, ARRAY[]::int[] as mention_ids
            FROM messages m
            WHERE m.room_id = $1
              AND m.message_type = 'room_message'
              AND m.status != 'deleted'
              AND m.content ILIKE $2
            ORDER BY m.created_at DESC
            LIMIT $3
            "#
        } else {
            // Recherche dans tous les messages accessibles à l'utilisateur
            r#"
            SELECT m.*, ARRAY[]::int[] as mention_ids
            FROM messages m
            WHERE m.status != 'deleted'
              AND m.content ILIKE $2
              AND (
                  m.message_type = 'room_message' OR
                  (m.message_type = 'direct_message' AND (m.author_id = $1 OR m.recipient_id = $1))
              )
            ORDER BY m.created_at DESC
            LIMIT $3
            "#
        };

        let search_pattern = format!("%{}%", query);
        
        let rows = if room_id.is_some() {
            sqlx::query(search_query)
                .bind(room_id.unwrap())
                .bind(&search_pattern)
                .bind(limit)
                .fetch_all(&self.db)
                .await
                .map_err(ChatError::Database)?
        } else {
            sqlx::query(search_query)
                .bind(user_id)
                .bind(&search_pattern)
                .bind(limit)
                .fetch_all(&self.db)
                .await
                .map_err(ChatError::Database)?
        };

        let mut messages = Vec::new();
        for row in rows {
            let message = self.row_to_message(row).await?;
            messages.push(message);
        }

        Ok(messages)
    }

    // ================================================
    // UTILITAIRES PRIVÉS
    // ================================================
    
    async fn get_message_by_id(&self, message_id: i64) -> Result<Message> {
        let row = sqlx::query!(
            r#"
            SELECT m.*, 
                   COALESCE(array_agg(mm.user_id) FILTER (WHERE mm.user_id IS NOT NULL), ARRAY[]::int[]) as mention_ids
            FROM messages m
            LEFT JOIN message_mentions mm ON m.id = mm.message_id
            WHERE m.id = $1
            GROUP BY m.id
            "#,
            message_id
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?;

        self.row_to_message_from_detailed_query(row).await
    }

    async fn row_to_message(&self, row: sqlx::Row) -> Result<Message> {
        use sqlx::Row;
        
        let message_id: i64 = row.try_get("id").map_err(|e| ChatError::from_sqlx_error("database_operation", e.into()))?;
        
        // Récupérer les réactions
        let reactions = self.get_message_reactions(message_id).await?;
        
        // Récupérer les mentions (si disponibles)
        let mentions: Vec<i32> = row.try_get("mention_ids")
            .unwrap_or_else(|_| Vec::new());

        Ok(Message {
            id: message_id,
            message_type: match row.try_get::<String, _>("message_type").map_err(|e| ChatError::from_sqlx_error("database_operation", e.into()))?.as_str() {
                "room_message" => MessageType::RoomMessage,
                "direct_message" => MessageType::DirectMessage,
                "system_message" => MessageType::SystemMessage,
                _ => MessageType::SystemMessage,
            },
            content: row.try_get("content").map_err(|e| ChatError::from_sqlx_error("database_operation", e.into()))?,
            author_id: row.try_get("author_id").map_err(|e| ChatError::from_sqlx_error("database_operation", e.into()))?,
            author_username: row.try_get("author_username").map_err(|e| ChatError::from_sqlx_error("database_operation", e.into()))?,
            room_id: row.try_get("room_id").ok(),
            recipient_id: row.try_get("recipient_id").ok(),
            recipient_username: row.try_get("recipient_username").ok(),
            created_at: row.try_get("created_at").map_err(|e| ChatError::from_sqlx_error("database_operation", e.into()))?,
            updated_at: row.try_get("updated_at").ok(),
            status: match row.try_get::<String, _>("status").map_err(|e| ChatError::from_sqlx_error("database_operation", e.into()))?.as_str() {
                "sent" => MessageStatus::Sent,
                "delivered" => MessageStatus::Delivered,
                "read" => MessageStatus::Read,
                "edited" => MessageStatus::Edited,
                "deleted" => MessageStatus::Deleted,
                _ => MessageStatus::Sent,
            },
            is_pinned: row.try_get("is_pinned").unwrap_or(false),
            is_edited: row.try_get("is_edited").unwrap_or(false),
            original_content: row.try_get("original_content").ok(),
            parent_message_id: row.try_get("parent_message_id").ok(),
            thread_count: row.try_get("thread_count").unwrap_or(0),
            reactions,
            attachments: Vec::new(), // TODO: récupérer les attachments
            mentions,
            is_flagged: row.try_get("is_flagged").unwrap_or(false),
            moderation_notes: row.try_get("moderation_notes").ok(),
        })
    }

    async fn row_to_message_from_detailed_query(&self, row: sqlx::postgres::PgRow) -> Result<Message> {
        let message_id = row.id;
        
        // Récupérer les réactions
        let reactions = self.get_message_reactions(message_id).await?;
        
        let mentions: Vec<i32> = row.mention_ids.unwrap_or_else(Vec::new);

        Ok(Message {
            id: message_id,
            message_type: match row.message_type.as_str() {
                "room_message" => MessageType::RoomMessage,
                "direct_message" => MessageType::DirectMessage,
                "system_message" => MessageType::SystemMessage,
                _ => MessageType::SystemMessage,
            },
            content: row.content,
            author_id: row.author_id,
            author_username: row.author_username,
            room_id: row.room_id,
            recipient_id: row.recipient_id,
            recipient_username: row.recipient_username,
            created_at: row.created_at,
            updated_at: row.updated_at,
            status: match row.status.as_str() {
                "sent" => MessageStatus::Sent,
                "delivered" => MessageStatus::Delivered,
                "read" => MessageStatus::Read,
                "edited" => MessageStatus::Edited,
                "deleted" => MessageStatus::Deleted,
                _ => MessageStatus::Sent,
            },
            is_pinned: row.is_pinned.unwrap_or(false),
            is_edited: row.is_edited.unwrap_or(false),
            original_content: row.original_content,
            parent_message_id: row.parent_message_id,
            thread_count: row.thread_count.unwrap_or(0),
            reactions,
            attachments: Vec::new(), // TODO: récupérer les attachments
            mentions,
            is_flagged: row.is_flagged.unwrap_or(false),
            moderation_notes: row.moderation_notes,
        })
    }

    async fn is_user_blocked(&self, user1_id: i32, user2_id: i32) -> Result<bool> {
        let is_blocked = sqlx::query_scalar!(
            "SELECT EXISTS(SELECT 1 FROM user_blocks WHERE blocker_id = $1 AND blocked_id = $2)",
            user2_id, // user2 bloque user1
            user1_id
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?
        .unwrap_or(false);

        Ok(is_blocked)
    }
}

/// Représentation d'une conversation DM
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DMConversation {
    pub other_user_id: i32,
    pub other_username: String,
    pub last_message_at: DateTime<Utc>,
    pub unread_count: u32,
    pub last_message_preview: Option<String>,
}

/// Statistiques de messages
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageStats {
    pub total_messages: i64,
    pub room_messages: i64,
    pub direct_messages: i64,
    pub messages_today: i64,
    pub messages_this_week: i64,
    pub top_rooms: Vec<(String, i64)>, // (room_id, message_count)
    pub active_users: Vec<(i32, String, i64)>, // (user_id, username, message_count)
}

impl MessageStore {
    /// Obtenir les statistiques de messages
    pub async fn get_message_stats(&self) -> Result<MessageStats> {
        let total_messages = sqlx::query_scalar!(
            "SELECT COUNT(*) FROM messages WHERE status != 'deleted'"
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?
        .unwrap_or(0);

        let room_messages = sqlx::query_scalar!(
            "SELECT COUNT(*) FROM messages WHERE message_type = 'room_message' AND status != 'deleted'"
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?
        .unwrap_or(0);

        let direct_messages = sqlx::query_scalar!(
            "SELECT COUNT(*) FROM messages WHERE message_type = 'direct_message' AND status != 'deleted'"
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?
        .unwrap_or(0);

        let messages_today = sqlx::query_scalar!(
            "SELECT COUNT(*) FROM messages WHERE created_at >= CURRENT_DATE AND status != 'deleted'"
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?
        .unwrap_or(0);

        let messages_this_week = sqlx::query_scalar!(
            "SELECT COUNT(*) FROM messages WHERE created_at >= CURRENT_DATE - INTERVAL '7 days' AND status != 'deleted'"
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?
        .unwrap_or(0);

        // Top salons par nombre de messages
        let top_rooms_rows = sqlx::query!(
            r#"
            SELECT room_id, COUNT(*) as message_count
            FROM messages 
            WHERE message_type = 'room_message' 
              AND status != 'deleted'
              AND room_id IS NOT NULL
            GROUP BY room_id
            ORDER BY message_count DESC
            LIMIT 10
            "#
        )
        .fetch_all(&self.db)
        .await
        .map_err(ChatError::Database)?;

        let top_rooms = top_rooms_rows.into_iter()
            .map(|row| (row.room_id.unwrap_or_else(|| "unknown".to_string()), row.message_count.unwrap_or(0)))
            .collect();

        // Utilisateurs les plus actifs
        let active_users_rows = sqlx::query!(
            r#"
            SELECT author_id, author_username, COUNT(*) as message_count
            FROM messages 
            WHERE status != 'deleted'
              AND created_at >= CURRENT_DATE - INTERVAL '30 days'
            GROUP BY author_id, author_username
            ORDER BY message_count DESC
            LIMIT 10
            "#
        )
        .fetch_all(&self.db)
        .await
        .map_err(ChatError::Database)?;

        let active_users = active_users_rows.into_iter()
            .map(|row| (row.author_id, row.author_username, row.message_count.unwrap_or(0)))
            .collect();

        Ok(MessageStats {
            total_messages,
            room_messages,
            direct_messages,
            messages_today,
            messages_this_week,
            top_rooms,
            active_users,
        })
    }
} 