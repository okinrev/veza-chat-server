//file: backend/modules/chat_server/src/hub.rs

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
//use tokio_tungstenite::tungstenite::protocol::Message;
use sqlx::{PgPool, FromRow, query_as}; // <- ajoute query_as ici directement
use serde_json::json;

use crate::client::Client;

pub struct ChatHub {
    pub db: PgPool,
    pub clients: RwLock<HashMap<i32, Client>>, // user_id → Client
    pub rooms: RwLock<HashMap<String, Vec<i32>>>, // room name → list of user_ids
}

#[derive(Debug, FromRow)]
pub struct DmMessage {
    pub username: String,
    pub content: String,
    pub timestamp: NaiveDateTime,
}

#[derive(Debug, FromRow)]
pub struct RoomMessage {
    pub username: String,
    pub content: String,
    pub timestamp: NaiveDateTime,
}

impl ChatHub {
    pub fn new(db: PgPool) -> Arc<Self> {
        Arc::new(Self {
            db,
            clients: Default::default(),
            rooms: Default::default(),
        })
    }

    /// Enregistre un nouveau client
    pub async fn register(&self, user_id: i32, client: Client) {
        tracing::info!("👤 Enregistrement du client {}", user_id);
        self.clients.write().await.insert(user_id, client);
    }

    /// Supprime un client déconnecté
    pub async fn unregister(&self, user_id: i32) {
        tracing::info!("🚪 Déconnexion du client {}", user_id);
        self.clients.write().await.remove(&user_id);
    }

    /// Rejoint un salon (enregistre l’utilisateur dans la room)
    pub async fn join_room(&self, room: &str, user_id: i32) {
        let mut rooms = self.rooms.write().await;
        rooms.entry(room.to_string()).or_default().push(user_id);
        tracing::info!("👥 Client {} a rejoint la room '{}'", user_id, room);
    }

    /// Broadcast un message à tous les membres d’un salon
    pub async fn broadcast_to_room(&self, user_id: i32, username: &str, room: &str, msg: &str) {
        let clients = self.clients.read().await;
        let rooms = self.rooms.read().await;

        if let Some(user_ids) = rooms.get(room) {
            for user_id in user_ids {
                if let Some(client) = clients.get(user_id) {
                    let payload = json!({
                        "username": username,
                        "fromUser": user_id,
                        "content": msg
                    });
                    tracing::debug!("📤 Envoi WS à {}: {:?}", user_id, payload);
                    client.send_text(&payload.to_string());                    
                }
            }
        }
        // Enregistre en base
        sqlx::query("INSERT INTO messages (from_user, room, content) VALUES ($1, $2, $3)")
            .bind(user_id)
            .bind(room)
            .bind(msg)
            .execute(&self.db)
            .await
            .unwrap();
    }

    /// Envoie un message direct (DM) à un utilisateur
    pub async fn send_dm(&self, from_user: i32, to_user: i32, msg: &str) {
        let clients = self.clients.read().await;
        if let Some(client) = clients.get(&to_user) {
            let payload = json!({
                "username": username,
                "fromUser": from_user,
                "content": content
            });
            tracing::debug!("📤 Envoi WS à {}: {:?}", user_id, payload);
            client.send_text(&payload.to_string());            
        }
        // Enregistrement en base
        sqlx::query("INSERT INTO messages (from_user, to_user, content) VALUES ($1, $2, $3)")
            .bind(from_user)
            .bind(to_user)
            .bind(msg)
            .execute(&self.db)
            .await
            .unwrap();
    }

    pub async fn fetch_dm_history(
        &self,
        user_id: i32,
        with: i32,
        limit: i64,
    ) -> Vec<DmMessage> {
        let rows = query_as!(
            DmMessage,
            r#"
            SELECT u.username, m.content
            FROM messages m
            JOIN users u ON u.id = m.from_user
            WHERE ((m.from_user = $1 AND m.to_user = $2)
                OR (m.from_user = $2 AND m.to_user = $1))
            ORDER BY m.timestamp DESC
            LIMIT $3
            "#,
            user_id,
            with,
            limit
        )
        .fetch_all(&self.db)
        .await
        .unwrap_or_default();

        rows
    }

    
    pub async fn fetch_room_history(&self, room: &str, limit: i64) -> Vec<RoomMessage> {
        let rows = query_as!(
            RoomMessage,
            r#"
            SELECT u.username, m.content
            FROM messages m
            JOIN users u ON u.id = m.from_user
            WHERE m.room = $1
            ORDER BY m.timestamp DESC
            LIMIT $2
            "#,
            room,
            limit
        )
        .fetch_all(&self.db)
        .await
        .unwrap_or_default();
    
        rows
    }    

    /// Vérifie si une room existe (en base)
    pub async fn room_exists(&self, room: &str) -> bool {
        let result = sqlx::query_scalar!(
            "SELECT EXISTS(SELECT 1 FROM rooms WHERE name = $1)",
            room
        )
        .fetch_one(&self.db)
        .await
        .unwrap_or(Some(false)) // Option<bool>
        .unwrap_or(false);      // bool

        result
    }

    /// Vérifie si un utilisateur existe
    pub async fn user_exists(&self, user_id: i32) -> bool {
        let result = sqlx::query_scalar!(
            "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)",
            user_id
        )
        .fetch_one(&self.db)
        .await
        .unwrap_or(Some(false)) // Option<bool>
        .unwrap_or(false);      // bool

        result
    }
    
}
