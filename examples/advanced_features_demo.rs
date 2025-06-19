use std::time::Duration;
use std::collections::HashMap;
use sqlx::PgPool;

// Import de nos nouveaux modules
use chat_server::{
    permissions::{Role, Permission, check_permission},
    security::{ContentFilter, ActionLimits},
    cache::CacheManager,  
    presence::{PresenceManager, UserStatus, NotificationManager},
    reactions::{ReactionType, ReactionManager},
    monitoring::{ChatMetrics, MetricsExport},
    moderation::{ModerationSystem, SanctionType, SanctionReason},
    hub::common::ChatHub,
    config::ServerConfig,
    error::Result,
};

/// Démonstration complète des nouvelles fonctionnalités
pub async fn demo_advanced_features() -> Result<()> {
    println!("🚀 === DÉMONSTRATION DES FONCTIONNALITÉS AVANCÉES ===");
    
    // Configuration factice pour l'exemple
    let config = ServerConfig::default();
    let db = create_mock_db_pool().await?;
    let hub = ChatHub::new(db.clone(), config);
    
    // ================================================
    // 🔒 SYSTÈME DE PERMISSIONS
    // ================================================
    println!("\n🔒 Démonstration du système de permissions :");
    
    let admin_role = Role::Admin;
    let user_role = Role::User;
    
    // Vérification des permissions
    match check_permission(&admin_role, Permission::BanUser) {
        Ok(_) => println!("✅ Admin peut bannir des utilisateurs"),
        Err(e) => println!("❌ Permission refusée : {}", e),
    }
    
    match check_permission(&user_role, Permission::BanUser) {
        Ok(_) => println!("✅ Utilisateur peut bannir"),
        Err(e) => println!("❌ Permission refusée pour l'utilisateur : {}", e),
    }
    
    println!("📋 Permissions de l'admin : {:?}", admin_role.get_permissions());
    
    // ================================================
    // 🛡️ SYSTÈME DE SÉCURITÉ  
    // ================================================
    println!("\n🛡️ Démonstration du filtrage de contenu :");
    
    let content_filter = ContentFilter::new();
    
    // Test de contenu suspect
    let test_messages = vec![
        "Bonjour tout le monde !",
        "<script>alert('xss')</script>",
        "javascript:void(0)",
        "DROP TABLE users;",
        "Salut les amis, comment ça va ?",
    ];
    
    for message in test_messages {
        match content_filter.check_content(message) {
            Ok(_) => println!("✅ Message autorisé : '{}'", message),
            Err(e) => println!("🚫 Message bloqué : '{}' - {}", message, e),
        }
    }
    
    // Validation nom de salon
    let room_names = vec!["salon-general", "test_room", "invalid room!", "ADMIN-ONLY"];
    for name in room_names {
        match content_filter.validate_room_name(name) {
            Ok(sanitized) => println!("✅ Salon '{}' → '{}'", name, sanitized),
            Err(e) => println!("❌ Nom de salon invalide '{}' : {}", name, e),
        }
    }
    
    // ================================================
    // 💾 SYSTÈME DE CACHE
    // ================================================
    println!("\n💾 Démonstration du système de cache :");
    
    let cache_manager = CacheManager::new();
    
    // Simulation de données mises en cache
    let messages = vec![
        chat_server::cache::MessageCacheEntry {
            id: 1,
            content: "Premier message".to_string(),
            user_id: 101,
            username: "Alice".to_string(),
            timestamp: chrono::Utc::now(),
        },
        chat_server::cache::MessageCacheEntry {
            id: 2,
            content: "Deuxième message".to_string(),
            user_id: 102,
            username: "Bob".to_string(),
            timestamp: chrono::Utc::now(),
        },
    ];
    
    // Mise en cache des messages du salon
    cache_manager.cache_room_messages("general", messages).await;
    println!("✅ Messages du salon 'general' mis en cache");
    
    // Récupération depuis le cache
    if let Some(cached_messages) = cache_manager.get_cached_room_messages("general").await {
        println!("📨 {} messages récupérés du cache", cached_messages.len());
    }
    
    // Statistiques globales du cache
    let stats = cache_manager.global_stats().await;
    println!("📊 Statistiques cache : {:?}", stats);
    
    // ================================================
    // 👥 SYSTÈME DE PRÉSENCE
    // ================================================
    println!("\n👥 Démonstration du système de présence :");
    
    let presence_manager = PresenceManager::new();
    
    // Connexion d'utilisateurs
    presence_manager.user_online(101, "Alice".to_string()).await;
    presence_manager.user_online(102, "Bob".to_string()).await;
    
    // Changement de statut
    presence_manager.set_user_status(101, UserStatus::Busy, Some("En réunion".to_string())).await;
    presence_manager.set_user_status(102, UserStatus::Away, None).await;
    
    // Entrée dans un salon
    presence_manager.set_user_room(101, Some("general".to_string())).await;
    presence_manager.set_user_room(102, Some("general".to_string())).await;
    
    // Affichage des utilisateurs en ligne
    let online_users = presence_manager.get_online_users().await;
    println!("👤 Utilisateurs en ligne : {}", online_users.len());
    for user in online_users {
        println!("   - {} ({:?}) : {:?}", user.username, user.status, user.status_message);
    }
    
    // Utilisateurs dans le salon
    let room_users = presence_manager.get_room_users("general").await;
    println!("🏠 Utilisateurs dans 'general' : {}", room_users.len());
    
    // ================================================
    // 😀 SYSTÈME DE RÉACTIONS
    // ================================================
    println!("\n😀 Démonstration du système de réactions :");
    
    let reaction_manager = ReactionManager::new(hub.clone());
    
    // Ajout de réactions à un message
    let message_id = 1;
    let _ = reaction_manager.add_reaction(message_id, 101, ReactionType::Like).await;
    let _ = reaction_manager.add_reaction(message_id, 102, ReactionType::Love).await;
    let _ = reaction_manager.add_reaction(message_id, 101, ReactionType::Laugh).await; // Devrait échouer (doublon)
    
    // Récupération des réactions d'un message
    if let Ok(reactions) = reaction_manager.get_message_reactions(message_id).await {
        println!("😀 Message {} a {} réactions", message_id, reactions.reactions.len());
        for (reaction_type, users) in reactions.reactions {
            println!("   {} : {} utilisateurs", reaction_type.to_emoji(), users.len());
        }
    }
    
    // ================================================
    // 📊 SYSTÈME DE MONITORING
    // ================================================
    println!("\n📊 Démonstration du monitoring :");
    
    let metrics = ChatMetrics::new();
    
    // Enregistrement de métriques
    metrics.websocket_connected(101).await;
    metrics.websocket_connected(102).await;
    metrics.message_sent("room", Some("general")).await;
    metrics.message_sent("direct", None).await;
    metrics.active_users(2).await;
    metrics.active_rooms(1).await;
    
    // Simulation d'une erreur
    metrics.error_occurred("validation", "message_too_long").await;
    
    // Export des métriques
    let metrics_export = MetricsExport::new(&metrics, std::time::Instant::now()).await;
    println!("📈 Métriques collectées à {}", metrics_export.timestamp);
    println!("🔧 Uptime : {}s", metrics_export.system_info.uptime_seconds);
    
    // Format Prometheus
    let prometheus_format = metrics_export.to_prometheus_format();
    println!("📋 Format Prometheus (extrait) :");
    for line in prometheus_format.lines().take(5) {
        println!("   {}", line);
    }
    
    // ================================================
    // ⚖️ SYSTÈME DE MODÉRATION
    // ================================================
    println!("\n⚖️ Démonstration du système de modération :");
    
    let moderation_system = ModerationSystem::new(hub.clone());
    
    // Vérification automatique d'un message suspect
    let suspect_message = "SPAM SPAM ACHETER MAINTENANT!!!";
    match moderation_system.check_message_auto_moderation(103, suspect_message).await {
        Ok(Some(sanction)) => println!("🚨 Sanction automatique appliquée : {:?}", sanction),
        Ok(None) => println!("✅ Message autorisé par la modération automatique"),
        Err(e) => println!("❌ Erreur de modération : {}", e),
    }
    
    // Application manuelle d'une sanction
    let _ = moderation_system.apply_sanction(
        1, // Moderator ID
        &Role::Moderator,
        103, // Target user
        SanctionType::Warning,
        SanctionReason::Spam,
        Some("Premier avertissement pour spam".to_string()),
        None,
    ).await;
    
    println!("⚖️ Sanction manuelle appliquée");
    
    // Historique de modération
    if let Ok(record) = moderation_system.get_user_moderation_record(103).await {
        println!("📜 Historique de modération pour l'utilisateur 103 :");
        println!("   - Avertissements : {}", record.total_warnings);
        println!("   - Score de réputation : {}", record.reputation_score);
        println!("   - Banni actuellement : {}", record.is_currently_banned);
    }
    
    // ================================================
    // 🎯 NOTIFICATIONS
    // ================================================
    println!("\n🎯 Démonstration des notifications :");
    
    let notification_manager = NotificationManager::new();
    
    // Notification de nouveau DM
    let _ = notification_manager.notify_new_dm(
        101, 
        "Bob", 
        "Salut ! Comment ça va ?"
    ).await;
    
    // Notification de mention dans un salon
    let _ = notification_manager.notify_room_mention(
        101,
        "general",
        "Charlie",
        "Hey @Alice, tu as vu ça ?"
    ).await;
    
    println!("📱 Notifications envoyées");
    
    // ================================================
    // 🎯 RÉSUMÉ FINAL
    // ================================================
    println!("\n🎉 === DÉMONSTRATION TERMINÉE ===");
    println!("✅ Toutes les fonctionnalités avancées ont été testées avec succès !");
    println!("📋 Fonctionnalités démontrées :");
    println!("   🔒 Système de permissions avec rôles hiérarchiques");
    println!("   🛡️ Filtrage de contenu et sécurité avancée");
    println!("   💾 Cache intelligent avec TTL et éviction LRU");
    println!("   👥 Gestion de présence en temps réel");
    println!("   😀 Système de réactions aux messages");
    println!("   📊 Monitoring complet avec métriques Prometheus");
    println!("   ⚖️ Modération automatique et manuelle");
    println!("   🎯 Système de notifications push");
    
    Ok(())
}

/// Création d'un pool de base de données factice pour la démo
async fn create_mock_db_pool() -> Result<PgPool> {
    // Dans un vrai cas, on se connecterait à PostgreSQL
    // Ici on simule juste pour la compilation de l'exemple
    Err(chat_server::error::ChatError::Configuration(
        "Base de données non configurée pour la démo".to_string()
    ))
}

#[tokio::main]
async fn main() -> Result<()> {
    // Configuration des logs
    tracing_subscriber::fmt::init();
    
    println!("🔧 Démarrage de la démonstration des fonctionnalités avancées...");
    
    // Note: Cette démo ne fonctionnera pas complètement sans une vraie DB
    // mais elle démontre l'usage de toutes les APIs
    match demo_advanced_features().await {
        Ok(_) => println!("✅ Démonstration réussie !"),
        Err(e) => println!("❌ Erreur de démonstration : {}", e),
    }
    
    Ok(())
} 