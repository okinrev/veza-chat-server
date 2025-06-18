//file: backend/modules/chat_server/src/hub/dm.rs

use sqlx::{query, query_as, FromRow};
use serde::Serialize;
use crate::hub::common::ChatHub;
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

pub async fn send_dm(hub: &ChatHub, from_user: i32, to_user: i32, username: &str, content: &str) {
    tracing::debug!(from_user = %from_user, to_user = %to_user, content_length = %content.len(), "🔧 Début send_dm");
    
    // Insertion en base de données
    tracing::debug!(from_user = %from_user, to_user = %to_user, "💾 Insertion du message direct en base de données");
    let rec = match query!(
        "INSERT INTO messages (from_user, to_user, content) VALUES ($1, $2, $3) RETURNING id, CURRENT_TIMESTAMP as timestamp",
        from_user,
        to_user,
        content
    )
    .fetch_one(&hub.db)
    .await {
        Ok(rec) => {
            tracing::debug!(from_user = %from_user, to_user = %to_user, message_id = %rec.id, "✅ Message direct inséré en base avec succès");
            rec
        }
        Err(e) => {
            tracing::error!(from_user = %from_user, to_user = %to_user, error = %e, "❌ Erreur insertion message direct en base");
            return;
        }
    };

    let clients = hub.clients.read().await;
    tracing::debug!(from_user = %from_user, to_user = %to_user, total_connected_clients = %clients.len(), "🔐 Lock de lecture sur clients obtenu");
    
    if let Some(client) = clients.get(&to_user) {
        tracing::debug!(from_user = %from_user, to_user = %to_user, "✅ Client destinataire trouvé");
        
        let payload = json!({
            "type": "dm",
            "data": {
                "id": rec.id,
                "fromUser": from_user,
                "username": username,
                "content": content,
                "timestamp": rec.timestamp
            }
        });
        
        if client.send_text(&payload.to_string()) {
            tracing::info!(from_user = %from_user, to_user = %to_user, message_id = %rec.id, "📨 DM envoyé et enregistré avec succès");
        } else {
            tracing::error!(from_user = %from_user, to_user = %to_user, message_id = %rec.id, "❌ Échec envoi du message direct au client");
        }
    } else {
        tracing::warn!(from_user = %from_user, to_user = %to_user, message_id = %rec.id, "⚠️ Client destinataire non connecté, message sauvé en base uniquement");
    }
}

pub async fn fetch_dm_history(hub: &ChatHub, user_id: i32, with: i32, limit: i64) -> Vec<DmMessage> {
    tracing::debug!(user_id = %user_id, with_user = %with, limit = %limit, "🔧 Début fetch_dm_history");
    
    match query_as!(
        DmMessage,
        r#"
        SELECT m.id, u.username, m.from_user, m.content, m.timestamp
        FROM messages m
        JOIN users u ON u.id = m.from_user
        WHERE ((m.from_user = $1 AND m.to_user = $2)
            OR (m.from_user = $2 AND m.to_user = $1))
        ORDER BY m.timestamp ASC
        LIMIT $3
        "#,
        user_id,
        with,
        limit
    )
    .fetch_all(&hub.db)
    .await {
        Ok(messages) => {
            tracing::debug!(user_id = %user_id, with_user = %with, message_count = %messages.len(), limit = %limit, "✅ Historique DM récupéré avec succès");
            messages
        }
        Err(e) => {
            tracing::error!(user_id = %user_id, with_user = %with, limit = %limit, error = %e, "❌ Erreur lors de la récupération de l'historique DM");
            Vec::new()
        }
    }
}

pub async fn user_exists(hub: &ChatHub, user_id: i32) -> bool {
    tracing::debug!(user_id = %user_id, "🔧 Vérification existence utilisateur");
    
    match sqlx::query_scalar!(
        "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)",
        user_id
    )
    .fetch_one(&hub.db)
    .await {
        Ok(Some(exists)) => {
            tracing::debug!(user_id = %user_id, exists = %exists, "✅ Vérification existence utilisateur terminée");
            exists
        }
        Ok(None) => {
            tracing::warn!(user_id = %user_id, "⚠️ Résultat NULL pour l'existence de l'utilisateur");
            false
        }
        Err(e) => {
            tracing::error!(user_id = %user_id, error = %e, "❌ Erreur lors de la vérification de l'existence de l'utilisateur");
            false
        }
    }
}
