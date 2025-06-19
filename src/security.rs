use crate::error::{ChatError, Result};
use regex::Regex;
use std::collections::HashSet;

/// Mots-clés interdits (profanité, spam, etc.)
static FORBIDDEN_WORDS: &[&str] = &[
    "spam", "scam", "phishing", 
    // Ajoutez vos mots interdits ici
];

/// Patterns dangereux (injection, XSS, etc.)
static DANGEROUS_PATTERNS: &[&str] = &[
    r"<script[^>]*>.*?</script>",
    r"javascript:",
    r"vbscript:",
    r"on\w+\s*=",
    r"eval\s*\(",
    r"document\.",
    r"window\.",
];

pub struct ContentFilter {
    forbidden_words: HashSet<String>,
    dangerous_patterns: Vec<Regex>,
}

impl ContentFilter {
    pub fn new() -> Result<Self> {
        let forbidden_words = FORBIDDEN_WORDS
            .iter()
            .map(|&word| word.to_lowercase())
            .collect();

        let mut dangerous_patterns = Vec::new();
        for pattern in DANGEROUS_PATTERNS {
            dangerous_patterns.push(
                Regex::new(pattern)
                    .map_err(|e| ChatError::configuration_error(&format!("Regex invalide: {}", e)))?
            );
        }

        Ok(Self {
            forbidden_words,
            dangerous_patterns,
        })
    }

    /// Nettoie et valide le contenu d'un message
    pub fn sanitize_content(&self, content: &str) -> Result<String> {
        let content = content.trim();
        
        // Vérification de la longueur
        if content.is_empty() {
            return Err(ChatError::configuration_error("Message vide"));
        }

        if content.len() > 2000 {
            return Err(ChatError::message_too_long(content.len(), 2000));
        }

        // Détection de contenu malveillant
        for pattern in &self.dangerous_patterns {
            if pattern.is_match(content) {
                tracing::warn!(pattern = %pattern.as_str(), content = %content, "🚫 Contenu dangereux détecté");
                return Err(ChatError::configuration_error("Contenu potentiellement malveillant détecté"));
            }
        }

        // Vérification des mots interdits
        let words_lower = content.to_lowercase();
        for forbidden in &self.forbidden_words {
            if words_lower.contains(forbidden) {
                tracing::warn!(forbidden_word = %forbidden, content = %content, "🚫 Mot interdit détecté");
                return Err(ChatError::configuration_error("Contenu inapproprié détecté"));
            }
        }

        // Nettoyage des caractères dangereux
        let cleaned = content
            .chars()
            .filter(|&c| {
                // Garder uniquement les caractères sûrs
                c.is_alphanumeric() 
                || c.is_whitespace() 
                || ".,!?;:()[]{}\"'-_@#&*+=~/\\|".contains(c)
            })
            .collect::<String>();

        // Suppression des espaces multiples
        let cleaned = Regex::new(r"\s+")
            .unwrap()
            .replace_all(&cleaned, " ")
            .trim()
            .to_string();

        Ok(cleaned)
    }

    /// Valide un nom de salon
    pub fn validate_room_name(&self, room_name: &str) -> Result<String> {
        let name = room_name.trim().to_lowercase();
        
        if name.is_empty() {
            return Err(ChatError::configuration_error("Nom de salon vide"));
        }

        if name.len() > 50 {
            return Err(ChatError::configuration_error("Nom de salon trop long (max 50 caractères)"));
        }

        // Vérifier que le nom ne contient que des caractères alphanumériques, tirets et underscores
        if !name.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_') {
            return Err(ChatError::configuration_error("Nom de salon invalide (alphanumériques, tirets et underscores uniquement)"));
        }

        // Vérifier les mots interdits
        for forbidden in &self.forbidden_words {
            if name.contains(forbidden) {
                return Err(ChatError::configuration_error("Nom de salon inapproprié"));
            }
        }

        Ok(name)
    }
}

impl Default for ContentFilter {
    fn default() -> Self {
        Self::new().expect("Impossible de créer le filtre de contenu")
    }
}

/// Génère un hash sécurisé pour l'audit
pub fn generate_audit_hash(user_id: i32, action: &str, timestamp: i64) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    
    let mut hasher = DefaultHasher::new();
    user_id.hash(&mut hasher);
    action.hash(&mut hasher);
    timestamp.hash(&mut hasher);
    
    format!("{:x}", hasher.finish())
}

/// Vérifie si une adresse IP est dans une liste noire
pub fn is_ip_blacklisted(ip: &str) -> bool {
    // Implémentation simple - en production, utilisez une vraie liste noire
    let blacklisted_ranges = [
        "127.0.0.1", // Exemple
    ];
    
    blacklisted_ranges.contains(&ip)
}

/// Rate limiting avancé par type d'action
#[derive(Debug, Clone)]
pub struct ActionLimits {
    pub messages_per_minute: u32,
    pub room_joins_per_hour: u32,
    pub dm_per_minute: u32,
}

impl Default for ActionLimits {
    fn default() -> Self {
        Self {
            messages_per_minute: 30,
            room_joins_per_hour: 10,
            dm_per_minute: 10,
        }
    }
} 