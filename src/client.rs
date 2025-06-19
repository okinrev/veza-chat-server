//file: backend/modules/chat_server/src/client.rs

use tokio::sync::mpsc::UnboundedSender;
use tokio_tungstenite::tungstenite::Message;
use std::time::{Duration, Instant};

#[derive(Debug, Clone)]
pub struct Client {
    pub user_id: i32,
    pub username: String,
    pub sender: UnboundedSender<Message>,
    pub last_heartbeat: std::sync::Arc<std::sync::RwLock<Instant>>,
    pub connected_at: Instant,
}

impl Client {
    pub fn new(user_id: i32, username: String, sender: UnboundedSender<Message>) -> Self {
        Self {
            user_id,
            username,
            sender,
            last_heartbeat: std::sync::Arc::new(std::sync::RwLock::new(Instant::now())),
            connected_at: Instant::now(),
        }
    }

    /// Envoie un message texte au client
    pub fn send_text(&self, text: &str) -> bool {
        tracing::debug!(user_id = %self.user_id, username = %self.username, text_length = %text.len(), "🔧 Tentative d'envoi de message texte");
        
        match self.sender.send(Message::Text(text.to_string())) {
            Ok(_) => {
                tracing::debug!(user_id = %self.user_id, username = %self.username, "✅ Message texte envoyé au canal");
                true
            }
            Err(e) => {
                tracing::error!(user_id = %self.user_id, username = %self.username, error = %e, "❌ Erreur envoi message texte au canal");
                false
            }
        }
    }

    /// Envoie un ping pour vérifier la connexion
    pub fn send_ping(&self) -> bool {
        tracing::debug!(user_id = %self.user_id, username = %self.username, "🏓 Envoi ping");
        
        match self.sender.send(Message::Ping(vec![])) {
            Ok(_) => {
                tracing::debug!(user_id = %self.user_id, username = %self.username, "✅ Ping envoyé");
                true
            }
            Err(e) => {
                tracing::error!(user_id = %self.user_id, username = %self.username, error = %e, "❌ Erreur envoi ping");
                false
            }
        }
    }

    /// Met à jour le timestamp du dernier heartbeat
    pub fn update_heartbeat(&self) {
        if let Ok(mut last_heartbeat) = self.last_heartbeat.write() {
            *last_heartbeat = Instant::now();
        }
    }

    /// Vérifie si la connexion est encore active (basé sur le heartbeat)
    pub fn is_alive(&self, timeout: Duration) -> bool {
        if let Ok(last_heartbeat) = self.last_heartbeat.read() {
            last_heartbeat.elapsed() < timeout
        } else {
            false
        }
    }

    /// Retourne la durée de connexion
    pub fn connection_duration(&self) -> Duration {
        self.connected_at.elapsed()
    }
}