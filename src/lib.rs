//! # Veza Chat Server - Serveur de chat temps réel en Rust
//! 
//! Serveur WebSocket haute performance avec authentification JWT,
//! messagerie unifiée (DM/Rooms), sécurité renforcée et fonctionnalités avancées.
//! 
//! ## Fonctionnalités
//! 
//! - 🔐 **Authentification sécurisée** avec JWT et 2FA
//! - 💬 **Messagerie unifiée** DM et salons publics/privés  
//! - 🛡️ **Sécurité avancée** avec filtrage de contenu et audit
//! - ⚡ **Performance optimisée** avec cache Redis et pooling
//! - 📱 **Temps réel** avec WebSocket et événements
//! - 🎯 **Production-ready** avec monitoring et logging
//! 
//! ## Architecture
//! 
//! ```text
//! ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
//! │   WebSocket     │───▶│   Chat Server    │───▶│   PostgreSQL    │
//! │   Clients       │    │   (Rust/Tokio)   │    │   Database      │
//! └─────────────────┘    └──────────────────┘    └─────────────────┘
//!                               │
//!                               ▼
//!                        ┌──────────────────┐
//!                        │   Redis Cache    │
//!                        │   (Sessions)     │
//!                        └──────────────────┘
//! ```

pub mod auth;
pub mod cache;
pub mod client;
pub mod config;
pub mod error;
pub mod hub;
pub mod message_handler;
// TODO: Réactiver après migration DB
// pub mod message_store;
// pub mod message_store_simple;
pub mod messages;
pub mod models;
pub mod moderation;
pub mod monitoring;
pub mod permissions;
pub mod presence;
pub mod rate_limiter;
pub mod reactions;
pub mod security;
pub mod security_enhanced;
pub mod services;
pub mod utils;
pub mod validation;
pub mod websocket;

// Re-exports publics
pub use auth::Claims;
// pub use auth::TokenData; // Private dans auth.rs
pub use config::ServerConfig;
pub use error::{ChatError, Result};
pub use models::*;
// TODO: Réactiver après implémentation complète
// pub use services::ChatService;
// pub use websocket::{WebSocketHandler, WebSocketMessage};

/// Version du serveur
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Message de bienvenue avec informations système
pub fn welcome_message() -> String {
    format!(
        r#"
🚀 Veza Chat Server v{} 
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Serveur WebSocket haute performance
🔐 Authentification JWT + 2FA  
💬 Messagerie unifiée (DM + Salons)
🛡️ Sécurité renforcée avec audit
⚡ Cache Redis intégré
📊 Monitoring et métriques

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        "#,
        VERSION
    )
}

/// Initialise et lance le serveur de chat
pub async fn initialize_server() -> Result<()> {
    // TODO: Implémenter ChatService
    // let config = ServerConfig::from_env()?;
    // let service = ChatService::new(config).await?;
    // Ok(service)
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version_format() {
        assert!(!VERSION.is_empty());
        assert!(VERSION.contains('.'));
    }

    #[test]
    fn test_welcome_message() {
        let message = welcome_message();
        assert!(message.contains("Veza Chat Server"));
        assert!(message.contains(VERSION));
    }
} 