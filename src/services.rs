//! Services métier du chat server

use crate::error::{ChatError, Result};
use crate::models::*;
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

/// Service de gestion des utilisateurs
pub struct UserService {
    db: Arc<PgPool>,
}

impl UserService {
    pub fn new(db: Arc<PgPool>) -> Self {
        Self { db }
    }

    pub async fn get_user_by_id(&self, user_id: Uuid) -> Result<Option<User>> {
        // TODO: Réactiver après migration DB
        /*
        let user = sqlx::query_as!(
            User,
            "SELECT * FROM users WHERE id = $1 AND is_active = true",
            user_id
        )
        .fetch_optional(&*self.db)
        .await
        .map_err(|e| ChatError::database_error("get_user_by_id", e))?;

        Ok(user)
        */
        
        // Placeholder temporaire
        tracing::warn!("get_user_by_id: Fonction temporairement désactivée (migration DB requise)");
        Ok(None)
    }

    pub async fn get_user_by_username(&self, username: &str) -> Result<Option<User>> {
        // TODO: Réactiver après migration DB
        /*
        let user = sqlx::query_as!(
            User,
            "SELECT * FROM users WHERE username = $1 AND is_active = true",
            username
        )
        .fetch_optional(&*self.db)
        .await
        .map_err(|e| ChatError::database_error("get_user_by_username", e))?;

        Ok(user)
        */
        
        // Placeholder temporaire
        tracing::warn!("get_user_by_username: Fonction temporairement désactivée (migration DB requise)");
        Ok(None)
    }
}

/// Service de gestion des messages
pub struct MessageService {
    db: Arc<PgPool>,
}

impl MessageService {
    pub fn new(db: Arc<PgPool>) -> Self {
        Self { db }
    }

    pub async fn get_message_by_id(&self, message_id: Uuid) -> Result<Option<Message>> {
        // TODO: Réactiver après migration DB
        /*
        let message = sqlx::query_as!(
            Message,
            r#"
            SELECT 
                id, conversation_id, sender_id, content, 
                message_type as "message_type: MessageType",
                parent_message_id, is_pinned, is_deleted,
                created_at, updated_at
            FROM messages 
            WHERE id = $1 AND is_deleted = false
            "#,
            message_id
        )
        .fetch_optional(&*self.db)
        .await
        .map_err(|e| ChatError::database_error("get_message_by_id", e))?;

        Ok(message)
        */
        
        // Placeholder temporaire
        tracing::warn!("get_message_by_id: Fonction temporairement désactivée (migration DB requise)");
        Ok(None)
    }

    pub async fn create_message(&self, conversation_id: Uuid, sender_id: Uuid, content: String) -> Result<Message> {
        // TODO: Réactiver après migration DB
        /*
        let message = sqlx::query_as!(
            Message,
            r#"
            INSERT INTO messages (conversation_id, sender_id, content, message_type)
            VALUES ($1, $2, $3, 'text')
            RETURNING 
                id, conversation_id, sender_id, content,
                message_type as "message_type: MessageType",
                parent_message_id, is_pinned, is_deleted,
                created_at, updated_at
            "#,
            conversation_id,
            sender_id,
            content
        )
        .fetch_one(&*self.db)
        .await
        .map_err(|e| ChatError::database_error("create_message", e))?;

        Ok(message)
        */
        
        // Placeholder temporaire
        tracing::warn!("create_message: Fonction temporairement désactivée (migration DB requise)");
        Err(ChatError::feature_not_available("create_message", "migration DB en cours"))
    }
}

/// Service de gestion des conversations
pub struct ConversationService {
    db: Arc<PgPool>,
}

impl ConversationService {
    pub fn new(db: Arc<PgPool>) -> Self {
        Self { db }
    }

    pub async fn get_conversation_by_id(&self, conversation_id: Uuid) -> Result<Option<Conversation>> {
        // TODO: Réactiver après migration DB
        /*
        let conversation = sqlx::query_as!(
            Conversation,
            r#"
            SELECT 
                id, name, description,
                conversation_type as "conversation_type: ConversationType",
                is_private, created_by, created_at, updated_at
            FROM conversations 
            WHERE id = $1
            "#,
            conversation_id
        )
        .fetch_optional(&*self.db)
        .await
        .map_err(|e| ChatError::database_error("get_conversation_by_id", e))?;

        Ok(conversation)
        */
        
        // Placeholder temporaire
        tracing::warn!("get_conversation_by_id: Fonction temporairement désactivée (migration DB requise)");
        Ok(None)
    }
}

/// Container de tous les services
pub struct Services {
    pub users: UserService,
    pub messages: MessageService,
    pub conversations: ConversationService,
}

impl Services {
    pub fn new(db: Arc<PgPool>) -> Self {
        Self {
            users: UserService::new(db.clone()),
            messages: MessageService::new(db.clone()),
            conversations: ConversationService::new(db),
        }
    }
} 