//! # Configuration du serveur de chat
//! 
//! Module de configuration centralisé avec support pour:
//! - Variables d'environnement
//! - Fichiers de configuration (TOML, JSON, YAML)
//! - Arguments de ligne de commande
//! - Validation des paramètres
//! - Configuration par environnement (dev, prod, test)

use crate::error::{ChatError, Result};
use clap::Parser;
use serde::{Deserialize, Serialize};
use std::fmt;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::time::Duration;
use url::Url;
use std::str::FromStr;

/// Configuration principale du serveur
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    /// Configuration du serveur
    pub server: ServerSettings,
    
    /// Configuration de la base de données
    pub database: DatabaseConfig,
    
    /// Configuration du cache Redis
    pub cache: CacheConfig,
    
    /// Configuration de sécurité
    pub security: SecurityConfig,
    
    /// Configuration des limites et quotas
    pub limits: LimitsConfig,
    
    /// Configuration des fonctionnalités
    pub features: FeaturesConfig,
    
    /// Configuration du logging
    pub logging: LoggingConfig,
    
    /// Configuration des intégrations externes
    pub integrations: IntegrationsConfig,
}

impl ServerConfig {
    /// Charge la configuration depuis l'environnement et les fichiers
    pub fn from_env() -> Result<Self> {
        // Arguments de ligne de commande
        let args = CliArgs::parse();
        
        // Configuration de base depuis l'environnement
        let mut config = config::Config::builder()
            // Valeurs par défaut
            .add_source(config::Config::try_from(&Self::default())?)
            // Fichier de configuration si spécifié
            .add_source(
                args.config_file
                    .as_ref()
                    .map(|path| config::File::with_name(path.to_str().unwrap()))
                    .unwrap_or_else(|| config::File::with_name("config/default"))
                    .required(false)
            )
            // Variables d'environnement (préfixe CHAT_SERVER_)
            .add_source(
                config::Environment::with_prefix("CHAT_SERVER")
                    .prefix_separator("_")
                    .separator("__")
            )
            .build()?;
        
        // Override avec les arguments CLI - construction de nouveau config avec overrides
        let mut config_final = config.clone();
        if args.bind_addr.is_some() || args.environment.is_some() {
            let mut builder = config::Config::builder();
            
            // Base config depuis fichiers
            builder = builder.add_source(config);
            
            // Overrides CLI
            if let Some(addr) = args.bind_addr {
                builder = builder.set_override("server.bind_addr", addr.to_string())?;
            }
            if let Some(env) = args.environment {
                builder = builder.set_override("server.environment", env.to_string())?;
            }
            
            config_final = builder.build()?;
        }
        
        let config: Self = config_final.try_deserialize()?;
        config.validate()?;
        
        Ok(config)
    }
    
    /// Valide la configuration
    fn validate(&self) -> Result<()> {
        // Validation de l'adresse de bind
        if self.server.bind_addr.port() == 0 {
            return Err(ChatError::Configuration {
                message: "Port de bind invalide".to_string(),
            });
        }
        
        // Validation de l'URL de base de données
        if self.database.url.scheme() != "postgresql" && self.database.url.scheme() != "postgres" {
            return Err(ChatError::Configuration {
                message: "URL de base de données doit utiliser le schéma postgresql://".to_string(),
            });
        }
        
        // Validation des limites
        if self.limits.max_message_length > 10000 {
            return Err(ChatError::Configuration {
                message: "Limite de taille de message trop élevée (max: 10000)".to_string(),
            });
        }
        
        // Validation du secret JWT
        if self.security.jwt_secret.len() < 32 {
            return Err(ChatError::Configuration {
                message: "Secret JWT trop court (minimum 32 caractères)".to_string(),
            });
        }
        
        Ok(())
    }
    
    /// Retourne true si on est en mode développement
    pub fn is_development(&self) -> bool {
        matches!(self.server.environment, Environment::Development)
    }
    
    /// Retourne true si on est en mode production
    pub fn is_production(&self) -> bool {
        matches!(self.server.environment, Environment::Production)
    }
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            server: ServerSettings::default(),
            database: DatabaseConfig::default(),
            cache: CacheConfig::default(),
            security: SecurityConfig::default(),
            limits: LimitsConfig::default(),
            features: FeaturesConfig::default(),
            logging: LoggingConfig::default(),
            integrations: IntegrationsConfig::default(),
        }
    }
}

impl fmt::Display for ServerConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "ServerConfig {{ env: {:?}, bind: {}, db_pool: {} }}",
            self.server.environment,
            self.server.bind_addr,
            self.database.max_connections
        )
    }
}

/// Configuration du serveur HTTP/WebSocket
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerSettings {
    /// Adresse de bind du serveur
    pub bind_addr: SocketAddr,
    
    /// Environnement d'exécution
    pub environment: Environment,
    
    /// Nombre de workers (0 = auto)
    pub workers: usize,
    
    /// Timeout de connexion
    pub connection_timeout: Duration,
    
    /// Interval de heartbeat (ping)
    pub heartbeat_interval: Duration,
    
    /// Timeout d'arrêt gracieux
    pub shutdown_timeout: Duration,
}

impl Default for ServerSettings {
    fn default() -> Self {
        Self {
            bind_addr: "127.0.0.1:8080".parse().unwrap(),
            environment: Environment::Development,
            workers: 0, // Auto-détection
            connection_timeout: Duration::from_secs(30),
            heartbeat_interval: Duration::from_secs(30),
            shutdown_timeout: Duration::from_secs(30),
        }
    }
}

/// Configuration de la base de données
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseConfig {
    /// URL de connexion PostgreSQL
    pub url: Url,
    
    /// Nombre maximum de connexions dans le pool
    pub max_connections: u32,
    
    /// Timeout de connexion
    pub connect_timeout: Duration,
    
    /// Timeout d'inactivité
    pub idle_timeout: Duration,
    
    /// Lifetime maximum d'une connexion
    pub max_lifetime: Duration,
    
    /// Exécuter les migrations au démarrage
    pub auto_migrate: bool,
}

impl Default for DatabaseConfig {
    fn default() -> Self {
        Self {
            url: "postgresql://postgres:password@localhost:5432/veza_chat"
                .parse()
                .unwrap(),
            max_connections: 10,
            connect_timeout: Duration::from_secs(30),
            idle_timeout: Duration::from_secs(600), // 10 minutes
            max_lifetime: Duration::from_secs(3600), // 1 heure
            auto_migrate: true,
        }
    }
}

/// Configuration du cache Redis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheConfig {
    /// URL de connexion Redis
    pub url: Url,
    
    /// Taille du pool de connexions
    pub pool_size: u32,
    
    /// Timeout de connexion
    pub connect_timeout: Duration,
    
    /// TTL par défaut pour les clés
    pub default_ttl: Duration,
    
    /// Préfixe pour toutes les clés
    pub key_prefix: String,
    
    /// Activé ou non
    pub enabled: bool,
}

impl Default for CacheConfig {
    fn default() -> Self {
        Self {
            url: "redis://localhost:6379".parse().unwrap(),
            pool_size: 10,
            connect_timeout: Duration::from_secs(5),
            default_ttl: Duration::from_secs(3600), // 1 heure
            key_prefix: "veza_chat:".to_string(),
            enabled: true,
        }
    }
}

/// Configuration de sécurité
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityConfig {
    /// Secret pour signer les JWT
    pub jwt_secret: String,
    
    /// Durée de vie des access tokens
    pub jwt_access_duration: Duration,
    
    /// Durée de vie des refresh tokens
    pub jwt_refresh_duration: Duration,
    
    /// Algorithme de signature JWT
    pub jwt_algorithm: String,
    
    /// Audience JWT
    pub jwt_audience: String,
    
    /// Issuer JWT
    pub jwt_issuer: String,
    
    /// Activer l'authentification 2FA
    pub enable_2fa: bool,
    
    /// Durée de validité des codes 2FA
    pub totp_window: u64,
    
    /// Activer le filtrage de contenu
    pub content_filtering: bool,
    
    /// Niveau de sécurité des mots de passe
    pub password_min_length: usize,
    
    /// Rounds de hachage bcrypt
    pub bcrypt_cost: u32,
}

impl Default for SecurityConfig {
    fn default() -> Self {
        Self {
            jwt_secret: "your-super-secret-jwt-key-change-this-in-production".to_string(),
            jwt_access_duration: Duration::from_secs(900), // 15 minutes
            jwt_refresh_duration: Duration::from_secs(604800), // 7 jours
            jwt_algorithm: "HS256".to_string(),
            jwt_audience: "veza-chat".to_string(),
            jwt_issuer: "veza-chat-server".to_string(),
            enable_2fa: false,
            totp_window: 1,
            content_filtering: true,
            password_min_length: 8,
            bcrypt_cost: 12,
        }
    }
}

/// Configuration des limites et quotas
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LimitsConfig {
    /// Taille maximum d'un message en caractères
    pub max_message_length: usize,
    
    /// Nombre maximum de connexions simultanées par utilisateur
    pub max_connections_per_user: u32,
    
    /// Nombre maximum de messages par minute par utilisateur
    pub max_messages_per_minute: u32,
    
    /// Taille maximum d'un fichier uploadé (en bytes)
    pub max_file_size: u64,
    
    /// Nombre maximum de fichiers par utilisateur
    pub max_files_per_user: u32,
    
    /// Nombre maximum de salons par utilisateur
    pub max_rooms_per_user: u32,
    
    /// Nombre maximum de membres par salon
    pub max_members_per_room: u32,
}

impl Default for LimitsConfig {
    fn default() -> Self {
        Self {
            max_message_length: 4000,
            max_connections_per_user: 5,
            max_messages_per_minute: 60,
            max_file_size: 100 * 1024 * 1024, // 100 MB
            max_files_per_user: 1000,
            max_rooms_per_user: 100,
            max_members_per_room: 1000,
        }
    }
}

/// Configuration des fonctionnalités
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeaturesConfig {
    /// Activer les uploads de fichiers
    pub file_uploads: bool,
    
    /// Activer les réactions aux messages
    pub message_reactions: bool,
    
    /// Activer les mentions @utilisateur
    pub user_mentions: bool,
    
    /// Activer les messages épinglés
    pub pinned_messages: bool,
    
    /// Activer les fils de discussion
    pub message_threads: bool,
    
    /// Activer les webhooks sortants
    pub webhooks: bool,
    
    /// Activer les notifications push
    pub push_notifications: bool,
    
    /// Activer l'historique de messages
    pub message_history: bool,
}

impl Default for FeaturesConfig {
    fn default() -> Self {
        Self {
            file_uploads: true,
            message_reactions: true,
            user_mentions: true,
            pinned_messages: true,
            message_threads: true,
            webhooks: false,
            push_notifications: false,
            message_history: true,
        }
    }
}

/// Configuration du logging
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoggingConfig {
    /// Niveau de log global
    pub level: String,
    
    /// Format des logs (json, pretty, compact)
    pub format: LogFormat,
    
    /// Fichier de sortie (None = stdout)
    pub file: Option<PathBuf>,
    
    /// Rotation des logs
    pub rotation: Option<LogRotation>,
    
    /// Filtres par module
    pub filters: Vec<String>,
}

impl Default for LoggingConfig {
    fn default() -> Self {
        Self {
            level: "info".to_string(),
            format: LogFormat::Pretty,
            file: None,
            rotation: None,
            filters: vec![
                "chat_server=debug".to_string(),
                "sqlx=info".to_string(),
                "hyper=info".to_string(),
            ],
        }
    }
}

/// Configuration des intégrations externes
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntegrationsConfig {
    /// Configuration email
    pub email: Option<EmailConfig>,
    
    /// Configuration Prometheus
    pub prometheus: Option<PrometheusConfig>,
    
    /// Configuration des webhooks
    pub webhooks: Vec<WebhookConfig>,
}

impl Default for IntegrationsConfig {
    fn default() -> Self {
        Self {
            email: None,
            prometheus: None,
            webhooks: Vec::new(),
        }
    }
}

/// Configuration email
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmailConfig {
    pub smtp_host: String,
    pub smtp_port: u16,
    pub smtp_username: String,
    pub smtp_password: String,
    pub from_address: String,
    pub from_name: String,
}

/// Configuration Prometheus
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrometheusConfig {
    pub bind_addr: SocketAddr,
    pub path: String,
}

/// Configuration d'un webhook
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebhookConfig {
    pub name: String,
    pub url: Url,
    pub events: Vec<String>,
    pub secret: Option<String>,
}

/// Environnements d'exécution
#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Environment {
    /// Environnement de développement local
    #[clap(name = "dev")]
    Development,
    
    /// Environnement de test/staging
    #[clap(name = "staging")]  
    Staging,
    
    /// Environnement de production
    #[clap(name = "prod")]
    Production,
}

impl fmt::Display for Environment {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Environment::Development => write!(f, "development"),
            Environment::Staging => write!(f, "staging"),
            Environment::Production => write!(f, "production"),
        }
    }
}

impl FromStr for Environment {
    type Err = ChatError;

    fn from_str(s: &str) -> std::result::Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "dev" | "development" => Ok(Environment::Development),
            "staging" | "test" => Ok(Environment::Staging),
            "prod" | "production" => Ok(Environment::Production),
            _ => Err(ChatError::configuration_error(&format!("Invalid environment: {}", s))),
        }
    }
}

/// Formats de logs
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogFormat {
    Json,
    Pretty,
    Compact,
}

/// Configuration de rotation des logs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogRotation {
    pub max_size: u64,      // Taille max en bytes
    pub max_files: usize,   // Nombre max de fichiers
    pub compress: bool,     // Compresser les anciens logs
}

/// Arguments de ligne de commande
#[derive(Parser, Debug)]
#[command(
    name = "chat-server",
    version,
    about = "Serveur de chat WebSocket sécurisé et haute performance",
    long_about = None
)]
struct CliArgs {
    /// Fichier de configuration
    #[arg(short, long, value_name = "FILE")]
    config_file: Option<PathBuf>,
    
    /// Adresse de bind
    #[arg(short, long, value_name = "ADDR")]
    bind_addr: Option<SocketAddr>,
    
    /// Environnement d'exécution
    #[arg(short, long, value_enum)]
    environment: Option<Environment>,
    
    /// Niveau de log
    #[arg(short, long, value_name = "LEVEL")]
    log_level: Option<String>,
    
    /// Mode verbose (augmente le niveau de log)
    #[arg(short, long, action = clap::ArgAction::Count)]
    verbose: u8,
    
    /// Mode silencieux
    #[arg(short, long)]
    quiet: bool,
}

/// Conversions depuis les erreurs de configuration
impl From<config::ConfigError> for ChatError {
    fn from(err: config::ConfigError) -> Self {
        Self::Configuration {
            message: format!("Erreur de configuration: {}", err),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_default_config() {
        let config = ServerConfig::default();
        assert!(config.validate().is_ok());
        assert!(config.is_development());
        assert!(!config.is_production());
    }
    
    #[test]
    fn test_config_validation() {
        let mut config = ServerConfig::default();
        
        // Secret JWT trop court
        config.security.jwt_secret = "short".to_string();
        assert!(config.validate().is_err());
        
        // Limite de message trop élevée
        config.security.jwt_secret = "a".repeat(32);
        config.limits.max_message_length = 20000;
        assert!(config.validate().is_err());
    }
    
    #[test]
    fn test_environment_display() {
        assert_eq!(Environment::Development.to_string(), "development");
        assert_eq!(Environment::Production.to_string(), "production");
    }
} 