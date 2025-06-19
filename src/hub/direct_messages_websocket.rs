//! Gestionnaire WebSocket enrichi pour les messages directs (DM)
//! 
//! Fonctionnalités équivalentes aux salons :
//! - Gestion complète des conversations DM
//! - Réactions en temps réel
//! - Messages épinglés
//! - Threads et réponses
//! - Édition de messages
//! - Historique paginé

use crate::hub::{ChatHub, dm_enhanced, reactions, audit};
use crate::error::{ChatError, Result};
use serde_json::{json, Value};
use tracing::{info, warn, error};

// ================================================================
// TYPES DE MESSAGES WEBSOCKET DM
// ================================================================

pub enum DmWebSocketMessage {
    // Gestion des conversations
    CreateConversation { user1_id: i64, user2_id: i64 },
    BlockConversation { conversation_id: i64, user_id: i64, block: bool },
    ListConversations { user_id: i64, limit: i64 },
    
    // Messages
    SendMessage { conversation_id: i64, user_id: i64, username: String, content: String, parent_id: Option<i64> },
    EditMessage { message_id: i64, user_id: i64, new_content: String, edit_reason: Option<String> },
    
    // Historique et recherche
    GetHistory { conversation_id: i64, user_id: i64, limit: i64, before_id: Option<i64> },
    GetPinnedMessages { conversation_id: i64, user_id: i64 },
    
    // Réactions (utilise le même système que les salons)
    AddReaction { message_id: i64, user_id: i64, emoji: String },
    RemoveReaction { message_id: i64, user_id: i64, emoji: String },
    GetReactions { message_id: i64, user_id: i64 },
    
    // Épinglage
    PinMessage { conversation_id: i64, message_id: i64, user_id: i64 },
    UnpinMessage { conversation_id: i64, message_id: i64, user_id: i64 },
    
    // Administration
    GetDmStats { conversation_id: i64, user_id: i64 },
    GetAuditLogs { conversation_id: i64, user_id: i64, limit: i64 },
}

// ================================================================
// GESTIONNAIRE PRINCIPAL
// ================================================================

pub async fn handle_dm_websocket_message(
    hub: &ChatHub,
    message: DmWebSocketMessage
) -> Result<Option<String>> {
    match message {
        // Gestion des conversations
        DmWebSocketMessage::CreateConversation { user1_id, user2_id } => {
            handle_create_conversation(hub, user1_id, user2_id).await
        }
        
        DmWebSocketMessage::BlockConversation { conversation_id, user_id, block } => {
            handle_block_conversation(hub, conversation_id, user_id, block).await
        }
        
        DmWebSocketMessage::ListConversations { user_id, limit } => {
            handle_list_conversations(hub, user_id, limit).await
        }
        
        // Messages
        DmWebSocketMessage::SendMessage { conversation_id, user_id, username, content, parent_id } => {
            handle_send_dm_message(hub, conversation_id, user_id, &username, &content, parent_id).await
        }
        
        DmWebSocketMessage::EditMessage { message_id, user_id, new_content, edit_reason } => {
            handle_edit_dm_message(hub, message_id, user_id, &new_content, edit_reason.as_deref()).await
        }
        
        // Historique
        DmWebSocketMessage::GetHistory { conversation_id, user_id, limit, before_id } => {
            handle_get_dm_history(hub, conversation_id, user_id, limit, before_id).await
        }
        
        DmWebSocketMessage::GetPinnedMessages { conversation_id, user_id } => {
            handle_get_pinned_dm_messages(hub, conversation_id, user_id).await
        }
        
        // Réactions (réutilise le système des salons)
        DmWebSocketMessage::AddReaction { message_id, user_id, emoji } => {
            handle_add_dm_reaction(hub, message_id, user_id, &emoji).await
        }
        
        DmWebSocketMessage::RemoveReaction { message_id, user_id, emoji } => {
            handle_remove_dm_reaction(hub, message_id, user_id, &emoji).await
        }
        
        DmWebSocketMessage::GetReactions { message_id, user_id } => {
            handle_get_dm_reactions(hub, message_id, user_id).await
        }
        
        // Épinglage
        DmWebSocketMessage::PinMessage { conversation_id, message_id, user_id } => {
            handle_pin_dm_message(hub, conversation_id, message_id, user_id, true).await
        }
        
        DmWebSocketMessage::UnpinMessage { conversation_id, message_id, user_id } => {
            handle_pin_dm_message(hub, conversation_id, message_id, user_id, false).await
        }
        
        // Administration
        DmWebSocketMessage::GetDmStats { conversation_id, user_id } => {
            handle_get_dm_stats(hub, conversation_id, user_id).await
        }
        
        DmWebSocketMessage::GetAuditLogs { conversation_id, user_id, limit } => {
            handle_get_dm_audit_logs(hub, conversation_id, user_id, limit).await
        }
    }
}

// ================================================================
// GESTIONNAIRES SPÉCIFIQUES
// ================================================================

async fn handle_create_conversation(hub: &ChatHub, user1_id: i64, user2_id: i64) -> Result<Option<String>> {
    info!(user1_id = %user1_id, user2_id = %user2_id, "💬 Création/récupération de conversation DM");
    
    match dm_enhanced::get_or_create_dm_conversation(hub, user1_id, user2_id).await {
        Ok(conversation) => {
            info!(conversation_id = %conversation.id, "✅ Conversation DM créée/récupérée");
            Ok(Some(json!({
                "type": "dm_conversation_created",
                "data": {
                    "conversation": conversation,
                    "success": true
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(user1_id = %user1_id, user2_id = %user2_id, error = %e, "❌ Échec de création de conversation DM");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "create_conversation",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_block_conversation(hub: &ChatHub, conversation_id: i64, user_id: i64, block: bool) -> Result<Option<String>> {
    let action_text = if block { "blocage" } else { "déblocage" };
    info!(conversation_id = %conversation_id, user_id = %user_id, block = %block, "🚫 {} de conversation DM", action_text);
    
    match dm_enhanced::block_dm_conversation(hub, conversation_id, user_id, block).await {
        Ok(()) => {
            info!(conversation_id = %conversation_id, block = %block, "✅ Statut de blocage mis à jour");
            Ok(Some(json!({
                "type": if block { "dm_conversation_blocked" } else { "dm_conversation_unblocked" },
                "data": {
                    "conversationId": conversation_id,
                    "isBlocked": block,
                    "success": true
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(conversation_id = %conversation_id, user_id = %user_id, error = %e, "❌ Échec de {} de conversation", action_text);
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": if block { "block_conversation" } else { "unblock_conversation" },
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_list_conversations(hub: &ChatHub, user_id: i64, limit: i64) -> Result<Option<String>> {
    info!(user_id = %user_id, limit = %limit, "📋 Liste des conversations DM");
    
    match dm_enhanced::list_user_dm_conversations(hub, user_id, limit).await {
        Ok(conversations) => {
            info!(user_id = %user_id, conversation_count = %conversations.len(), "✅ Conversations DM listées");
            Ok(Some(json!({
                "type": "dm_conversations_list",
                "data": {
                    "conversations": conversations,
                    "total": conversations.len()
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(user_id = %user_id, error = %e, "❌ Échec de liste des conversations DM");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "list_conversations",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_send_dm_message(
    hub: &ChatHub,
    conversation_id: i64,
    user_id: i64,
    username: &str,
    content: &str,
    parent_id: Option<i64>
) -> Result<Option<String>> {
    info!(conversation_id = %conversation_id, user_id = %user_id, content_length = %content.len(), "📝 Envoi de message DM enrichi");
    
    match dm_enhanced::send_dm_message(hub, conversation_id, user_id, username, content, parent_id, None).await {
        Ok(message_id) => {
            info!(conversation_id = %conversation_id, message_id = %message_id, "✅ Message DM enrichi envoyé");
            Ok(Some(json!({
                "type": "dm_message_sent",
                "data": {
                    "messageId": message_id,
                    "conversationId": conversation_id,
                    "success": true
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(conversation_id = %conversation_id, user_id = %user_id, error = %e, "❌ Échec d'envoi de message DM");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "send_dm_message",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_edit_dm_message(
    hub: &ChatHub,
    message_id: i64,
    user_id: i64,
    new_content: &str,
    edit_reason: Option<&str>
) -> Result<Option<String>> {
    info!(message_id = %message_id, user_id = %user_id, "✏️ Édition de message DM");
    
    match dm_enhanced::edit_dm_message(hub, message_id, user_id, new_content, edit_reason).await {
        Ok(()) => {
            info!(message_id = %message_id, "✅ Message DM édité");
            Ok(Some(json!({
                "type": "dm_message_edited",
                "data": {
                    "messageId": message_id,
                    "newContent": new_content,
                    "editReason": edit_reason,
                    "success": true
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(message_id = %message_id, user_id = %user_id, error = %e, "❌ Échec d'édition de message DM");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "edit_dm_message",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_get_dm_history(
    hub: &ChatHub,
    conversation_id: i64,
    user_id: i64,
    limit: i64,
    before_id: Option<i64>
) -> Result<Option<String>> {
    info!(conversation_id = %conversation_id, user_id = %user_id, limit = %limit, "📚 Récupération de l'historique DM enrichi");
    
    match dm_enhanced::fetch_dm_history(hub, conversation_id, user_id, limit, before_id).await {
        Ok(messages) => {
            info!(conversation_id = %conversation_id, message_count = %messages.len(), "✅ Historique DM enrichi récupéré");
            Ok(Some(json!({
                "type": "dm_history",
                "data": {
                    "conversationId": conversation_id,
                    "messages": messages,
                    "hasMore": messages.len() as i64 == limit
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(conversation_id = %conversation_id, user_id = %user_id, error = %e, "❌ Échec de récupération de l'historique DM");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "get_dm_history",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_get_pinned_dm_messages(hub: &ChatHub, conversation_id: i64, user_id: i64) -> Result<Option<String>> {
    info!(conversation_id = %conversation_id, user_id = %user_id, "📌 Récupération des messages DM épinglés");
    
    match dm_enhanced::fetch_pinned_dm_messages(hub, conversation_id, user_id).await {
        Ok(messages) => {
            info!(conversation_id = %conversation_id, pinned_count = %messages.len(), "✅ Messages DM épinglés récupérés");
            Ok(Some(json!({
                "type": "dm_pinned_messages",
                "data": {
                    "conversationId": conversation_id,
                    "messages": messages
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(conversation_id = %conversation_id, user_id = %user_id, error = %e, "❌ Échec de récupération des messages DM épinglés");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "get_pinned_dm_messages",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_add_dm_reaction(hub: &ChatHub, message_id: i64, user_id: i64, emoji: &str) -> Result<Option<String>> {
    info!(message_id = %message_id, user_id = %user_id, emoji = %emoji, "😊 Ajout de réaction DM");
    
    // Utilise le même système de réactions que les salons
    match reactions::add_reaction(hub, message_id, user_id, emoji).await {
        Ok(()) => {
            info!(message_id = %message_id, emoji = %emoji, "✅ Réaction DM ajoutée");
            Ok(Some(json!({
                "type": "dm_reaction_added",
                "data": {
                    "messageId": message_id,
                    "userId": user_id,
                    "emoji": emoji,
                    "success": true
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(message_id = %message_id, user_id = %user_id, error = %e, "❌ Échec d'ajout de réaction DM");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "add_dm_reaction",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_remove_dm_reaction(hub: &ChatHub, message_id: i64, user_id: i64, emoji: &str) -> Result<Option<String>> {
    info!(message_id = %message_id, user_id = %user_id, emoji = %emoji, "🗑️ Suppression de réaction DM");
    
    match reactions::remove_reaction(hub, message_id, user_id, emoji).await {
        Ok(()) => {
            info!(message_id = %message_id, emoji = %emoji, "✅ Réaction DM supprimée");
            Ok(Some(json!({
                "type": "dm_reaction_removed",
                "data": {
                    "messageId": message_id,
                    "userId": user_id,
                    "emoji": emoji,
                    "success": true
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(message_id = %message_id, user_id = %user_id, error = %e, "❌ Échec de suppression de réaction DM");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "remove_dm_reaction",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_get_dm_reactions(hub: &ChatHub, message_id: i64, user_id: i64) -> Result<Option<String>> {
    info!(message_id = %message_id, user_id = %user_id, "📊 Récupération des réactions DM");
    
    match reactions::get_message_reactions(hub, message_id, user_id).await {
        Ok(message_reactions) => {
            info!(message_id = %message_id, total_reactions = %message_reactions.total_reactions, "✅ Réactions DM récupérées");
            Ok(Some(json!({
                "type": "dm_message_reactions",
                "data": message_reactions
            }).to_string()))
        }
        Err(e) => {
            warn!(message_id = %message_id, user_id = %user_id, error = %e, "❌ Échec de récupération des réactions DM");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "get_dm_reactions",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_pin_dm_message(hub: &ChatHub, conversation_id: i64, message_id: i64, user_id: i64, pin: bool) -> Result<Option<String>> {
    let action_text = if pin { "épinglage" } else { "désépinglage" };
    info!(conversation_id = %conversation_id, message_id = %message_id, user_id = %user_id, pin = %pin, "📌 {} de message DM", action_text);
    
    match dm_enhanced::pin_dm_message(hub, conversation_id, message_id, user_id, pin).await {
        Ok(()) => {
            info!(message_id = %message_id, pin = %pin, "✅ Statut d'épinglage DM mis à jour");
            Ok(Some(json!({
                "type": if pin { "dm_message_pinned" } else { "dm_message_unpinned" },
                "data": {
                    "messageId": message_id,
                    "conversationId": conversation_id,
                    "isPinned": pin,
                    "success": true
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(message_id = %message_id, user_id = %user_id, error = %e, "❌ Échec de {} de message DM", action_text);
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": if pin { "pin_dm_message" } else { "unpin_dm_message" },
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_get_dm_stats(hub: &ChatHub, conversation_id: i64, user_id: i64) -> Result<Option<String>> {
    info!(conversation_id = %conversation_id, user_id = %user_id, "📊 Récupération des statistiques DM");
    
    match dm_enhanced::get_dm_stats(hub, conversation_id, user_id).await {
        Ok(stats) => {
            info!(conversation_id = %conversation_id, "✅ Statistiques DM récupérées");
            Ok(Some(json!({
                "type": "dm_stats",
                "data": stats
            }).to_string()))
        }
        Err(e) => {
            warn!(conversation_id = %conversation_id, user_id = %user_id, error = %e, "❌ Échec de récupération des statistiques DM");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "get_dm_stats",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

async fn handle_get_dm_audit_logs(hub: &ChatHub, conversation_id: i64, user_id: i64, limit: i64) -> Result<Option<String>> {
    info!(conversation_id = %conversation_id, user_id = %user_id, limit = %limit, "📋 Récupération des logs d'audit DM");
    
    // Adapter les logs d'audit pour les DM (chercher par conversation_id dans les détails)
    match audit::get_room_audit_logs(hub, conversation_id, user_id, limit, None).await {
        Ok(logs) => {
            info!(conversation_id = %conversation_id, log_count = %logs.len(), "✅ Logs d'audit DM récupérés");
            Ok(Some(json!({
                "type": "dm_audit_logs",
                "data": {
                    "conversationId": conversation_id,
                    "logs": logs
                }
            }).to_string()))
        }
        Err(e) => {
            warn!(conversation_id = %conversation_id, user_id = %user_id, error = %e, "❌ Échec de récupération des logs d'audit DM");
            Ok(Some(json!({
                "type": "error",
                "data": {
                    "action": "get_dm_audit_logs",
                    "error": e.to_string()
                }
            }).to_string()))
        }
    }
}

// ================================================================
// UTILITAIRES DE PARSING
// ================================================================

/// Parser un message JSON WebSocket en DmWebSocketMessage
pub fn parse_dm_websocket_message(message: &str) -> Result<DmWebSocketMessage> {
    let value: Value = serde_json::from_str(message)
        .map_err(|e| ChatError::configuration_error(&format!("JSON invalide: {}", e)))?;
    
    let msg_type = value.get("type")
        .and_then(|v| v.as_str())
        .ok_or_else(|| ChatError::configuration_error("Type de message manquant"))?;
    
    let data = value.get("data")
        .ok_or_else(|| ChatError::configuration_error("Données du message manquantes"))?;
    
    match msg_type {
        "create_dm_conversation" => Ok(DmWebSocketMessage::CreateConversation {
            user1_id: data.get("user1Id").and_then(|v| v.as_i64()).unwrap_or(0),
            user2_id: data.get("user2Id").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
        
        "block_dm_conversation" => Ok(DmWebSocketMessage::BlockConversation {
            conversation_id: data.get("conversationId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
            block: data.get("block").and_then(|v| v.as_bool()).unwrap_or(true),
        }),
        
        "list_dm_conversations" => Ok(DmWebSocketMessage::ListConversations {
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
            limit: data.get("limit").and_then(|v| v.as_i64()).unwrap_or(50),
        }),
        
        "send_dm_message" => Ok(DmWebSocketMessage::SendMessage {
            conversation_id: data.get("conversationId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
            username: data.get("username").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            content: data.get("content").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            parent_id: data.get("parentId").and_then(|v| v.as_i64()),
        }),
        
        "edit_dm_message" => Ok(DmWebSocketMessage::EditMessage {
            message_id: data.get("messageId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
            new_content: data.get("newContent").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            edit_reason: data.get("editReason").and_then(|v| v.as_str()).map(|s| s.to_string()),
        }),
        
        "get_dm_history" => Ok(DmWebSocketMessage::GetHistory {
            conversation_id: data.get("conversationId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
            limit: data.get("limit").and_then(|v| v.as_i64()).unwrap_or(50),
            before_id: data.get("beforeId").and_then(|v| v.as_i64()),
        }),
        
        "get_pinned_dm_messages" => Ok(DmWebSocketMessage::GetPinnedMessages {
            conversation_id: data.get("conversationId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
        
        "add_dm_reaction" => Ok(DmWebSocketMessage::AddReaction {
            message_id: data.get("messageId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
            emoji: data.get("emoji").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        }),
        
        "remove_dm_reaction" => Ok(DmWebSocketMessage::RemoveReaction {
            message_id: data.get("messageId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
            emoji: data.get("emoji").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        }),
        
        "get_dm_reactions" => Ok(DmWebSocketMessage::GetReactions {
            message_id: data.get("messageId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
        
        "pin_dm_message" => Ok(DmWebSocketMessage::PinMessage {
            conversation_id: data.get("conversationId").and_then(|v| v.as_i64()).unwrap_or(0),
            message_id: data.get("messageId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
        
        "unpin_dm_message" => Ok(DmWebSocketMessage::UnpinMessage {
            conversation_id: data.get("conversationId").and_then(|v| v.as_i64()).unwrap_or(0),
            message_id: data.get("messageId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
        
        "get_dm_stats" => Ok(DmWebSocketMessage::GetDmStats {
            conversation_id: data.get("conversationId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
        
        "get_dm_audit_logs" => Ok(DmWebSocketMessage::GetAuditLogs {
            conversation_id: data.get("conversationId").and_then(|v| v.as_i64()).unwrap_or(0),
            user_id: data.get("userId").and_then(|v| v.as_i64()).unwrap_or(0),
            limit: data.get("limit").and_then(|v| v.as_i64()).unwrap_or(50),
        }),
        
        _ => Err(ChatError::configuration_error(&format!("Type de message DM non supporté: {}", msg_type)))
    }
} 