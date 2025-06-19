//file: backend/modules/chat_server/src/hub/dm.rs

use sqlx::{query, query_as, FromRow, Row};
use serde::Serialize;
use crate::hub::common::ChatHub;
use crate::validation::{validate_message_content, validate_user_id, validate_limit};
use crate::error::{ChatError, Result};
use serde_json::json;
use chrono::NaiveDateTime;

#[derive(Debug, FromRow, Serialize)]
pub struct DmMessage {
    pub id: i32,
    pub from_user: Option<i32>,
    pub username: String,
    pub content: String,
    pub timestamp: Option<NaiveDateTime>,
}

pub async fn send_dm(hub: &ChatHub, from_user: i32, to_user: i32, username: &str, content: &str) -> Result<()> {
    tracing::debug!(from_user = %from_user, to_user = %to_user, content_length = %content.len(), "🔧 Début send_dm");
    
    // Validation des entrées
    validate_user_id(from_user)?;
    validate_user_id(to_user)?;
    validate_message_content(content, hub.config.limits.max_message_length)?;
    
    if from_user == to_user {
        tracing::warn!(user_id = %from_user, "🚫 Tentative d'envoi de DM à soi-même");
        return Err(ChatError::configuration_error("Impossible d'envoyer un message à soi-même"));
    }
    
    // Vérification du rate limiting
    if !hub.check_rate_limit(from_user).await {
        tracing::warn!(from_user = %from_user, to_user = %to_user, "🚫 Rate limit dépassé");
        return Err(ChatError::rate_limit_exceeded_simple("rate_limit"));
    }
    
    // Insertion en base de données
    tracing::debug!(from_user = %from_user, to_user = %to_user, "💾 Insertion du message direct en base de données");
    let row = query("INSERT INTO messages (from_user, to_user, content) VALUES ($1, $2, $3) RETURNING id, CURRENT_TIMESTAMP as timestamp")
        .bind(from_user)
        .bind(to_user)
        .bind(content)
        .fetch_one(&hub.db)
        .await
        .map_err(|e| {
            tracing::error!(from_user = %from_user, to_user = %to_user, error = %e, "❌ Erreur insertion message direct en base");
            ChatError::from_sqlx_error("database_operation", e)
        })?;

    let message_id: i32 = row.get("id");
    let timestamp: chrono::DateTime<chrono::Utc> = row.get("timestamp");

    tracing::debug!(from_user = %from_user, to_user = %to_user, message_id = %message_id, "✅ Message direct inséré en base avec succès");

    // Incrémentation des statistiques
    hub.increment_message_count().await;

    let clients = hub.clients.read().await;
    tracing::debug!(from_user = %from_user, to_user = %to_user, total_connected_clients = %clients.len(), "🔐 Lock de lecture sur clients obtenu");
    
    if let Some(client) = clients.get(&to_user) {
        tracing::debug!(from_user = %from_user, to_user = %to_user, "✅ Client destinataire trouvé");
        
        let payload = json!({
            "type": "dm",
            "data": {
                "id": message_id,
                "fromUser": from_user,
                "username": username,
                "content": content,
                "timestamp": timestamp
            }
        });
        
        if client.send_text(&payload.to_string()) {
            tracing::info!(from_user = %from_user, to_user = %to_user, message_id = %message_id, "📨 DM envoyé et enregistré avec succès");
        } else {
            tracing::error!(from_user = %from_user, to_user = %to_user, message_id = %message_id, "❌ Échec envoi du message direct au client");
        }
    } else {
        tracing::warn!(from_user = %from_user, to_user = %to_user, message_id = %message_id, "⚠️ Client destinataire non connecté, message sauvé en base uniquement");
    }

    Ok(())
}

pub async fn fetch_dm_history(hub: &ChatHub, user_id: i32, with: i32, limit: i64) -> Result<Vec<DmMessage>> {
    tracing::debug!(user_id = %user_id, with_user = %with, limit = %limit, "🔧 Début fetch_dm_history");
    
    // Validation des paramètres
    validate_user_id(user_id)?;
    validate_user_id(with)?;
    let validated_limit = validate_limit(limit)?;

    if user_id == with {
        tracing::warn!(user_id = %user_id, "🚫 Tentative de récupération d'historique DM avec soi-même");
        return Err(ChatError::configuration_error("Impossible de récupérer l'historique avec soi-même"));
    }
    
    let messages = query_as::<_, DmMessage>("
        SELECT m.id, u.username, m.from_user, m.content, m.timestamp
        FROM messages m
        JOIN users u ON u.id = m.from_user
        WHERE ((m.from_user = $1 AND m.to_user = $2)
            OR (m.from_user = $2 AND m.to_user = $1))
        ORDER BY m.timestamp ASC
        LIMIT $3
    ")
    .bind(user_id)
    .bind(with)
    .bind(validated_limit)
    .fetch_all(&hub.db)
    .await
    .map_err(|e| {
        tracing::error!(user_id = %user_id, with_user = %with, limit = %validated_limit, error = %e, "❌ Erreur lors de la récupération de l'historique DM");
        ChatError::from_sqlx_error("database_operation", e)
    })?;

    tracing::debug!(user_id = %user_id, with_user = %with, message_count = %messages.len(), limit = %validated_limit, "✅ Historique DM récupéré avec succès");
    Ok(messages)
}

pub async fn user_exists(hub: &ChatHub, user_id: i32) -> Result<bool> {
    tracing::debug!(user_id = %user_id, "🔧 Vérification existence utilisateur");
    
    // Validation de l'ID utilisateur
    validate_user_id(user_id)?;
    
    let row = sqlx::query("SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)")
        .bind(user_id)
        .fetch_one(&hub.db)
        .await
        .map_err(|e| {
            tracing::error!(user_id = %user_id, error = %e, "❌ Erreur lors de la vérification de l'existence de l'utilisateur");
            ChatError::from_sqlx_error("database_operation", e)
        })?;

    let exists: bool = row.get(0);

    tracing::debug!(user_id = %user_id, exists = %exists, "✅ Vérification existence utilisateur terminée");
    Ok(exists)
}
