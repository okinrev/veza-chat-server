use std::collections::HashMap;
use serde::{Serialize, Deserialize};
use crate::error::{ChatError, Result};
use crate::hub::common::ChatHub;
use sqlx::Row;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum ReactionType {
    // Émojis de base
    Like,
    Love,
    Laugh,
    Angry,
    Sad,
    Wow,
    
    // Émojis étendus
    ThumbsUp,
    ThumbsDown,
    Fire,
    Party,
    Check,
    Cross,
    
    // Réactions personnalisées
    Custom(String),
}

#[derive(Debug, Clone, Serialize)]
pub struct MessageReaction {
    pub message_id: i32,
    pub reaction_type: ReactionType,
    pub user_id: i32,
    pub username: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ReactionSummary {
    pub message_id: i32,
    pub reactions: HashMap<ReactionType, Vec<ReactionUser>>,
    pub total_count: u32,
}

#[derive(Debug, Clone, Serialize)]
pub struct ReactionUser {
    pub user_id: i32,
    pub username: String,
}

/// Gestionnaire des réactions aux messages
pub struct ReactionManager {
    hub: std::sync::Arc<ChatHub>,
}

impl ReactionManager {
    pub fn new(hub: std::sync::Arc<ChatHub>) -> Self {
        Self { hub }
    }

    /// Ajoute une réaction à un message
    pub async fn add_reaction(
        &self,
        message_id: i32,
        user_id: i32,
        username: &str,
        reaction_type: ReactionType,
    ) -> Result<()> {
        // Vérifier que le message existe
        if !self.message_exists(message_id).await? {
            return Err(ChatError::configuration_error("Message introuvable"));
        }

        // Vérifier si l'utilisateur a déjà réagi à ce message avec cette réaction
        if self.user_has_reaction(message_id, user_id, &reaction_type).await? {
            return Err(ChatError::configuration_error("Vous avez déjà ajouté cette réaction"));
        }

        // Ajouter la réaction en base
        let reaction_str = serde_json::to_string(&reaction_type)
            .map_err(|e| ChatError::from_json_error(e))?;

        sqlx::query(
            "INSERT INTO message_reactions (message_id, user_id, reaction_type) VALUES ($1, $2, $3)"
        )
        .bind(message_id)
        .bind(user_id)
        .bind(reaction_str)
        .execute(&self.hub.db)
        .await
        .map_err(|e| ChatError::from_sqlx_error("database_operation", e))?;

        tracing::info!(
            message_id = %message_id,
            user_id = %user_id,
            username = %username,
            reaction = ?reaction_type,
            "👍 Réaction ajoutée"
        );

        // Diffuser la mise à jour des réactions
        self.broadcast_reaction_update(message_id).await?;

        Ok(())
    }

    /// Supprime une réaction d'un message
    pub async fn remove_reaction(
        &self,
        message_id: i32,
        user_id: i32,
        reaction_type: ReactionType,
    ) -> Result<()> {
        let reaction_str = serde_json::to_string(&reaction_type)
            .map_err(|e| ChatError::from_json_error(e))?;

        let result = sqlx::query(
            "DELETE FROM message_reactions WHERE message_id = $1 AND user_id = $2 AND reaction_type = $3"
        )
        .bind(message_id)
        .bind(user_id)
        .bind(reaction_str)
        .execute(&self.hub.db)
        .await
        .map_err(|e| ChatError::from_sqlx_error("database_operation", e))?;

        if result.rows_affected() == 0 {
            return Err(ChatError::configuration_error("Réaction non trouvée"));
        }

        tracing::info!(
            message_id = %message_id,
            user_id = %user_id,
            reaction = ?reaction_type,
            "👎 Réaction supprimée"
        );

        // Diffuser la mise à jour des réactions
        self.broadcast_reaction_update(message_id).await?;

        Ok(())
    }

    /// Récupère toutes les réactions pour un message
    pub async fn get_message_reactions(&self, message_id: i32) -> Result<ReactionSummary> {
        let rows = sqlx::query(
            r#"
            SELECT mr.reaction_type, mr.user_id, u.username
            FROM message_reactions mr
            JOIN users u ON u.id = mr.user_id
            WHERE mr.message_id = $1
            ORDER BY mr.created_at ASC
            "#
        )
        .bind(message_id)
        .fetch_all(&self.hub.db)
        .await
        .map_err(|e| ChatError::from_sqlx_error("database_operation", e))?;

        let mut reactions: HashMap<ReactionType, Vec<ReactionUser>> = HashMap::new();
        let mut total_count = 0;

        for row in rows {
            let reaction_str: String = row.get("reaction_type");
            let reaction_type: ReactionType = serde_json::from_str(&reaction_str)
                .map_err(|e| ChatError::from_json_error(e))?;
            let user_id: i32 = row.get("user_id");
            let username: String = row.get("username");

            reactions.entry(reaction_type)
                .or_insert_with(Vec::new)
                .push(ReactionUser { user_id, username });
            
            total_count += 1;
        }

        Ok(ReactionSummary {
            message_id,
            reactions,
            total_count,
        })
    }

    /// Vérifie si un message existe
    async fn message_exists(&self, message_id: i32) -> Result<bool> {
        let row = sqlx::query("SELECT EXISTS(SELECT 1 FROM messages WHERE id = $1)")
            .bind(message_id)
            .fetch_one(&self.hub.db)
            .await
            .map_err(|e| ChatError::from_sqlx_error("database_operation", e))?;

        Ok(row.get(0))
    }

    /// Vérifie si un utilisateur a déjà réagi avec un type de réaction spécifique
    async fn user_has_reaction(&self, message_id: i32, user_id: i32, reaction_type: &ReactionType) -> Result<bool> {
        let reaction_str = serde_json::to_string(reaction_type)
            .map_err(|e| ChatError::from_json_error(e))?;

        let row = sqlx::query(
            "SELECT EXISTS(SELECT 1 FROM message_reactions WHERE message_id = $1 AND user_id = $2 AND reaction_type = $3)"
        )
        .bind(message_id)
        .bind(user_id)
        .bind(reaction_str)
        .fetch_one(&self.hub.db)
        .await
        .map_err(|e| ChatError::from_sqlx_error("database_operation", e))?;

        Ok(row.get(0))
    }

    /// Diffuse la mise à jour des réactions à tous les clients concernés
    async fn broadcast_reaction_update(&self, message_id: i32) -> Result<()> {
        let reactions = self.get_message_reactions(message_id).await?;
        
        let update_msg = serde_json::json!({
            "type": "reaction_update",
            "data": reactions
        });

        // Diffuser à tous les clients connectés
        // En production, on pourrait optimiser en ne diffusant qu'aux utilisateurs du salon concerné
        let clients = self.hub.clients.read().await;
        for client in clients.values() {
            if let Err(e) = client.sender.send(tokio_tungstenite::tungstenite::Message::Text(update_msg.to_string())) {
                tracing::warn!(user_id = %client.user_id, error = %e, "❌ Erreur diffusion mise à jour réactions");
            }
        }

        Ok(())
    }
}

impl ReactionType {
    /// Convertit un string emoji en ReactionType
    pub fn from_emoji(emoji: &str) -> Option<Self> {
        match emoji {
            "👍" | "like" => Some(ReactionType::Like),
            "❤️" | "love" => Some(ReactionType::Love),
            "😂" | "laugh" => Some(ReactionType::Laugh),
            "😡" | "angry" => Some(ReactionType::Angry),
            "😢" | "sad" => Some(ReactionType::Sad),
            "😮" | "wow" => Some(ReactionType::Wow),
            "👍🏼" | "thumbs_up" => Some(ReactionType::ThumbsUp),
            "👎" | "thumbs_down" => Some(ReactionType::ThumbsDown),
            "🔥" | "fire" => Some(ReactionType::Fire),
            "🎉" | "party" => Some(ReactionType::Party),
            "✅" | "check" => Some(ReactionType::Check),
            "❌" | "cross" => Some(ReactionType::Cross),
            _ => {
                // Réaction personnalisée
                if emoji.len() <= 10 && !emoji.is_empty() {
                    Some(ReactionType::Custom(emoji.to_string()))
                } else {
                    None
                }
            }
        }
    }

    /// Convertit le ReactionType en emoji string
    pub fn to_emoji(&self) -> String {
        match self {
            ReactionType::Like => "👍".to_string(),
            ReactionType::Love => "❤️".to_string(),
            ReactionType::Laugh => "😂".to_string(),
            ReactionType::Angry => "😡".to_string(),
            ReactionType::Sad => "😢".to_string(),
            ReactionType::Wow => "😮".to_string(),
            ReactionType::ThumbsUp => "👍🏼".to_string(),
            ReactionType::ThumbsDown => "👎".to_string(),
            ReactionType::Fire => "🔥".to_string(),
            ReactionType::Party => "🎉".to_string(),
            ReactionType::Check => "✅".to_string(),
            ReactionType::Cross => "❌".to_string(),
            ReactionType::Custom(emoji) => emoji.clone(),
        }
    }
} 