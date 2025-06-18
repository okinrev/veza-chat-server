//file: backend/modules/chat_server/src/messages.rs

use serde::Deserialize;

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
pub enum WsInbound {
    #[serde(rename = "join_room")]
    Join {
        room: String,
    },

    #[serde(rename = "room_message")]
    Message {
        room: String,
        content: String,
    },

    #[serde(rename = "direct_message")]
    DirectMessage {
        to_user_id: i32,
        content: String,
    },

    #[serde(rename = "room_history")]
    RoomHistory {
        room: String,
        limit: i64,
    },

    #[serde(rename = "dm_history")]
    DmHistory {
        with: i32,
        limit: i64,
    }
}

impl WsInbound {
    #[allow(dead_code)]
    pub fn log_received(&self) {
        match self {
            WsInbound::Join { room } => {
                tracing::debug!(message_type = "join_room", room = %room, "📥 Message join_room reçu");
            }
            WsInbound::Message { room, content } => {
                tracing::debug!(message_type = "room_message", room = %room, content_length = %content.len(), "📥 Message room_message reçu");
            }
            WsInbound::DirectMessage { to_user_id, content } => {
                tracing::debug!(message_type = "direct_message", to_user_id = %to_user_id, content_length = %content.len(), "📥 Message direct_message reçu");
            }
            WsInbound::RoomHistory { room, limit } => {
                tracing::debug!(message_type = "room_history", room = %room, limit = %limit, "📥 Message room_history reçu");
            }
            WsInbound::DmHistory { with, limit } => {
                tracing::debug!(message_type = "dm_history", with_user = %with, limit = %limit, "📥 Message dm_history reçu");
            }
        }
    }
}
