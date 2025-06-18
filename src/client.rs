//file: backend/modules/chat_server/src/client.rs

use tokio::sync::mpsc::UnboundedSender;
use tokio_tungstenite::tungstenite::Message;

#[derive(Debug, Clone)]
pub struct Client {
    pub user_id: i32,
    pub username: String,
    pub sender: UnboundedSender<Message>,
}

impl Client {
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
}