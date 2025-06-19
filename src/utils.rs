//! Utilitaires généraux

use chrono::{DateTime, Utc};
use uuid::Uuid;

/// Génère un nouvel UUID v4
pub fn generate_id() -> Uuid {
    Uuid::new_v4()
}

/// Retourne le timestamp UTC actuel
pub fn now() -> DateTime<Utc> {
    Utc::now()
}

/// Valide un nom d'utilisateur
pub fn validate_username(username: &str) -> bool {
    !username.is_empty() 
        && username.len() >= 3 
        && username.len() <= 32 
        && username.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '-')
}

/// Valide une adresse email basique
pub fn validate_email(email: &str) -> bool {
    email.contains('@') && email.len() >= 5 && email.len() <= 255
}

/// Nettoie et normalise le contenu d'un message
pub fn sanitize_message_content(content: &str) -> String {
    content.trim().to_string()
}

/// Tronque un texte à une longueur donnée
pub fn truncate_text(text: &str, max_len: usize) -> String {
    if text.len() <= max_len {
        text.to_string()
    } else {
        format!("{}...", &text[..max_len.saturating_sub(3)])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_username() {
        assert!(validate_username("test_user"));
        assert!(validate_username("user-123"));
        assert!(!validate_username(""));
        assert!(!validate_username("us"));
        assert!(!validate_username("user@domain"));
    }

    #[test]
    fn test_validate_email() {
        assert!(validate_email("test@example.com"));
        assert!(!validate_email("invalid"));
        assert!(!validate_email(""));
    }

    #[test]
    fn test_truncate_text() {
        assert_eq!(truncate_text("hello", 10), "hello");
        assert_eq!(truncate_text("hello world test", 10), "hello w...");
    }
} 