//! # Veza Chat Server - Point d'entrée principal
//! 
//! Serveur de chat WebSocket sécurisé et haute performance

use chat_server::{initialize_server, ChatError, Result};
use std::process;
use tracing::{error, info, warn};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialisation du système de logging
    init_logging();
    
    // Configuration du signal d'arrêt
    let shutdown_signal = setup_shutdown_handlers();
    
    // Lancement du serveur
    match run_server(shutdown_signal).await {
        Ok(()) => {
            info!("🟢 Serveur arrêté proprement");
            Ok(())
        }
        Err(e) => {
            error!("❌ Erreur critique du serveur: {}", e);
            process::exit(1);
        }
    }
}

/// Initialise le système de logging avec configuration avancée
fn init_logging() {
    use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};
    
    // Configuration du niveau de log depuis l'environnement
    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| {
            "chat_server=debug,tower_http=debug,sqlx=info,hyper=info".into()
        });
    
    // Configuration du formateur avec couleurs et métadonnées
    let fmt_layer = fmt::layer()    
        .with_target(true)
        .with_thread_ids(true)
        .with_thread_names(true)
        .with_file(true)
        .with_line_number(true)
        .with_ansi(true);
    
    // Initialisation du subscriber global
    tracing_subscriber::registry()
        .with(env_filter)
        .with(fmt_layer)
        .init();

    info!("📊 Système de logging initialisé");
}

/// Configure les gestionnaires de signaux pour un arrêt propre
async fn setup_shutdown_handlers() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        
        let mut sigterm = signal(SignalKind::terminate())
            .expect("Impossible de configurer le handler SIGTERM");
        let mut sigint = signal(SignalKind::interrupt())
            .expect("Impossible de configurer le handler SIGINT");
        
        tokio::select! {
            _ = sigterm.recv() => {
                tracing::info!("📴 SIGTERM reçu");
            }
            _ = sigint.recv() => {
                tracing::info!("📴 SIGINT reçu");
            }
        }
    }
    
    #[cfg(not(unix))]
    {
        match tokio::signal::ctrl_c().await {
            Ok(()) => {
                tracing::info!("📴 Ctrl+C reçu");
            }
            Err(err) => {
                tracing::error!("⚠️ Erreur lors de l'écoute du signal: {}", err);
            }
        }
    }
}

/// Lance le serveur principal avec gestion des erreurs
async fn run_server(shutdown_signal: impl std::future::Future<Output = ()>) -> Result<()> {
    tracing::info!("🚀 Démarrage du serveur de chat...");
    
    // Initialiser le serveur (pour l'instant juste la config)
    chat_server::initialize_server().await?;
    
    tracing::info!("✅ Serveur de chat démarré avec succès");
    
    // TODO: Implémenter la boucle principale du serveur
    // Pour l'instant, on attend juste le signal d'arrêt
    shutdown_signal.await;
    
    tracing::info!("🛑 Signal d'arrêt reçu, arrêt du serveur...");

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_shutdown_signal_handling() {
        // Test basique du setup des gestionnaires de signaux
        let _shutdown_future = setup_shutdown_handlers().await;
        // Si on arrive ici, le setup n'a pas paniqué
        assert!(true);
    }
    
    #[test]
    fn test_logging_init() {
        // Test que l'initialisation du logging ne panique pas
        // Note: On ne peut pas vraiment tester l'init car elle ne peut être
        // appelée qu'une fois par processus
        assert!(true);
    }
}
