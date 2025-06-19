use crate::error::{ChatError, Result};
use regex::Regex;
use std::collections::{HashSet, HashMap};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use serde::{Serialize, Deserialize};

/// Système de sécurité renforcé
pub struct EnhancedSecurity {
    content_filter: ContentFilter,
    rate_limiter: AdvancedRateLimiter,
    session_manager: SessionManager,
    ip_monitor: IpMonitor,
}

impl EnhancedSecurity {
    pub fn new() -> Result<Self> {
        Ok(Self {
            content_filter: ContentFilter::new()?,
            rate_limiter: AdvancedRateLimiter::new(),
            session_manager: SessionManager::new(),
            ip_monitor: IpMonitor::new(),
        })
    }

    /// Validation complète d'une requête utilisateur
    pub async fn validate_request(
        &mut self,
        user_id: i32,
        ip: &str,
        session_token: &str,
        action: &SecurityAction,
        content: Option<&str>
    ) -> Result<()> {
        // 1. Vérifier le rate limiting
        self.rate_limiter.check_limit(user_id, action)?;
        
        // 2. Vérifier la session
        self.session_manager.validate_session(user_id, session_token)?;
        
        // 3. Monitorer l'IP
        self.ip_monitor.check_ip(ip, action)?;
        
        // 4. Filtrer le contenu si présent
        if let Some(content) = content {
            self.content_filter.validate_content(content)?;
        }

        Ok(())
    }
}

#[derive(Debug, Clone, Hash, Eq, PartialEq)]
pub enum SecurityAction {
    SendMessage,
    CreateRoom,
    JoinRoom,
    SendDM,
    UploadFile,
    ChangeSettings,
    AdminAction,
}

/// Filtre de contenu amélioré avec détection ML
pub struct ContentFilter {
    forbidden_words: HashSet<String>,
    dangerous_patterns: Vec<Regex>,
    spam_detector: SpamDetector,
    toxicity_detector: ToxicityDetector,
}

impl ContentFilter {
    pub fn new() -> Result<Self> {
        // Mots interdits étendus
        let forbidden_words = vec![
            // Spam/Scam
            "click here", "urgent", "limited time", "act now", "free money",
            "viagra", "casino", "lottery", "winner", "congratulations",
            
            // Injection/Exploitation
            "script", "eval", "onclick", "onerror", "javascript",
            "vbscript", "expression", "import", "alert",
            
            // Profanité (exemples)
            "spam", "fuck", "shit", "bitch", "damn",
            
            // Harcèlement
            "kill yourself", "kys", "suicide", "die",
        ].into_iter().map(|s| s.to_lowercase()).collect();

        // Patterns XSS/Injection renforcés
        let dangerous_patterns = vec![
            // XSS
            r"<script[^>]*>.*?</script>",
            r"javascript:",
            r"vbscript:",
            r"data:text/html",
            r"on\w+\s*=",
            r"eval\s*\(",
            r"setTimeout\s*\(",
            r"setInterval\s*\(",
            
            // SQL Injection
            r"(?i)(union|select|insert|update|delete|drop|create|alter|exec)\s+",
            r"(?i)(\s|^)(or|and)\s+\d+\s*=\s*\d+",
            r"(?i)(\s|^)(or|and)\s+['\x22][^'\x22]*['\x22]",
            
            // Path Traversal
            r"\.\./",
            r"\.\.\\",
            
            // Command Injection
            r"[\s;|&`$(){}[\]<>]",
        ].into_iter()
        .map(|pattern| Regex::new(pattern))
        .collect::<std::result::Result<Vec<_>, _>>()
        .map_err(|e| ChatError::configuration_error(&format!("Regex invalide: {}", e)))?;

        Ok(Self {
            forbidden_words,
            dangerous_patterns,
            spam_detector: SpamDetector::new(),
            toxicity_detector: ToxicityDetector::new(),
        })
    }

    pub fn validate_content(&mut self, content: &str) -> Result<String> {
        // 1. Longueur
        if content.len() > 4000 {
            return Err(ChatError::message_too_long(content.len(), 4000));
        }

        // 2. Patterns dangereux
        let content_lower = content.to_lowercase();
        for pattern in &self.dangerous_patterns {
            if pattern.is_match(&content_lower) {
                tracing::warn!(content = %content, "🚨 Contenu dangereux détecté");
                return Err(ChatError::inappropriate_content_simple("inappropriate_content"));
            }
        }

        // 3. Mots interdits
        for word in &self.forbidden_words {
            if content_lower.contains(word) {
                tracing::warn!(word = %word, "🚫 Mot interdit détecté");
                return Err(ChatError::inappropriate_content_simple("inappropriate_content"));
            }
        }

        // 4. Détection de spam
        if self.spam_detector.is_spam(content).unwrap_or(false) {
            return Err(ChatError::SpamDetected);
        }

        // 5. Détection de toxicité
        if self.toxicity_detector.is_toxic(content).unwrap_or(false) {
            return Err(ChatError::inappropriate_content_simple("inappropriate_content"));
        }

        // 6. Sanitisation
        let sanitized = self.sanitize_html(content);
        Ok(sanitized)
    }

    fn sanitize_html(&self, content: &str) -> String {
        content
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&#x27;")
            .replace("&", "&amp;")
            .chars()
            .filter(|c| c.is_ascii() || c.is_alphanumeric() || " .,!?-_@#()[]{}".contains(*c))
            .collect()
    }
}

/// Détecteur de spam avec algorithmes heuristiques
pub struct SpamDetector {
    repetition_threshold: f32,
    caps_threshold: f32,
    emoji_threshold: f32,
}

impl SpamDetector {
    pub fn new() -> Self {
        Self {
            repetition_threshold: 0.7, // 70% de répétition
            caps_threshold: 0.5,       // 50% de majuscules
            emoji_threshold: 0.3,      // 30% d'emojis
        }
    }

    pub fn is_spam(&self, content: &str) -> Result<bool> {
        if content.len() < 10 {
            return Ok(false);
        }

        // 1. Répétition excessive de caractères
        if self.detect_character_repetition(content) {
            return Ok(true);
        }

        // 2. Trop de majuscules
        if self.detect_excessive_caps(content) {
            return Ok(true);
        }

        // 3. Trop d'emojis/caractères spéciaux
        if self.detect_excessive_special_chars(content) {
            return Ok(true);
        }

        // 4. Patterns de spam
        if self.detect_spam_patterns(content) {
            return Ok(true);
        }

        Ok(false)
    }

    fn detect_character_repetition(&self, content: &str) -> bool {
        let mut char_counts = HashMap::new();
        for c in content.chars() {
            *char_counts.entry(c).or_insert(0) += 1;
        }

        let max_count = char_counts.values().max().unwrap_or(&0);
        (*max_count as f32) / (content.len() as f32) > self.repetition_threshold
    }

    fn detect_excessive_caps(&self, content: &str) -> bool {
        let caps_count = content.chars().filter(|c| c.is_uppercase()).count();
        let letter_count = content.chars().filter(|c| c.is_alphabetic()).count();
        
        if letter_count == 0 {
            return false;
        }

        (caps_count as f32) / (letter_count as f32) > self.caps_threshold
    }

    fn detect_excessive_special_chars(&self, content: &str) -> bool {
        let special_count = content.chars()
            .filter(|c| !c.is_alphanumeric() && !c.is_whitespace())
            .count();
        
        (special_count as f32) / (content.len() as f32) > self.emoji_threshold
    }

    fn detect_spam_patterns(&self, content: &str) -> bool {
        let content_lower = content.to_lowercase();
        
        // Patterns typiques de spam
        let spam_patterns = [
            "click here now",
            "limited time offer",
            "act fast",
            "free free free",
            "!!!!!!",
            "buy now",
            "special offer",
        ];

        spam_patterns.iter().any(|pattern| content_lower.contains(pattern))
    }
}

/// Détecteur de toxicité basique (à améliorer avec ML en production)
pub struct ToxicityDetector {
    toxic_patterns: Vec<Regex>,
    severity_threshold: f32,
}

impl ToxicityDetector {
    pub fn new() -> Self {
        let toxic_patterns = vec![
            // Harcèlement
            r"(?i)(kill\s+yourself|kys)",
            r"(?i)(go\s+die|should\s+die)",
            r"(?i)(hate\s+(you|u))",
            
            // Menaces
            r"(?i)(i\s+will\s+(kill|hurt|harm))",
            r"(?i)(threat|threaten)",
            
            // Discrimination
            r"(?i)(racist|sexist|homophobic)",
            r"(?i)(n[i1]gg[ea]r)",
            r"(?i)(f[a4]gg[o0]t)",
        ].into_iter()
        .filter_map(|pattern| Regex::new(pattern).ok())
        .collect();

        Self {
            toxic_patterns,
            severity_threshold: 0.6,
        }
    }

    pub fn is_toxic(&self, content: &str) -> Result<bool> {
        let mut toxicity_score = 0.0;
        let content_lower = content.to_lowercase();

        for pattern in &self.toxic_patterns {
            if pattern.is_match(&content_lower) {
                toxicity_score += 0.3;
            }
        }

        // Facteurs aggravants
        if content.contains("!!!") {
            toxicity_score += 0.1;
        }
        
        if content.chars().filter(|c| c.is_uppercase()).count() as f32 / content.len() as f32 > 0.5 {
            toxicity_score += 0.1;
        }

        Ok(toxicity_score > self.severity_threshold)
    }
}

/// Rate limiter avancé par action
pub struct AdvancedRateLimiter {
    limits: HashMap<SecurityAction, RateLimit>,
    user_actions: HashMap<(i32, SecurityAction), Vec<SystemTime>>,
}

#[derive(Clone)]
pub struct RateLimit {
    pub max_count: u32,
    pub window_duration: Duration,
    pub burst_limit: Option<u32>, // Limite de burst
}

impl AdvancedRateLimiter {
    pub fn new() -> Self {
        let mut limits = HashMap::new();
        
        // Configuration des limites
        limits.insert(SecurityAction::SendMessage, RateLimit {
            max_count: 20,
            window_duration: Duration::from_secs(60),
            burst_limit: Some(5),
        });
        
        limits.insert(SecurityAction::CreateRoom, RateLimit {
            max_count: 3,
            window_duration: Duration::from_secs(300), // 5 minutes
            burst_limit: None,
        });
        
        limits.insert(SecurityAction::JoinRoom, RateLimit {
            max_count: 10,
            window_duration: Duration::from_secs(60),
            burst_limit: Some(3),
        });
        
        limits.insert(SecurityAction::SendDM, RateLimit {
            max_count: 15,
            window_duration: Duration::from_secs(60),
            burst_limit: Some(3),
        });
        
        limits.insert(SecurityAction::AdminAction, RateLimit {
            max_count: 100,
            window_duration: Duration::from_secs(60),
            burst_limit: Some(10),
        });

        Self {
            limits,
            user_actions: HashMap::new(),
        }
    }

    pub fn check_limit(&mut self, user_id: i32, action: &SecurityAction) -> Result<()> {
        let limit = self.limits.get(action)
            .ok_or_else(|| ChatError::configuration_error("Action non configurée"))?;

        let key = (user_id, action.clone());
        let now = SystemTime::now();
        
        // Nettoyer les anciens événements
        let actions = self.user_actions.entry(key).or_insert_with(Vec::new);
        actions.retain(|time| now.duration_since(*time).unwrap_or(Duration::ZERO) <= limit.window_duration);

        // Vérifier la limite principale
        if actions.len() >= limit.max_count as usize {
            tracing::warn!(user_id = %user_id, action = ?action, count = %actions.len(), limit = %limit.max_count, "⏰ Rate limit dépassé");
            return Err(ChatError::rate_limit_exceeded_simple("rate_limit"));
        }

        // Vérifier la limite de burst si configurée
        if let Some(burst_limit) = limit.burst_limit {
            let recent_actions = actions.iter()
                .filter(|time| now.duration_since(**time).unwrap_or(Duration::ZERO) <= Duration::from_secs(10))
                .count();
            
            if recent_actions >= burst_limit as usize {
                tracing::warn!(user_id = %user_id, action = ?action, burst_count = %recent_actions, burst_limit = %burst_limit, "💥 Burst limit dépassé");
                return Err(ChatError::rate_limit_exceeded_simple("rate_limit"));
            }
        }

        // Enregistrer l'action
        actions.push(now);
        Ok(())
    }
}

/// Gestionnaire de sessions sécurisé
pub struct SessionManager {
    active_sessions: HashMap<i32, SessionInfo>,
    max_sessions_per_user: u32,
}

#[derive(Debug, Clone)]
pub struct SessionInfo {
    pub token_hash: String,
    pub created_at: SystemTime,
    pub last_activity: SystemTime,
    pub ip_address: String,
    pub user_agent: Option<String>,
}

impl SessionManager {
    pub fn new() -> Self {
        Self {
            active_sessions: HashMap::new(),
            max_sessions_per_user: 5, // Max 5 sessions par utilisateur
        }
    }

    pub fn create_session(&mut self, user_id: i32, token: &str, ip: &str) -> Result<()> {
        let token_hash = self.hash_token(token);
        
        // Vérifier le nombre de sessions
        let user_sessions: Vec<_> = self.active_sessions.iter()
            .filter(|(_, session)| session.token_hash == token_hash)
            .collect();
            
        if user_sessions.len() >= self.max_sessions_per_user as usize {
            return Err(ChatError::ConnectionLimitReached);
        }

        let session = SessionInfo {
            token_hash,
            created_at: SystemTime::now(),
            last_activity: SystemTime::now(),
            ip_address: ip.to_string(),
            user_agent: None,
        };

        self.active_sessions.insert(user_id, session);
        Ok(())
    }

    pub fn validate_session(&mut self, user_id: i32, token: &str) -> Result<()> {
        let token_hash = self.hash_token(token);
        
        if let Some(session) = self.active_sessions.get_mut(&user_id) {
            if session.token_hash != token_hash {
                return Err(ChatError::unauthorized_simple("unauthorized_action"));
            }
            
            // Vérifier l'expiration (24h)
            if session.last_activity.elapsed().unwrap_or(Duration::ZERO) > Duration::from_secs(86400) {
                self.active_sessions.remove(&user_id);
                return Err(ChatError::unauthorized_simple("unauthorized_action"));
            }
            
            // Mettre à jour l'activité
            session.last_activity = SystemTime::now();
            Ok(())
        } else {
            Err(ChatError::unauthorized_simple("unauthorized_action"))
        }
    }

    fn hash_token(&self, token: &str) -> String {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};
        
        let mut hasher = DefaultHasher::new();
        token.hash(&mut hasher);
        format!("{:x}", hasher.finish())
    }
}

/// Moniteur d'IP pour détecter les comportements suspects
pub struct IpMonitor {
    ip_actions: HashMap<String, Vec<(SystemTime, SecurityAction)>>,
    blacklisted_ips: HashSet<String>,
    suspicious_threshold: u32,
}

impl IpMonitor {
    pub fn new() -> Self {
        // IPs couramment malveillantes (exemple)
        let blacklisted_ips = vec![
            "0.0.0.0",
            "255.255.255.255",
        ].into_iter().map(|s| s.to_string()).collect();

        Self {
            ip_actions: HashMap::new(),
            blacklisted_ips,
            suspicious_threshold: 100, // 100 actions par minute
        }
    }

    pub fn check_ip(&mut self, ip: &str, action: &SecurityAction) -> Result<()> {
        // Vérifier la liste noire
        if self.blacklisted_ips.contains(ip) {
            tracing::error!(ip = %ip, "🚫 IP blacklistée détectée");
            return Err(ChatError::unauthorized_simple("unauthorized_action"));
        }

        // Monitorer l'activité
        let now = SystemTime::now();
        let actions = self.ip_actions.entry(ip.to_string()).or_insert_with(Vec::new);
        
        // Nettoyer les anciennes actions (dernière minute)
        actions.retain(|(time, _)| now.duration_since(*time).unwrap_or(Duration::ZERO) <= Duration::from_secs(60));
        
        // Vérifier le seuil de suspicion
        if actions.len() >= self.suspicious_threshold as usize {
            tracing::warn!(ip = %ip, action_count = %actions.len(), "🚨 IP suspecte détectée");
            // En production, on pourrait bloquer temporairement l'IP
        }

        // Enregistrer l'action
        actions.push((now, action.clone()));
        Ok(())
    }

    pub fn blacklist_ip(&mut self, ip: &str) {
        self.blacklisted_ips.insert(ip.to_string());
        tracing::warn!(ip = %ip, "🚫 IP ajoutée à la liste noire");
    }
} 