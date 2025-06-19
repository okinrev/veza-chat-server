//! Module WebSocket pour la communication temps réel

use crate::{error::Result, models::User};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tokio_tungstenite::{
    tungstenite::{Message as WsMessage, Result as WsResult},
    WebSocketStream,
};
use uuid::Uuid;

/// Message WebSocket entrant
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum IncomingMessage {
    /// Envoi d'un message de chat
    SendMessage {
        conversation_id: Uuid,
        content: String,
        parent_message_id: Option<Uuid>,
    },
    /// Rejoindre une conversation
    JoinConversation { conversation_id: Uuid },
    /// Quitter une conversation
    LeaveConversation { conversation_id: Uuid },
    /// Marquer des messages comme lus
    MarkAsRead { conversation_id: Uuid, message_id: Uuid },
    /// Ping de connexion
    Ping,
}

/// Message WebSocket sortant
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum OutgoingMessage {
    /// Nouveau message reçu
    NewMessage {
        conversation_id: Uuid,
        message_id: Uuid,
        sender_id: Uuid,
        content: String,
        created_at: chrono::DateTime<chrono::Utc>,
    },
    /// Confirmation d'action
    ActionConfirmed { action: String, success: bool },
    /// Erreur
    Error { message: String },
    /// Pong de connexion
    Pong,
}

/// Client WebSocket connecté
pub struct WebSocketClient {
    pub id: Uuid,
    pub user: User,
    pub stream: Arc<RwLock<WebSocketStream<tokio::net::TcpStream>>>,
    pub conversations: Arc<RwLock<Vec<Uuid>>>,
}

impl WebSocketClient {
    pub fn new(
        user: User,
        stream: WebSocketStream<tokio::net::TcpStream>,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            user,
            stream: Arc::new(RwLock::new(stream)),
            conversations: Arc::new(RwLock::new(Vec::new())),
        }
    }

    /// Envoie un message au client
    pub async fn send_message(&self, message: OutgoingMessage) -> Result<()> {
        let json = serde_json::to_string(&message)
            .map_err(|e| crate::error::ChatError::serialization_error("OutgoingMessage", "", e))?;
        
        let mut stream = self.stream.write().await;
        stream
            .send(WsMessage::Text(json))
            .await
            .map_err(|e| crate::error::ChatError::websocket_error("send_message", e))?;

        Ok(())
    }

    /// Lit le prochain message du client
    pub async fn receive_message(&self) -> Result<Option<IncomingMessage>> {
        let mut stream = self.stream.write().await;
        
        if let Some(msg) = stream.next().await {
            match msg.map_err(|e| crate::error::ChatError::websocket_error("receive_message", e))? {
                WsMessage::Text(text) => {
                    let incoming: IncomingMessage = serde_json::from_str(&text)
                        .map_err(|e| crate::error::ChatError::serialization_error("IncomingMessage", &text, e))?;
                    Ok(Some(incoming))
                }
                WsMessage::Close(_) => Ok(None),
                _ => Ok(None), // Ignore autres types de messages
            }
        } else {
            Ok(None)
        }
    }
}

/// Gestionnaire de connexions WebSocket
pub struct WebSocketManager {
    clients: Arc<RwLock<Vec<WebSocketClient>>>,
}

impl WebSocketManager {
    pub fn new() -> Self {
        Self {
            clients: Arc::new(RwLock::new(Vec::new())),
        }
    }

    /// Ajoute un nouveau client
    pub async fn add_client(&self, client: WebSocketClient) {
        let mut clients = self.clients.write().await;
        clients.push(client);
    }

    /// Supprime un client
    pub async fn remove_client(&self, client_id: Uuid) {
        let mut clients = self.clients.write().await;
        clients.retain(|c| c.id != client_id);
    }

    /// Diffuse un message à tous les clients d'une conversation
    pub async fn broadcast_to_conversation(&self, conversation_id: Uuid, message: OutgoingMessage) -> Result<()> {
        let clients = self.clients.read().await;
        
        for client in clients.iter() {
            let conversations = client.conversations.read().await;
            if conversations.contains(&conversation_id) {
                let _ = client.send_message(message.clone()).await; // Ignore les erreurs individuelles
            }
        }
        
        Ok(())
    }
}

impl Default for WebSocketManager {
    fn default() -> Self {
        Self::new()
    }
} 