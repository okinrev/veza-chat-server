//file: backend/modules/chat_server/src/hub/room.rs

use sqlx::{query, query_as, FromRow};
use serde::Serialize;
use crate::hub::common::ChatHub;
use serde_json::json;
use chrono::NaiveDateTime;

#[derive(Debug, FromRow, Serialize)]
pub struct RoomMessage {
    pub id: i32,
    pub username: String,
    pub content: String,
    pub timestamp: Option<NaiveDateTime>,
    pub room: Option<String>,
}

pub async fn join_room(hub: &ChatHub, room: &str, user_id: i32) {
    tracing::debug!(user_id = %user_id, room = %room, "🔧 Début de join_room");
    
    let mut rooms = hub.rooms.write().await;
    tracing::debug!(user_id = %user_id, room = %room, "🔐 Lock d'écriture sur rooms obtenu");
    
    let entry = rooms.entry(room.to_string()).or_default();
    let room_size_before = entry.len();
    
    if !entry.contains(&user_id) {
        entry.push(user_id);
        tracing::debug!(user_id = %user_id, room = %room, room_size_before = %room_size_before, room_size_after = %entry.len(), "✅ Ajout à la room en mémoire");
    } else {
        tracing::debug!(user_id = %user_id, room = %room, room_size = %entry.len(), "⏩ Déjà membre de la room");
    }

    tracing::info!(room = %room, user_id = %user_id, total_members = %entry.len(), "👥 Rejoint la room");
}

pub async fn broadcast_to_room(
    hub: &ChatHub,
    user_id: i32,
    username: &str,
    room: &str,
    msg: &str
) {
    tracing::debug!(user_id = %user_id, room = %room, content_length = %msg.len(), "🔧 Début broadcast_to_room");
    
    // Insertion en base de données
    tracing::debug!(user_id = %user_id, room = %room, "💾 Insertion du message en base de données");
    let rec = match query!(
        "INSERT INTO messages (from_user, room, content) VALUES ($1, $2, $3) RETURNING id, CURRENT_TIMESTAMP as timestamp",
        user_id,
        room,
        msg
    )
    .fetch_one(&hub.db)
    .await {
        Ok(rec) => {
            tracing::debug!(user_id = %user_id, room = %room, message_id = %rec.id, "✅ Message inséré en base avec succès");
            rec
        }
        Err(e) => {
            tracing::error!(user_id = %user_id, room = %room, error = %e, "❌ Erreur insertion message en base");
            return;
        }
    };

    let clients = hub.clients.read().await;
    let rooms = hub.rooms.read().await;
    
    tracing::debug!(user_id = %user_id, room = %room, total_connected_clients = %clients.len(), "🔐 Locks de lecture obtenus");

    let payload = json!({
        "type": "message",
        "data": {
            "id": rec.id,
            "fromUser": user_id,
            "username": username,
            "content": msg,
            "timestamp": rec.timestamp,
            "room": room
        }
    });

    if let Some(user_ids) = rooms.get(room) {
        tracing::debug!(user_id = %user_id, room = %room, room_members = %user_ids.len(), "📋 Membres du salon trouvés");
        
        let mut successful_sends = 0;
        let mut failed_sends = 0;
        
        for id in user_ids {
            if let Some(client) = clients.get(id) {
                tracing::debug!(user_id = %user_id, room = %room, target_user = %id, "📤 Envoi du message à un membre");
                
                if client.send_text(&payload.to_string()) {
                    successful_sends += 1;
                    tracing::debug!(user_id = %user_id, room = %room, target_user = %id, "✅ Message envoyé avec succès");
                } else {
                    failed_sends += 1;
                    tracing::warn!(user_id = %user_id, room = %room, target_user = %id, "❌ Échec envoi message");
                }
            } else {
                failed_sends += 1;
                tracing::warn!(user_id = %user_id, room = %room, target_user = %id, "❌ Client non trouvé dans les connexions actives");
            }
        }
        
        tracing::info!(user_id = %user_id, room = %room, message_id = %rec.id, successful_sends = %successful_sends, failed_sends = %failed_sends, "📨 Message room enregistré et diffusé");
    } else {
        tracing::warn!(user_id = %user_id, room = %room, "❌ Salon non trouvé dans la liste des salons actifs");
    }
}


pub async fn fetch_room_history(hub: &ChatHub, room: &str, limit: i64) -> Vec<RoomMessage> {
    tracing::debug!(room = %room, limit = %limit, "🔧 Début fetch_room_history");
    
    match query_as!(
        RoomMessage,
        r#"
        SELECT m.id, u.username, m.content, m.timestamp, m.room
        FROM messages m
        JOIN users u ON u.id = m.from_user
        WHERE m.room = $1
        ORDER BY m.timestamp ASC
        LIMIT $2
        "#,
        room,
        limit
    )
    .fetch_all(&hub.db)
    .await {
        Ok(messages) => {
            tracing::debug!(room = %room, message_count = %messages.len(), limit = %limit, "✅ Historique salon récupéré avec succès");
            messages
        }
        Err(e) => {
            tracing::error!(room = %room, limit = %limit, error = %e, "❌ Erreur lors de la récupération de l'historique du salon");
            Vec::new()
        }
    }
}

pub async fn room_exists(hub: &ChatHub, room: &str) -> bool {
    tracing::debug!(room = %room, "🔧 Vérification existence salon");
    
    match sqlx::query_scalar!(
        "SELECT EXISTS(SELECT 1 FROM rooms WHERE name = $1)",
        room
    )
    .fetch_one(&hub.db)
    .await {
        Ok(Some(exists)) => {
            tracing::debug!(room = %room, exists = %exists, "✅ Vérification existence salon terminée");
            exists
        }
        Ok(None) => {
            tracing::warn!(room = %room, "⚠️ Résultat NULL pour l'existence du salon");
            false
        }
        Err(e) => {
            tracing::error!(room = %room, error = %e, "❌ Erreur lors de la vérification de l'existence du salon");
            false
        }
    }
}
