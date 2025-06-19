//! Gestionnaire WebSocket enrichi pour les salons
//! 
//! Nouvelles fonctionnalités :
//! - Gestion complète des salons avec rôles
//! - Réactions en temps réel
//! - Messages épinglés
//! - Threads et réponses
//! - Notifications d'audit
//! - Événements de modération

use crate::hub::{ChatHub, room_enhanced, reactions, audit};
use crate::error::{ChatError, Result};
use serde_json::{json, Value};
use tokio_tungstenite::tungstenite::Message;
use tracing::{info, warn, error};

// ================================================================
// TYPES DE MESSAGES WEBSOCKET
// ================================================================

pub enum RoomWebSocketMessage {
    // Messages de base
    JoinRoom { room_id: i64, user_id: i64 },
    LeaveRoom { room_id: i64, user_id: i64 },
    SendMessage { room_id: i64, user_id: i64, username: String, content: String, parent_id: Option<i64> },
    
    // Historique et recherche
    GetHistory { room_id: i64, user_id: i64, limit: i64, before_id: Option<i64> },
    GetPinnedMessages { room_id: i64, user_id: i64 },
    
    // Réactions
    AddReaction { message_id: i64, user_id: i64, emoji: String },
    RemoveReaction { message_id: i64, user_id: i64, emoji: String },
    GetReactions { message_id: i64, user_id: i64 },
    
    // Modération
    PinMessage { room_id: i64, message_id: i64, user_id: i64 },
    UnpinMessage { room_id: i64, message_id: i64, user_id: i64 },
    
    // Administration
    GetRoomStats { room_id: i64, user_id: i64 },
    GetMembers { room_id: i64, user_id: i64 },
    GetAuditLogs { room_id: i64, user_id: i64, limit: i64 },
}

// ================================================================
// GESTIONNAIRE PRINCIPAL
// ================================================================

pub async fn handle_room_websocket_message(
    hub: &ChatHub,
    message: RoomWebSocketMessage
) -> Result<Option<String>> {
    match message {
        // Messages de base
        RoomWebSocketMessage::JoinRoom { room_id, user_id } => {
            handle_join_room(hub, room_id, user_id).await
        }
        
        RoomWebSocketMessage::LeaveRoom { room_id, user_id } => {
            handle_leave_room(hub, room_id, user_id).await
        }
        
        RoomWebSocketMessage::SendMessage { room_id, user_id, username, content, parent_id } => {
            handle_send_message(hub, room_id, user_id, &username, &content, parent_id).await
        }
        
        // Historique
        RoomWebSocketMessage::GetHistory { room_id, user_id, limit, before_id } => {
            handle_get_history(hub, room_id, user_id, limit, before_id).await
        }
        
        RoomWebSocketMessage::GetPinnedMessages { room_id, user_id } => {
            handle_get_pinned_messages(hub, room_id, user_id).await
        }
        
        // Réactions
        RoomWebSocketMessage::AddReaction { message_id, user_id, emoji } => {
            handle_add_reaction(hub, message_id, user_id, &emoji).await
        }
        
        RoomWebSocketMessage::RemoveReaction { message_id, user_id, emoji } => {
            handle_remove_reaction(hub, message_id, user_id, &emoji).await
        }
        
        RoomWebSocketMessage::GetReactions { message_id, user_id } => {
            handle_get_reactions(hub, message_id, user_id).await
        }
        
        // Modération
        RoomWebSocketMessage::PinMessage { room_id, message_id, user_id } => {
            handle_pin_message(hub, room_id, message_id, user_id, true).await
        }
        
        RoomWebSocketMessage::UnpinMessage { room_id, message_id, user_id } => {
            handle_pin_message(hub, room_id, message_id, user_id, false).await
        }
        
        // Administration
        RoomWebSocketMessage::GetRoomStats { room_id, user_id } => {
            handle_get_room_stats(hub, room_id, user_id).await
        }
        
        RoomWebSocketMessage::GetMembers { room_id, user_id } => {
            handle_get_members(hub, room_id, user_id).await
        }
        
        RoomWebSocketMessage::GetAuditLogs { room_id, user_id, limit } => {
            handle_get_audit_logs(hub, room_id, user_id, limit).await
        }
    }
}

// ================================================================
// GESTIONNAIRES SPÉCIFIQUES
// ================================================================

async fn handle_join_room(hub: &ChatHub, room_id: i64, user_id: i64) -> Result<Option<String>> {
    info!(room_id = %room_id, user_id = %user_id, "🚪 Tentative de rejoindre le salon");
    
    match room_enhanced::join_room(hub, room_id, user_id).await {
        Ok(()) => {
            // Logger l'événement
            audit::log_member_change(hub, room_id, "Salon", user_id, None, "joined", None).await?;
            
            Ok(Some(json!({
                "type": "room_joined",
                "data": {
                    "roomId": room_id,
                    "userId": user_id,
                    "success": true
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(room_id = %room_id, user_id = %user_id, error = %e, "❌ Échec de rejoindre le salon");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "join_room",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_leave_room(hub: &ChatHub, room_id: i64, user_id: i64) -> Result<Option<String>> {
    info!(room_id = %room_id, user_id = %user_id, "🚪 Tentative de quitter le salon");
    
    match room_enhanced::leave_room(hub, room_id, user_id).await {
        Ok(()) => {
            // Logger l'événement
            audit::log_member_change(hub, room_id, "Salon", user_id, None, "left", None).await?;
            
            Ok(Some(json!({
                "type": "room_left",
                "data": {
                    "roomId": room_id,
                    "userId": user_id,
                    "success": true
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(room_id = %room_id, user_id = %user_id, error = %e, "❌ Échec de quitter le salon");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "leave_room",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_send_message(
    hub: &ChatHub,
    room_id: i64,
    user_id: i64,
    username: &str,
    content: &str,
    parent_id: Option<i64>
) -> Result<Option<String>> {
    info!(room_id = %room_id, user_id = %user_id, content_length = %content.len(), "📝 Envoi de message dans le salon");
    
    match room_enhanced::send_room_message(hub, room_id, user_id, username, content, parent_id, None).await {
        Ok(message_id) => {
            info!(room_id = %room_id, message_id = %message_id, "✅ Message envoyé dans le salon");
            Ok(Some(json!({
                "type": "message_sent",
                "data": {
                    "messageId": message_id,
                    "roomId": room_id,
                    "success": true
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(room_id = %room_id, user_id = %user_id, error = %e, "❌ Échec d'envoi de message");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "send_message",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_get_history(
    hub: &ChatHub,
    room_id: i64,
    user_id: i64,
    limit: i64,
    before_id: Option<i64>
) -> Result<Option<String>> {
    info!(room_id = %room_id, user_id = %user_id, limit = %limit, "📚 Récupération de l'historique du salon");
    
    match room_enhanced::fetch_room_history(hub, room_id, user_id, limit, before_id).await {
        Ok(messages) => {
            info!(room_id = %room_id, message_count = %messages.len(), "✅ Historique récupéré");
            Ok(Some(json!({
                "type": "room_history",
                "data": {
                    "roomId": room_id,
                    "messages": messages,
                    "hasMore": messages.len() as i64 == limit
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(room_id = %room_id, user_id = %user_id, error = %e, "❌ Échec de récupération de l'historique");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "get_history",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_get_pinned_messages(hub: &ChatHub, room_id: i64, user_id: i64) -> Result<Option<String>> {
    info!(room_id = %room_id, user_id = %user_id, "📌 Récupération des messages épinglés");
    
    match room_enhanced::fetch_pinned_messages(hub, room_id, user_id).await {
        Ok(messages) => {
            info!(room_id = %room_id, pinned_count = %messages.len(), "✅ Messages épinglés récupérés");
            Ok(Some(json!({
                "type": "pinned_messages",
                "data": {
                    "roomId": room_id,
                    "messages": messages
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(room_id = %room_id, user_id = %user_id, error = %e, "❌ Échec de récupération des messages épinglés");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "get_pinned_messages",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_add_reaction(hub: &ChatHub, message_id: i64, user_id: i64, emoji: &str) -> Result<Option<String>> {
    info!(message_id = %message_id, user_id = %user_id, emoji = %emoji, "😊 Ajout de réaction");
    
    match reactions::add_reaction(hub, message_id, user_id, emoji).await {
        Ok(()) => {
            info!(message_id = %message_id, emoji = %emoji, "✅ Réaction ajoutée");
            Ok(Some(json!({
                "type": "reaction_added",
                "data": {
                    "messageId": message_id,
                    "userId": user_id,
                    "emoji": emoji,
                    "success": true
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(message_id = %message_id, user_id = %user_id, error = %e, "❌ Échec d'ajout de réaction");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "add_reaction",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_remove_reaction(hub: &ChatHub, message_id: i64, user_id: i64, emoji: &str) -> Result<Option<String>> {
    info!(message_id = %message_id, user_id = %user_id, emoji = %emoji, "🗑️ Suppression de réaction");
    
    match reactions::remove_reaction(hub, message_id, user_id, emoji).await {
        Ok(()) => {
            info!(message_id = %message_id, emoji = %emoji, "✅ Réaction supprimée");
            Ok(Some(json!({
                "type": "reaction_removed",
                "data": {
                    "messageId": message_id,
                    "userId": user_id,
                    "emoji": emoji,
                    "success": true
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(message_id = %message_id, user_id = %user_id, error = %e, "❌ Échec de suppression de réaction");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "remove_reaction",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_get_reactions(hub: &ChatHub, message_id: i64, user_id: i64) -> Result<Option<String>> {
    info!(message_id = %message_id, user_id = %user_id, "📊 Récupération des réactions");
    
    match reactions::get_message_reactions(hub, message_id, user_id).await {
        Ok(message_reactions) => {
            info!(message_id = %message_id, total_reactions = %message_reactions.total_reactions, "✅ Réactions récupérées");
            Ok(Some(json!({
                "type": "message_reactions",
                "data": message_reactions
            }).to_string()))
        }
        Err(e) => {
            warn!(message_id = %message_id, user_id = %user_id, error = %e, "❌ Échec de récupération des réactions");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "get_reactions",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_pin_message(hub: &ChatHub, room_id: i64, message_id: i64, user_id: i64, pin: bool) -> Result<Option<String>> {
    let action_text = if pin { "épinglage" } else { "désépinglage" };
    info!(room_id = %room_id, message_id = %message_id, user_id = %user_id, pin = %pin, "📌 {} de message", action_text);
    
    match room_enhanced::pin_message(hub, room_id, message_id, user_id, pin).await {
        Ok(()) => {
            info!(message_id = %message_id, pin = %pin, "✅ Statut d'épinglage mis à jour");
            Ok(Some(json!({
                "type": if pin { "message_pinned" } else { "message_unpinned" },
                "data": {
                    "messageId": message_id,
                    "roomId": room_id,
                    "isPinned": pin,
                    "success": true
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(message_id = %message_id, user_id = %user_id, error = %e, "❌ Échec de {} de message", action_text);
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": if pin { "pin_message" } else { "unpin_message" },
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_get_room_stats(hub: &ChatHub, room_id: i64, user_id: i64) -> Result<Option<String>> {
    info!(room_id = %room_id, user_id = %user_id, "📊 Récupération des statistiques du salon");
    
    match room_enhanced::get_room_stats(hub, room_id).await {
        Ok(stats) => {
            info!(room_id = %room_id, "✅ Statistiques récupérées");
            Ok(Some(json!({
                "type": "room_stats",
                "data": stats
            }).to_string()))
        }
        Err(e) => {
            warn!(room_id = %room_id, user_id = %user_id, error = %e, "❌ Échec de récupération des statistiques");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "get_room_stats",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_get_members(hub: &ChatHub, room_id: i64, user_id: i64) -> Result<Option<String>> {
    info!(room_id = %room_id, user_id = %user_id, "👥 Récupération de la liste des membres");
    
    match room_enhanced::list_room_members(hub, room_id, user_id).await {
        Ok(members) => {
            info!(room_id = %room_id, member_count = %members.len(), "✅ Liste des membres récupérée");
            Ok(Some(json!({
                "type": "room_members",
                "data": {
                    "roomId": room_id,
                    "members": members
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(room_id = %room_id, user_id = %user_id, error = %e, "❌ Échec de récupération des membres");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "get_members",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_get_audit_logs(hub: &ChatHub, room_id: i64, user_id: i64, limit: i64) -> Result<Option<String>> {
    info!(room_id = %room_id, user_id = %user_id, limit = %limit, "📋 Récupération des logs d'audit");
    
    match audit::get_room_audit_logs(hub, room_id, user_id, limit, None).await {
        Ok(logs) => {
            info!(room_id = %room_id, log_count = %logs.len(), "✅ Logs d'audit récupérés");
            Ok(Some(json!({
                "type": "audit_logs",
                "data": {
                    "roomId": room_id,
                    "logs": logs
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(room_id = %room_id, user_id = %user_id, error = %e, "❌ Échec de récupération des logs d'audit");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "get_audit_logs",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

// ================================================================
// UTILITAIRES DE PARSING
// ================================================================

/// Parser un message JSON WebSocket en RoomWebSocketMessage
pub fn parse_websocket_message(message: &str) -> Result<RoomWebSocketMessage> {
    let value: Value = serde_json::from_str(message)
        .map_err(|e| ChatError::configuration_error(&format!("JSON invalide: {}", e)))?;
    
    let msg_type = value.get("type")
        .and_then(|v| v.as_str())
        .ok_or_else(|| ChatError::configuration_error("Type de message manquant"))?;
    
    let data = value.get("data")
        .ok_or_else(|| ChatError::configuration_error("Données du message manquantes"))?;
    
    match msg_type {
        "join_room" => Ok(RoomWebSocketMessage::JoinRoom {
            room_id: data.get("roomId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
        
        "leave_room" => Ok(RoomWebSocketMessage::LeaveRoom {
            room_id: data.get("roomId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
        
        "send_message" => Ok(RoomWebSocketMessage::SendMessage {
            room_id: data.get("roomId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
            username: data.get("username").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            content: data.get("content").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            parent_id: data.get("parentId").and_then(|v| v.as_i64()),
        }),
        
        "get_history" => Ok(RoomWebSocketMessage::GetHistory {
            room_id: data.get("roomId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
            limit: data.get("limit").and_then(|v| v.as_i64()).unwrap_or(50),
            before_id: data.get("beforeId").and_then(|v| v.as_i64()),
        }),
        
        "get_pinned_messages" => Ok(RoomWebSocketMessage::GetPinnedMessages {
            room_id: data.get("roomId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
        
        "add_reaction" => Ok(RoomWebSocketMessage::AddReaction {
            message_id: data.get("messageId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
            emoji: data.get("emoji").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        }),
        
        "remove_reaction" => Ok(RoomWebSocketMessage::RemoveReaction {
            message_id: data.get("messageId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
            emoji: data.get("emoji").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        }),
        
        "get_reactions" => Ok(RoomWebSocketMessage::GetReactions {
            message_id: data.get("messageId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
        
        "pin_message" => Ok(RoomWebSocketMessage::PinMessage {
            room_id: data.get("roomId").and_then(|v| v.as_i64()).unwrap_or(0),
            message_id: data.get("messageId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
        
        "unpin_message" => Ok(RoomWebSocketMessage::UnpinMessage {
            room_id: data.get("roomId").and_then(|v| v.as_i64()).unwrap_or(0),
            message_id: data.get("messageId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
        
        "get_room_stats" => Ok(RoomWebSocketMessage::GetRoomStats {
            room_id: data.get("roomId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
        
        "get_members" => Ok(RoomWebSocketMessage::GetMembers {
            room_id: data.get("roomId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
        
        "get_audit_logs" => Ok(RoomWebSocketMessage::GetAuditLogs {
            room_id: data.get("roomId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
            limit: data.get("limit").and_then(|v| v.as_i64()).unwrap_or(50),
        }),
        
        _ => Err(ChatError::configuration_error(&format!("Type de message non supporté: {}", msg_type)))
    }
} 