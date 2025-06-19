//! # Gestion d'erreurs unifiée pour Veza Chat Server
//! 
//! Ce module fournit un système d'erreurs cohérent et complet avec:
//! - Catégorisation des erreurs par domaine
//! - Codes d'erreur standardisés  
//! - Logging automatique selon la gravité
//! - Sérialisation pour l'API

use serde::{Deserialize, Serialize};
use std::fmt;
use thiserror::Error;

/// Type alias pour Result avec notre erreur personnalisée
pub type Result<T> = std::result::Result<T, ChatError>;

/// Erreurs principales du système de chat
#[derive(Error, Debug)]
pub enum ChatError {
    // ═══════════════════════════════════════════════════════════════════════
    // ERREURS D'AUTHENTIFICATION ET AUTORISATION
    // ═══════════════════════════════════════════════════════════════════════
    
    /// Token JWT invalide ou expiré
    #[error("Token d'authentification invalide: {reason}")]
    InvalidToken { reason: String },
    
    /// Utilisateur non autorisé pour cette action
    #[error("Accès refusé: {action}")]
    Unauthorized { action: String },
    
    /// Utilisateur banni ou suspendu
    #[error("Compte suspendu: {reason}")]
    AccountSuspended { reason: String },
    
    /// Tentative de connexion avec des identifiants invalides
    #[error("Identifiants invalides")]
    InvalidCredentials,
    
    /// Authentification à deux facteurs requise
    #[error("Authentification 2FA requise")]
    TwoFactorRequired,
    
    /// Code 2FA invalide
    #[error("Code d'authentification 2FA invalide")]
    InvalidTwoFactorCode,
    
    // ═══════════════════════════════════════════════════════════════════════
    // ERREURS DE VALIDATION ET CONTENU
    // ═══════════════════════════════════════════════════════════════════════
    
    /// Contenu de message trop long
    #[error("Message trop long: {actual} caractères (max: {max})")]
    MessageTooLong { actual: usize, max: usize },
    
    /// Contenu inapproprié détecté
    #[error("Contenu inapproprié détecté: {reason}")]
    InappropriateContent { reason: String },
    
    /// Spam détecté par les filtres
    #[error("Contenu identifié comme spam")]
    SpamDetected,
    
    /// Format de données invalide
    #[error("Format invalide pour {field}: {reason}")]
    InvalidFormat { field: String, reason: String },
    
    /// Paramètre requis manquant
    #[error("Paramètre requis manquant: {param}")]
    MissingParameter { param: String },
    
    /// Valeur hors limites acceptables
    #[error("{field} hors limites: {value} (min: {min}, max: {max})")]
    OutOfRange { field: String, value: i64, min: i64, max: i64 },
    
    // ═══════════════════════════════════════════════════════════════════════
    // ERREURS DE RATE LIMITING ET QUOTA
    // ═══════════════════════════════════════════════════════════════════════
    
    /// Limite de taux dépassée
    #[error("Limite de taux dépassée pour {action}: {current}/{limit} dans {window}s")]
    RateLimitExceeded { 
        action: String, 
        current: u32, 
        limit: u32, 
        window: u64 
    },
    
    /// Quota utilisateur dépassé
    #[error("Quota {quota_type} dépassé: {used}/{limit}")]
    QuotaExceeded { quota_type: String, used: u64, limit: u64 },
    
    /// Trop de connexions simultanées
    #[error("Trop de connexions simultanées: {current}/{max}")]
    TooManyConnections { current: u32, max: u32 },
    
    // ═══════════════════════════════════════════════════════════════════════
    // ERREURS RÉSEAU ET WEBSOCKET
    // ═══════════════════════════════════════════════════════════════════════
    
    /// Erreur de connexion WebSocket
    #[error("Erreur WebSocket: {source}")]
    WebSocket { 
        #[source]
        source: tokio_tungstenite::tungstenite::Error 
    },
    
    /// Connexion fermée de manière inattendue
    #[error("Connexion fermée: {reason}")]
    ConnectionClosed { reason: String },
    
    /// Timeout de connexion
    #[error("Timeout de connexion après {seconds}s")]
    ConnectionTimeout { seconds: u64 },
    
    /// Erreur réseau générale
    #[error("Erreur réseau: {message}")]
    NetworkError { message: String },
    
    // ═══════════════════════════════════════════════════════════════════════
    // ERREURS DE BASE DE DONNÉES
    // ═══════════════════════════════════════════════════════════════════════
    
    /// Erreur de base de données
    #[error("Erreur base de données: {operation}")]
    Database { 
        operation: String,
        #[source]
        source: sqlx::Error 
    },
    
    /// Ressource non trouvée
    #[error("{resource} non trouvé(e): {id}")]
    NotFound { resource: String, id: String },
    
    /// Conflit de données (ex: violation de contrainte unique)
    #[error("Conflit de données: {reason}")]
    Conflict { reason: String },
    
    /// Transaction échouée
    #[error("Transaction échouée: {reason}")]
    TransactionFailed { reason: String },
    
    // ═══════════════════════════════════════════════════════════════════════
    // ERREURS DE CONVERSATIONS ET MESSAGES
    // ═══════════════════════════════════════════════════════════════════════
    
    /// Conversation inexistante
    #[error("Conversation {id} inexistante")]
    ConversationNotFound { id: String },
    
    /// Utilisateur pas membre de la conversation
    #[error("Utilisateur non membre de la conversation {conversation_id}")]
    NotMember { conversation_id: String },
    
    /// Permissions insuffisantes dans la conversation
    #[error("Permissions insuffisantes pour {action} dans {conversation_id}")]
    InsufficientPermissions { action: String, conversation_id: String },
    
    /// Conversation archivée
    #[error("Conversation {id} archivée")]
    ConversationArchived { id: String },
    
    /// Message non trouvé
    #[error("Message {id} non trouvé")]
    MessageNotFound { id: String },
    
    /// Impossible d'éditer le message
    #[error("Edition impossible: {reason}")]
    EditForbidden { reason: String },
    
    // ═══════════════════════════════════════════════════════════════════════
    // ERREURS DE FICHIERS ET UPLOAD
    // ═══════════════════════════════════════════════════════════════════════
    
    /// Fichier trop volumineux
    #[error("Fichier trop volumineux: {size} bytes (max: {max_size})")]
    FileTooLarge { size: u64, max_size: u64 },
    
    /// Type de fichier non autorisé
    #[error("Type de fichier non autorisé: {mime_type}")]
    UnsupportedFileType { mime_type: String },
    
    /// Fichier infecté détecté
    #[error("Fichier potentiellement dangereux détecté")]
    MaliciousFile,
    
    /// Erreur d'upload
    #[error("Erreur upload: {reason}")]
    UploadError { reason: String },
    
    // ═══════════════════════════════════════════════════════════════════════
    // ERREURS SYSTÈME ET CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════
    
    /// Erreur de configuration
    #[error("Erreur configuration: {message}")]
    Configuration { message: String },
    
    /// Service indisponible
    #[error("Service {service} indisponible: {reason}")]
    ServiceUnavailable { service: String, reason: String },
    
    /// Erreur de cache
    #[error("Erreur cache: {operation}")]
    Cache { operation: String },
    
    /// Timeout d'arrêt du serveur
    #[error("Timeout lors de l'arrêt du serveur")]
    ShutdownTimeout,
    
    /// Erreur interne non spécifiée
    #[error("Erreur interne: {message}")]
    Internal { message: String },
    
    // ═══════════════════════════════════════════════════════════════════════
    // ERREURS DE SÉCURITÉ
    // ═══════════════════════════════════════════════════════════════════════
    
    /// Activité suspecte détectée
    #[error("Activité suspecte détectée: {reason}")]
    SuspiciousActivity { reason: String },
    
    /// IP bloquée
    #[error("Adresse IP {ip} bloquée: {reason}")]
    IpBlocked { ip: String, reason: String },
    
    /// Tentative d'injection détectée
    #[error("Tentative d'injection détectée")]
    InjectionAttempt,
    
    /// Validation de sécurité échouée
    #[error("Validation sécurité échouée: {check}")]
    SecurityValidationFailed { check: String },
    
    /// Erreur de sérialisation JSON
    #[error("Erreur JSON: {source}")]
    Json {
        #[source]
        source: serde_json::Error,
    },
    
    /// Erreur de sérialisation générale
    #[error("Erreur de sérialisation {operation}: {message}")]
    Serialization {
        operation: String,
        message: String,
    },
    
    /// Fonctionnalité non disponible
    #[error("Fonctionnalité {feature} non disponible: {reason}")]
    FeatureNotAvailable {
        feature: String,
        reason: String,
    },
    
    /// Limite de connexions atteinte
    #[error("Limite de connexions simultanées atteinte")]
    ConnectionLimitReached,
}

impl ChatError {
    /// Retourne le code d'erreur HTTP approprié
    pub fn http_status(&self) -> u16 {
        match self {
            // 400 Bad Request
            Self::InvalidFormat { .. } 
            | Self::MissingParameter { .. }
            | Self::OutOfRange { .. }
            | Self::MessageTooLong { .. }
            | Self::FileTooLarge { .. }
            | Self::UnsupportedFileType { .. } => 400,
            
            // 401 Unauthorized  
            Self::InvalidToken { .. }
            | Self::InvalidCredentials
            | Self::TwoFactorRequired
            | Self::InvalidTwoFactorCode => 401,
            
            // 403 Forbidden
            Self::Unauthorized { .. }
            | Self::AccountSuspended { .. }
            | Self::InsufficientPermissions { .. }
            | Self::EditForbidden { .. }
            | Self::IpBlocked { .. } => 403,
            
            // 404 Not Found
            Self::NotFound { .. }
            | Self::ConversationNotFound { .. }
            | Self::MessageNotFound { .. } => 404,
            
            // 409 Conflict
            Self::Conflict { .. } => 409,
            
            // 413 Payload Too Large
            Self::MessageTooLong { .. } => 413,
            
            // 422 Unprocessable Entity
            Self::InappropriateContent { .. }
            | Self::SpamDetected
            | Self::MaliciousFile => 422,
            
            // 429 Too Many Requests
            Self::RateLimitExceeded { .. }
            | Self::QuotaExceeded { .. }
            | Self::TooManyConnections { .. } => 429,
            
            // 500 Internal Server Error
            Self::Database { .. }
            | Self::Internal { .. }
            | Self::Configuration { .. }
            | Self::TransactionFailed { .. }
            | Self::UploadError { .. }
            | Self::Cache { .. } => 500,
            
            // 503 Service Unavailable
            Self::ServiceUnavailable { .. }
            | Self::ShutdownTimeout => 503,
            
            // 418 I'm a teapot (pour les tentatives d'injection)
            Self::InjectionAttempt => 418,
            
            // Autres erreurs -> 500
            Self::Json { .. }
            | Self::Serialization { .. }
            | Self::FeatureNotAvailable { .. }
            | Self::ConnectionLimitReached
            | Self::SecurityValidationFailed { .. }
            | Self::SuspiciousActivity { .. }
            | Self::ConversationArchived { .. }
            | Self::NetworkError { .. }
            | Self::ConnectionClosed { .. }
            | Self::ConnectionTimeout { .. }
            | Self::WebSocket { .. }
            | Self::NotMember { .. } => 500,
        }
    }
    
    /// Retourne la sévérité de l'erreur pour les logs
    pub fn severity(&self) -> ErrorSeverity {
        match self {
            // CRITICAL - Erreur système critique  
            Self::Database { .. }
            | Self::ServiceUnavailable { .. }
            | Self::ShutdownTimeout
            | Self::SuspiciousActivity { .. }
            | Self::InjectionAttempt
            | Self::IpBlocked { .. } => ErrorSeverity::High,
            
            // HIGH - Problème sérieux à traiter rapidement
            Self::InvalidToken { .. }
            | Self::AccountSuspended { .. }
            | Self::InvalidFormat { .. }
            | Self::MissingParameter { .. }
            | Self::OutOfRange { .. }
            | Self::MessageTooLong { .. }
            | Self::FileTooLarge { .. }
            | Self::UnsupportedFileType { .. }
            | Self::TransactionFailed { .. }
            | Self::UploadError { .. }
            | Self::InvalidCredentials
            | Self::InvalidTwoFactorCode
            | Self::InappropriateContent { .. }
            | Self::SpamDetected
            | Self::MaliciousFile
            | Self::ConversationNotFound { .. }
            | Self::InsufficientPermissions { .. }
            | Self::MessageNotFound { .. }
            | Self::EditForbidden { .. }
            | Self::Conflict { .. }
            | Self::ConnectionLimitReached
            | Self::SecurityValidationFailed { .. } => ErrorSeverity::Medium,
            
            // Gravité moyenne - Erreurs qui affectent l'utilisateur
            Self::RateLimitExceeded { .. }
            | Self::QuotaExceeded { .. }
            | Self::TooManyConnections { .. }
            | Self::Unauthorized { .. }
            | Self::NotFound { .. } => ErrorSeverity::Low,
            
            // INFO - Information
            Self::ConnectionClosed { .. }
            | Self::TwoFactorRequired
            | Self::NotMember { .. }
            | Self::Json { .. }
            | Self::Serialization { .. }
            | Self::FeatureNotAvailable { .. }
            | Self::ConversationArchived { .. }
            | Self::WebSocket { .. }
            | Self::NetworkError { .. }
            | Self::ConnectionTimeout { .. }
            | Self::Cache { .. }
            | Self::Internal { .. }
            | Self::Configuration { .. } => ErrorSeverity::Info,
        }
    }
    
    /// Retourne un message d'erreur sécurisé pour le client
    pub fn public_message(&self) -> String {
        match self {
            // Messages détaillés OK pour le client
            Self::InvalidFormat { field, .. } => format!("Format invalide pour {}", field),
            Self::MissingParameter { param } => format!("Paramètre manquant: {}", param),
            Self::MessageTooLong { max, .. } => format!("Message trop long (max: {} caractères)", max),
            Self::RateLimitExceeded { action, window, .. } => {
                format!("Trop de requêtes pour {}, veuillez patienter {}s", action, window)
            },
            
            // Messages génériques pour éviter la divulgation d'informations
            Self::Database { .. } => "Erreur temporaire, veuillez réessayer".to_string(),
            Self::Internal { .. } => "Erreur interne du serveur".to_string(),
            Self::Configuration { .. } => "Service temporairement indisponible".to_string(),
            Self::InjectionAttempt => "Requête rejetée".to_string(),
            Self::SuspiciousActivity { .. } => "Activité inhabituelle détectée".to_string(),
            
            // Message par défaut
            _ => self.to_string(),
        }
    }
    
    /// Crée une erreur de base de données avec contexte
    pub fn database_error(operation: &str, source: sqlx::Error) -> Self {
        Self::Database {
            operation: operation.to_string(),
            source,
        }
    }
    
    /// Crée une erreur d'autorisation avec contexte
    pub fn unauthorized(action: &str) -> Self {
        Self::Unauthorized {
            action: action.to_string(),
        }
    }
    
    /// Crée une erreur de ressource non trouvée
    pub fn not_found(resource: &str, id: &str) -> Self {
        Self::NotFound {
            resource: resource.to_string(),
            id: id.to_string(),
        }
    }

    /// Helper pour les erreurs de configuration
    pub fn configuration_error(message: &str) -> Self {
        Self::Configuration {
            message: message.to_string(),
        }
    }

    /// Helper pour les erreurs de message trop long
    pub fn message_too_long(actual: usize, max: usize) -> Self {
        Self::MessageTooLong { actual, max }
    }

    /// Helper pour les erreurs de sérialisation
    pub fn serialization_error(type_name: &str, _data: &str, source: serde_json::Error) -> Self {
        Self::Serialization {
            operation: format!("serialize {}", type_name),
            message: source.to_string(),
        }
    }

    /// Helper pour les erreurs WebSocket
    pub fn websocket_error(_operation: &str, source: tokio_tungstenite::tungstenite::Error) -> Self {
        Self::WebSocket {
            source,
        }
    }

    /// Helper pour les fonctionnalités non disponibles
    pub fn feature_not_available(feature: &str, reason: &str) -> Self {
        Self::FeatureNotAvailable {
            feature: feature.to_string(),
            reason: reason.to_string(),
        }
    }

    /// Helper pour convertir sqlx::Error avec une meilleure gestion
    pub fn from_sqlx_error(operation: &str, error: sqlx::Error) -> Self {
        Self::Database {
            operation: operation.to_string(),
            source: error,
        }
    }
    
    /// Helper pour les erreurs JSON
    pub fn from_json_error(error: serde_json::Error) -> Self {
        Self::Json { source: error }
    }
    
    /// Helper pour les erreurs de rate limiting avec des valeurs par défaut
    pub fn rate_limit_exceeded_simple(action: &str) -> Self {
        Self::RateLimitExceeded {
            action: action.to_string(),
            current: 0,
            limit: 0,
            window: 60,
        }
    }
    
    /// Helper pour les erreurs d'autorisation
    pub fn unauthorized_simple(action: &str) -> Self {
        Self::Unauthorized {
            action: action.to_string(),
        }
    }
    
    /// Helper pour les erreurs de contenu inapproprié
    pub fn inappropriate_content_simple(reason: &str) -> Self {
        Self::InappropriateContent {
            reason: reason.to_string(),
        }
    }
}

/// Niveaux de sévérité des erreurs
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ErrorSeverity {
    Info,
    Low,
    Medium,
    High,
    Critical,
}

impl fmt::Display for ErrorSeverity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Info => write!(f, "INFO"),
            Self::Low => write!(f, "LOW"),
            Self::Medium => write!(f, "MEDIUM"),
            Self::High => write!(f, "HIGH"),
            Self::Critical => write!(f, "CRITICAL"),
        }
    }
}

/// Implémentations de conversion depuis des erreurs externes
impl From<sqlx::Error> for ChatError {
    fn from(err: sqlx::Error) -> Self {
        Self::database_error("query", err)
    }
}

impl From<tokio_tungstenite::tungstenite::Error> for ChatError {
    fn from(err: tokio_tungstenite::tungstenite::Error) -> Self {
        Self::WebSocket { source: err }
    }
}

impl From<serde_json::Error> for ChatError {
    fn from(err: serde_json::Error) -> Self {
        Self::InvalidFormat {
            field: "json".to_string(),
            reason: err.to_string(),
        }
    }
}

impl From<std::env::VarError> for ChatError {
    fn from(err: std::env::VarError) -> Self {
        Self::Configuration {
            message: format!("Variable d'environnement manquante: {}", err),
        }
    }
}

/// Macro pour simplifier la création d'erreurs
#[macro_export]
macro_rules! chat_error {
    ($variant:ident, $($field:ident = $value:expr),*) => {
        ChatError::$variant {
            $($field: $value.into()),*
        }
    };
    ($variant:ident) => {
        ChatError::$variant
    };
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_error_http_status() {
        assert_eq!(ChatError::InvalidCredentials.http_status(), 401);
        assert_eq!(ChatError::not_found("user", "123").http_status(), 404);
        assert_eq!(ChatError::unauthorized("send_message").http_status(), 403);
    }
    
    #[test]
    fn test_error_severity() {
        assert_eq!(ChatError::InjectionAttempt.severity(), ErrorSeverity::High);
        assert_eq!(ChatError::InvalidCredentials.severity(), ErrorSeverity::Low);
        assert_eq!(ChatError::SpamDetected.severity(), ErrorSeverity::Medium);
    }
    
    #[test]
    fn test_public_message() {
        let error = ChatError::InvalidFormat {
            field: "email".to_string(),
            reason: "invalid format".to_string(),
        };
        assert_eq!(error.public_message(), "Format invalide pour email");
        
        let db_error = ChatError::database_error("insert", sqlx::Error::RowNotFound);
        assert_eq!(db_error.public_message(), "Erreur temporaire, veuillez réessayer");
    }
    
    #[test]
    fn test_error_creation_helpers() {
        let error = ChatError::not_found("conversation", "room_123");
        match error {
            ChatError::NotFound { resource, id } => {
                assert_eq!(resource, "conversation");
                assert_eq!(id, "room_123");
            }
            _ => panic!("Wrong error type"),
        }
    }
    
    #[test]
    fn test_macro() {
        let error = chat_error!(MessageTooLong, actual = 5000, max = 4000);
        match error {
            ChatError::MessageTooLong { actual, max } => {
                assert_eq!(actual, 5000);
                assert_eq!(max, 4000);
            }
            _ => panic!("Wrong error type"),
        }
    }
} 