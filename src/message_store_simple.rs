// Version simplifiée du message store qui fonctionne avec le schéma existant
use crate::error::{ChatError, Result};
use chrono::{DateTime, Utc};
use serde::{Serialize, Deserialize};
use sqlx::PgPool;
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum MessageType {
    RoomMessage,
    DirectMessage,
    SystemMessage,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimpleMessage {
    pub id: i64,
    pub content: String,
    pub author_id: i32,
    pub author_username: String,
    pub room_id: Option<String>,
    pub recipient_id: Option<i32>,
    pub created_at: DateTime<Utc>,
    pub message_type: MessageType,
}

pub struct SimpleMessageStore {
    db: PgPool,
}

impl SimpleMessageStore {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    // Récupérer les messages d'un salon
    pub async fn get_room_messages(
        &self,
        room_id: &str,
        limit: i32,
    ) -> Result<Vec<SimpleMessage>> {
        let rows = sqlx::query!(
            "SELECT id, content, sender_id, username, room_id, created_at 
             FROM room_messages 
             WHERE room_id = $1 
             ORDER BY created_at DESC 
             LIMIT $2",
            room_id,
            limit
        )
        .fetch_all(&self.db)
        .await
        .map_err(ChatError::Database)?;

        let mut messages = Vec::new();
        for row in rows {
            messages.push(SimpleMessage {
                id: row.id,
                content: row.content,
                author_id: row.sender_id,
                author_username: row.username,
                room_id: Some(row.room_id),
                recipient_id: None,
                created_at: row.created_at,
                message_type: MessageType::RoomMessage,
            });
        }

        Ok(messages)
    }

    // Récupérer les DM entre deux utilisateurs
    pub async fn get_dm_messages(
        &self,
        user1_id: i32,
        user2_id: i32,
        limit: i32,
    ) -> Result<Vec<SimpleMessage>> {
        let rows = sqlx::query!(
            "SELECT id, content, sender_id, sender_username, recipient_id, created_at 
             FROM direct_messages 
             WHERE (sender_id = $1 AND recipient_id = $2) 
                OR (sender_id = $2 AND recipient_id = $1)
             ORDER BY created_at DESC 
             LIMIT $3",
            user1_id,
            user2_id,
            limit
        )
        .fetch_all(&self.db)
        .await
        .map_err(ChatError::Database)?;

        let mut messages = Vec::new();
        for row in rows {
            messages.push(SimpleMessage {
                id: row.id,
                content: row.content,
                author_id: row.sender_id,
                author_username: row.sender_username,
                room_id: None,
                recipient_id: Some(row.recipient_id),
                created_at: row.created_at,
                message_type: MessageType::DirectMessage,
            });
        }

        Ok(messages)
    }

    // Envoyer un message dans un salon
    pub async fn send_room_message(
        &self,
        room_id: &str,
        sender_id: i32,
        username: &str,
        content: &str,
    ) -> Result<SimpleMessage> {
        let now = Utc::now();
        
        let message_id = sqlx::query_scalar!(
            "INSERT INTO room_messages (room_id, sender_id, username, content, created_at) 
             VALUES ($1, $2, $3, $4, $5) 
             RETURNING id",
            room_id,
            sender_id,
            username,
            content,
            now
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?;

        Ok(SimpleMessage {
            id: message_id,
            content: content.to_string(),
            author_id: sender_id,
            author_username: username.to_string(),
            room_id: Some(room_id.to_string()),
            recipient_id: None,
            created_at: now,
            message_type: MessageType::RoomMessage,
        })
    }

    // Envoyer un DM
    pub async fn send_dm_message(
        &self,
        sender_id: i32,
        sender_username: &str,
        recipient_id: i32,
        content: &str,
    ) -> Result<SimpleMessage> {
        let now = Utc::now();
        
        let message_id = sqlx::query_scalar!(
            "INSERT INTO direct_messages (sender_id, sender_username, recipient_id, content, created_at) 
             VALUES ($1, $2, $3, $4, $5) 
             RETURNING id",
            sender_id,
            sender_username,
            recipient_id,
            content,
            now
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?;

        Ok(SimpleMessage {
            id: message_id,
            content: content.to_string(),
            author_id: sender_id,
            author_username: sender_username.to_string(),
            room_id: None,
            recipient_id: Some(recipient_id),
            created_at: now,
            message_type: MessageType::DirectMessage,
        })
    }

    // Rechercher des messages
    pub async fn search_messages(
        &self,
        query: &str,
        limit: i32,
    ) -> Result<Vec<SimpleMessage>> {
        let search_pattern = format!("%{}%", query);
        let mut messages = Vec::new();

        // Rechercher dans les messages de salon
        let room_rows = sqlx::query!(
            "SELECT id, content, sender_id, username, room_id, created_at 
             FROM room_messages 
             WHERE content ILIKE $1 
             ORDER BY created_at DESC 
             LIMIT $2",
            search_pattern,
            limit / 2
        )
        .fetch_all(&self.db)
        .await
        .map_err(ChatError::Database)?;

        for row in room_rows {
            messages.push(SimpleMessage {
                id: row.id,
                content: row.content,
                author_id: row.sender_id,
                author_username: row.username,
                room_id: Some(row.room_id),
                recipient_id: None,
                created_at: row.created_at,
                message_type: MessageType::RoomMessage,
            });
        }

        // Rechercher dans les DM
        let dm_rows = sqlx::query!(
            "SELECT id, content, sender_id, sender_username, recipient_id, created_at 
             FROM direct_messages 
             WHERE content ILIKE $1 
             ORDER BY created_at DESC 
             LIMIT $2",
            search_pattern,
            limit / 2
        )
        .fetch_all(&self.db)
        .await
        .map_err(ChatError::Database)?;

        for row in dm_rows {
            messages.push(SimpleMessage {
                id: row.id,
                content: row.content,
                author_id: row.sender_id,
                author_username: row.sender_username,
                room_id: None,
                recipient_id: Some(row.recipient_id),
                created_at: row.created_at,
                message_type: MessageType::DirectMessage,
            });
        }

        // Trier par date décroissante
        messages.sort_by(|a, b| b.created_at.cmp(&a.created_at));
        messages.truncate(limit as usize);

        Ok(messages)
    }

    // Obtenir les statistiques
    pub async fn get_stats(&self) -> Result<MessageStats> {
        let room_count = sqlx::query_scalar!(
            "SELECT COUNT(*) FROM room_messages"
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?
        .unwrap_or(0);

        let dm_count = sqlx::query_scalar!(
            "SELECT COUNT(*) FROM direct_messages"
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?
        .unwrap_or(0);

        let today_count = sqlx::query_scalar!(
            "SELECT COUNT(*) FROM (
                SELECT created_at FROM room_messages WHERE created_at >= CURRENT_DATE
                UNION ALL
                SELECT created_at FROM direct_messages WHERE created_at >= CURRENT_DATE
             ) AS all_messages"
        )
        .fetch_one(&self.db)
        .await
        .map_err(ChatError::Database)?
        .unwrap_or(0);

        Ok(MessageStats {
            total_room_messages: room_count,
            total_dm_messages: dm_count,
            messages_today: today_count,
            total_messages: room_count + dm_count,
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageStats {
    pub total_room_messages: i64,
    pub total_dm_messages: i64,
    pub messages_today: i64,
    pub total_messages: i64,
} 