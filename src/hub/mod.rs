//file: backend/modules/chat_server/src/hub/mod.rs

//! Module Hub - Gestion centralisée du chat en temps réel
//! 
//! Ce module contient tous les composants pour la gestion du hub de chat,
//! incluant les salons, messages directs, réactions, audit et WebSocket.

// ================================================================
// MODULES CORE
// ================================================================

/// Structures communes et hub principal
pub mod common;

/// Gestion des salons de chat (anciennement room_enhanced)
pub mod channels;

/// Gestion des messages directs (anciennement dm_enhanced)
pub mod direct_messages;

/// Système de réactions aux messages
pub mod reactions;

/// Système d'audit et de logs de sécurité
pub mod audit;

// ================================================================
// MODULES WEBSOCKET
// ================================================================

/// WebSocket pour les salons de chat
pub mod channel_websocket;

/// WebSocket pour les messages directs
pub mod direct_messages_websocket;

// ================================================================
// RÉEXPORTS PRINCIPAUX
// ================================================================

// Types et fonctions du hub principal
pub use common::{ChatHub, HubStats};

// Types et fonctions pour les salons de chat
pub use channels::{
    Room, RoomMember, EnhancedRoomMessage as RoomMessage, 
    RoomStats, RoomPermissions,
    create_room, join_room, leave_room,
    send_room_message, pin_message as pin_room_message,
    fetch_room_history, fetch_pinned_messages as fetch_pinned_room_messages,
    get_room_stats, list_room_members
};

// Types et fonctions pour les messages directs
pub use direct_messages::{
    DmConversation, DmMessage, DmStats, DmParticipant,
    get_or_create_conversation as get_or_create_dm_conversation,
    block_conversation as block_dm_conversation,
    send_message as send_dm_message, 
    pin_message as pin_dm_message, 
    edit_message as edit_dm_message,
    fetch_history as fetch_dm_history,
    fetch_pinned_messages as fetch_pinned_dm_messages,
    get_stats as get_dm_stats, 
    list_user_conversations as list_user_dm_conversations
};

// Système de réactions
pub use reactions::{
    MessageReaction, ReactionSummary, MessageReactions,
    add_reaction, remove_reaction, toggle_reaction,
    get_message_reactions, get_user_reactions, get_popular_emojis
};

// Système d'audit
pub use audit::{
    AuditLog, SecurityEvent, ActivityReport, UserActivity, RoomAuditSummary,
    log_action, log_security_event,
    log_room_created, log_member_change, log_message_modified, log_moderation_action,
    get_room_audit_logs, get_room_security_events,
    generate_room_activity_report, get_room_audit_summary,
    detect_suspicious_patterns
};

// Handlers WebSocket
pub use channel_websocket::{
    RoomWebSocketMessage, handle_room_websocket_message, parse_websocket_message as parse_room_websocket_message
};

pub use direct_messages_websocket::{
    DmWebSocketMessage, handle_dm_websocket_message, parse_dm_websocket_message
};
