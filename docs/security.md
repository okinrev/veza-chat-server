# 🔐 Sécurité - Documentation Complète

**Version :** 0.2.0  
**Dernière mise à jour :** $(date +"%Y-%m-%d")

## 📋 Vue d'Ensemble

Le serveur de chat Veza implémente une architecture de sécurité multicouches couvrant l'authentification, l'autorisation, la protection des données, l'audit, et la prévention des attaques. Cette documentation détaille tous les aspects sécuritaires.

## 🔑 Authentification

### **JWT (JSON Web Tokens)**

#### **Structure des Tokens**
```json
{
  "header": {
    "alg": "HS256",
    "typ": "JWT"
  },
  "payload": {
    "sub": "123",
    "username": "john_doe",
    "role": "user",
    "permissions": ["read_messages", "send_messages"],
    "iat": 1705920000,
    "exp": 1705921800,
    "jti": "unique-token-id"
  }
}
```

#### **Cycle de Vie des Tokens**
- **Access Token** : Durée de vie courte (15 minutes)
- **Refresh Token** : Durée de vie longue (7 jours)
- **Rotation automatique** des refresh tokens
- **Révocation immédiate** en cas de compromission

#### **Validation des Tokens**
```rust
// Validation côté serveur
pub fn validate_token(token: &str) -> Result<Claims, TokenError> {
    let validation = Validation::new(Algorithm::HS256);
    let token_data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(JWT_SECRET.as_ref()),
        &validation,
    )?;
    
    // Vérifications supplémentaires
    if token_data.claims.exp < SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs() {
        return Err(TokenError::Expired);
    }
    
    // Vérifier si le token n'est pas révoqué
    if is_token_revoked(&token_data.claims.jti).await? {
        return Err(TokenError::Revoked);
    }
    
    Ok(token_data.claims)
}
```

### **Authentification Multi-Facteurs (2FA)**

#### **TOTP (Time-based One-Time Password)**
```http
POST /api/v1/auth/2fa/enable
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

{
  "backup_codes": true
}
```

**Réponse :**
```json
{
  "success": true,
  "data": {
    "secret": "JBSWY3DPEHPK3PXP",
    "qr_code": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...",
    "backup_codes": [
      "12345-67890",
      "23456-78901",
      "34567-89012"
    ]
  }
}
```

#### **Vérification 2FA**
```http
POST /api/v1/auth/login
Content-Type: application/json

{
  "username": "john_doe",
  "password": "secure_password",
  "totp_code": "123456"
}
```

### **Authentification par Clés API**

#### **Génération de Clés API**
```http
POST /api/v1/auth/api-keys
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

{
  "name": "Integration Bot",
  "permissions": ["read_messages", "send_messages"],
  "expires_at": "2024-12-31T23:59:59Z",
  "ip_whitelist": ["192.168.1.0/24", "10.0.0.1"]
}
```

#### **Utilisation des Clés API**
```http
GET /api/v1/rooms
X-API-Key: veza_ak_1234567890abcdef...
```

## 🛡️ Autorisation

### **Système de Rôles et Permissions**

#### **Rôles Prédéfinis**
```json
{
  "roles": {
    "admin": {
      "permissions": ["*"],
      "description": "Accès complet au système"
    },
    "moderator": {
      "permissions": [
        "read_messages", "send_messages", "delete_messages",
        "pin_messages", "kick_users", "ban_users",
        "manage_rooms", "view_audit_logs"
      ],
      "description": "Modération des salons"
    },
    "user": {
      "permissions": [
        "read_messages", "send_messages", "react_messages",
        "create_rooms", "join_rooms", "send_dm"
      ],
      "description": "Utilisateur standard"
    },
    "guest": {
      "permissions": ["read_messages"],
      "description": "Lecture seule"
    }
  }
}
```

#### **Permissions Granulaires**
```rust
#[derive(Debug, Clone, PartialEq)]
pub enum Permission {
    // Messages
    ReadMessages,
    SendMessages,
    EditOwnMessages,
    EditAllMessages,
    DeleteOwnMessages,
    DeleteAllMessages,
    PinMessages,
    
    // Salons
    CreateRooms,
    JoinRooms,
    ManageRooms,
    DeleteRooms,
    
    // Utilisateurs
    KickUsers,
    BanUsers,
    ManageUsers,
    ViewUserProfiles,
    
    // Administration
    ViewAuditLogs,
    ManageSystem,
    ManagePermissions,
    
    // Messages directs
    SendDM,
    BlockUsers,
    
    // Fichiers
    UploadFiles,
    DeleteFiles,
    ManageFiles,
}
```

#### **Vérification des Permissions**
```rust
pub async fn check_permission(
    user_id: i32,
    permission: Permission,
    context: PermissionContext,
) -> Result<bool, SecurityError> {
    let user_permissions = get_user_permissions(user_id).await?;
    
    // Vérification globale
    if user_permissions.contains(&Permission::All) {
        return Ok(true);
    }
    
    // Vérification spécifique
    if !user_permissions.contains(&permission) {
        return Ok(false);
    }
    
    // Vérifications contextuelles
    match context {
        PermissionContext::Room(room_id) => {
            check_room_permission(user_id, room_id, permission).await
        },
        PermissionContext::Message(message_id) => {
            check_message_permission(user_id, message_id, permission).await
        },
        PermissionContext::Global => Ok(true),
    }
}
```

### **Contrôle d'Accès Basé sur les Ressources (RBAC)**

#### **Politique d'Accès aux Salons**
```json
{
  "room_access_policy": {
    "public_rooms": {
      "read": ["authenticated"],
      "write": ["member", "moderator", "admin"],
      "admin": ["owner", "admin"]
    },
    "private_rooms": {
      "read": ["member", "moderator", "admin"],
      "write": ["member", "moderator", "admin"],
      "admin": ["owner", "admin"]
    },
    "restricted_rooms": {
      "read": ["invited", "moderator", "admin"],
      "write": ["invited", "moderator", "admin"],
      "admin": ["owner", "admin"]
    }
  }
}
```

## 🔒 Protection des Données

### **Chiffrement en Transit**

#### **TLS 1.3**
```nginx
# Configuration Nginx
ssl_protocols TLSv1.3;
ssl_ciphers 'TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256';
ssl_prefer_server_ciphers off;
ssl_ecdh_curve secp384r1;
```

#### **WebSocket Sécurisé (WSS)**
```javascript
// Client WebSocket sécurisé
const ws = new WebSocket('wss://chat.example.com/ws', {
    headers: {
        'Authorization': `Bearer ${token}`
    }
});
```

### **Chiffrement au Repos**

#### **Base de Données**
```sql
-- Chiffrement des champs sensibles
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email_encrypted BYTEA NOT NULL, -- Chiffré avec AES-256
    password_hash VARCHAR(255) NOT NULL, -- bcrypt
    created_at TIMESTAMP DEFAULT NOW()
);
```

#### **Chiffrement des Messages Sensibles**
```rust
use aes_gcm::{Aes256Gcm, Key, Nonce};
use rand::Rng;

pub fn encrypt_message(content: &str, key: &[u8]) -> Result<Vec<u8>, CryptoError> {
    let cipher = Aes256Gcm::new(Key::from_slice(key));
    let nonce = Nonce::from_slice(&rand::thread_rng().gen::<[u8; 12]>());
    
    let ciphertext = cipher.encrypt(nonce, content.as_bytes())
        .map_err(|_| CryptoError::EncryptionFailed)?;
    
    // Préfixer avec le nonce
    let mut result = nonce.to_vec();
    result.extend_from_slice(&ciphertext);
    
    Ok(result)
}

pub fn decrypt_message(encrypted_data: &[u8], key: &[u8]) -> Result<String, CryptoError> {
    let (nonce, ciphertext) = encrypted_data.split_at(12);
    let cipher = Aes256Gcm::new(Key::from_slice(key));
    let nonce = Nonce::from_slice(nonce);
    
    let plaintext = cipher.decrypt(nonce, ciphertext)
        .map_err(|_| CryptoError::DecryptionFailed)?;
    
    String::from_utf8(plaintext)
        .map_err(|_| CryptoError::InvalidUtf8)
}
```

### **Hachage des Mots de Passe**

#### **Argon2**
```rust
use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier};
use argon2::password_hash::{rand_core::OsRng, SaltString};

pub fn hash_password(password: &str) -> Result<String, PasswordError> {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    
    let password_hash = argon2.hash_password(password.as_bytes(), &salt)
        .map_err(|_| PasswordError::HashingFailed)?;
    
    Ok(password_hash.to_string())
}

pub fn verify_password(password: &str, hash: &str) -> Result<bool, PasswordError> {
    let parsed_hash = PasswordHash::new(hash)
        .map_err(|_| PasswordError::InvalidHash)?;
    
    let argon2 = Argon2::default();
    
    match argon2.verify_password(password.as_bytes(), &parsed_hash) {
        Ok(()) => Ok(true),
        Err(_) => Ok(false),
    }
}
```

## 🚫 Protection contre les Attaques

### **Rate Limiting**

#### **Configuration Multi-Niveaux**
```rust
pub struct RateLimitConfig {
    pub global: RateLimit,
    pub per_user: RateLimit,
    pub per_ip: RateLimit,
    pub per_endpoint: HashMap<String, RateLimit>,
}

#[derive(Clone)]
pub struct RateLimit {
    pub requests: u32,
    pub window: Duration,
    pub burst: u32,
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        let mut per_endpoint = HashMap::new();
        
        // Endpoints sensibles
        per_endpoint.insert("/auth/login".to_string(), RateLimit {
            requests: 5,
            window: Duration::from_secs(300), // 5 min
            burst: 2,
        });
        
        per_endpoint.insert("/messages".to_string(), RateLimit {
            requests: 60,
            window: Duration::from_secs(60), // 1 min
            burst: 10,
        });
        
        Self {
            global: RateLimit {
                requests: 1000,
                window: Duration::from_secs(60),
                burst: 100,
            },
            per_user: RateLimit {
                requests: 100,
                window: Duration::from_secs(60),
                burst: 20,
            },
            per_ip: RateLimit {
                requests: 200,
                window: Duration::from_secs(60),
                burst: 50,
            },
            per_endpoint,
        }
    }
}
```

#### **Implémentation Redis**
```rust
pub async fn check_rate_limit(
    redis: &mut Connection,
    key: &str,
    limit: &RateLimit,
) -> Result<RateLimitStatus, RedisError> {
    let current_time = SystemTime::now()
        .duration_since(UNIX_EPOCH)?
        .as_secs();
    
    let window_start = current_time - limit.window.as_secs();
    
    // Nettoyer les anciennes entrées
    redis.zremrangebyscore(key, 0, window_start as f64).await?;
    
    // Compter les requêtes actuelles
    let current_count: u32 = redis.zcard(key).await?;
    
    if current_count >= limit.requests {
        let oldest_request: Option<f64> = redis.zrange(key, 0, 0, ZRange::ByScore).await?
            .first().cloned();
        
        let retry_after = if let Some(oldest) = oldest_request {
            (oldest as u64 + limit.window.as_secs()).saturating_sub(current_time)
        } else {
            limit.window.as_secs()
        };
        
        return Ok(RateLimitStatus::Exceeded { retry_after });
    }
    
    // Ajouter la requête actuelle
    redis.zadd(key, current_time as f64, current_time).await?;
    redis.expire(key, limit.window.as_secs() as usize).await?;
    
    Ok(RateLimitStatus::Allowed {
        remaining: limit.requests - current_count - 1,
        reset_at: current_time + limit.window.as_secs(),
    })
}
```

### **Protection CSRF**

#### **Tokens CSRF**
```rust
use csrf::{CsrfProtection, CsrfToken};

pub fn generate_csrf_token(session_id: &str) -> String {
    let protect = CsrfProtection::from_key([0u8; 32]); // Clé sécurisée en production
    let (token, _) = protect.generate_token_pair(None, 3600).unwrap();
    token.b64_string()
}

pub fn verify_csrf_token(token: &str, session_id: &str) -> bool {
    let protect = CsrfProtection::from_key([0u8; 32]);
    let token = CsrfToken::from_base64(token).unwrap();
    protect.verify_token_pair(&token, &session_id.as_bytes()).is_ok()
}
```

### **Protection XSS**

#### **Sanitisation des Entrées**
```rust
use ammonia::{Builder, UrlRelative};

pub fn sanitize_message_content(content: &str) -> String {
    Builder::default()
        .tags(hashset!["b", "i", "u", "code", "pre", "a"])
        .tag_attributes(hashmap![
            "a" => hashset!["href"]
        ])
        .url_relative(UrlRelative::Deny)
        .clean(content)
        .to_string()
}

pub fn escape_html(content: &str) -> String {
    content
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#x27;")
}
```

### **Protection contre l'Injection SQL**

#### **Requêtes Préparées avec SQLx**
```rust
// ❌ Vulnérable à l'injection SQL
pub async fn get_user_messages_unsafe(
    pool: &PgPool,
    user_id: i32,
    content_filter: &str
) -> Result<Vec<Message>, sqlx::Error> {
    let query = format!(
        "SELECT * FROM messages WHERE author_id = {} AND content LIKE '%{}%'",
        user_id, content_filter
    );
    sqlx::query_as::<_, Message>(&query).fetch_all(pool).await
}

// ✅ Sécurisé avec requête préparée
pub async fn get_user_messages_safe(
    pool: &PgPool,
    user_id: i32,
    content_filter: &str
) -> Result<Vec<Message>, sqlx::Error> {
    sqlx::query_as!(
        Message,
        "SELECT * FROM messages WHERE author_id = $1 AND content ILIKE $2",
        user_id,
        format!("%{}%", content_filter)
    )
    .fetch_all(pool)
    .await
}
```

### **Protection DDoS**

#### **Configuration Nginx**
```nginx
# Rate limiting par IP
limit_req_zone $binary_remote_addr zone=chat_api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=chat_ws:10m rate=5r/s;

# Limitation des connexions concurrentes
limit_conn_zone $binary_remote_addr zone=chat_conn:10m;

server {
    # Appliquer les limites
    limit_req zone=chat_api burst=20 nodelay;
    limit_conn chat_conn 10;
    
    # Timeouts
    client_body_timeout 10s;
    client_header_timeout 10s;
    send_timeout 30s;
    
    # Taille des requêtes
    client_max_body_size 10M;
    client_body_buffer_size 128k;
    
    location /api/ {
        limit_req zone=chat_api burst=10 nodelay;
        proxy_pass http://chat_backend;
    }
    
    location /ws {
        limit_req zone=chat_ws burst=5 nodelay;
        proxy_pass http://chat_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

## 📋 Audit et Logging

### **Événements d'Audit**

#### **Types d'Événements**
```rust
#[derive(Debug, Serialize, Deserialize)]
pub enum AuditEvent {
    // Authentification
    LoginSuccess { user_id: i32, ip_address: String },
    LoginFailure { username: String, ip_address: String, reason: String },
    LogoutSuccess { user_id: i32 },
    TokenRefreshed { user_id: i32 },
    
    // Messages
    MessageSent { user_id: i32, room_id: i32, message_id: i32 },
    MessageEdited { user_id: i32, message_id: i32, room_id: i32 },
    MessageDeleted { user_id: i32, message_id: i32, room_id: i32, reason: Option<String> },
    
    // Salons
    RoomCreated { user_id: i32, room_id: i32 },
    RoomJoined { user_id: i32, room_id: i32 },
    RoomLeft { user_id: i32, room_id: i32 },
    
    // Administration
    UserBanned { admin_id: i32, user_id: i32, reason: String },
    UserUnbanned { admin_id: i32, user_id: i32 },
    PermissionChanged { admin_id: i32, user_id: i32, old_role: String, new_role: String },
    
    // Sécurité
    RateLimitExceeded { ip_address: String, endpoint: String },
    SuspiciousActivity { user_id: Option<i32>, ip_address: String, description: String },
    SecurityViolation { user_id: Option<i32>, violation_type: String, details: String },
}
```

#### **Enregistrement d'Audit**
```rust
pub async fn log_audit_event(
    pool: &PgPool,
    event: AuditEvent,
    context: AuditContext,
) -> Result<(), AuditError> {
    let event_data = serde_json::to_value(&event)?;
    
    sqlx::query!(
        r#"
        INSERT INTO audit_logs (
            event_type, event_data, user_id, ip_address, 
            user_agent, request_id, created_at
        ) VALUES ($1, $2, $3, $4, $5, $6, NOW())
        "#,
        event.event_type(),
        event_data,
        context.user_id,
        context.ip_address,
        context.user_agent,
        context.request_id
    )
    .execute(pool)
    .await?;
    
    // Alertes en temps réel pour les événements critiques
    if event.is_critical() {
        send_security_alert(&event, &context).await?;
    }
    
    Ok(())
}
```

### **Monitoring de Sécurité**

#### **Métriques Prometheus**
```rust
use prometheus::{Counter, Histogram, Gauge};

pub struct SecurityMetrics {
    pub login_attempts: Counter,
    pub login_failures: Counter,
    pub rate_limit_hits: Counter,
    pub suspicious_activities: Counter,
    pub active_sessions: Gauge,
    pub auth_duration: Histogram,
}

impl SecurityMetrics {
    pub fn new() -> Self {
        Self {
            login_attempts: Counter::new("auth_login_attempts_total", "Total login attempts").unwrap(),
            login_failures: Counter::new("auth_login_failures_total", "Failed login attempts").unwrap(),
            rate_limit_hits: Counter::new("rate_limit_hits_total", "Rate limit violations").unwrap(),
            suspicious_activities: Counter::new("security_suspicious_activities_total", "Suspicious activities").unwrap(),
            active_sessions: Gauge::new("auth_active_sessions", "Number of active sessions").unwrap(),
            auth_duration: Histogram::with_opts(
                prometheus::HistogramOpts::new("auth_duration_seconds", "Authentication duration")
                    .buckets(vec![0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0])
            ).unwrap(),
        }
    }
}
```

### **Alertes de Sécurité**

#### **Détection d'Anomalies**
```rust
pub async fn detect_anomalies(
    redis: &mut Connection,
    user_id: i32,
    activity: &UserActivity,
) -> Result<Vec<SecurityAlert>, SecurityError> {
    let mut alerts = Vec::new();
    
    // Détection de connexions simultanées suspectes
    let active_sessions = get_user_active_sessions(redis, user_id).await?;
    if active_sessions.len() > 5 {
        alerts.push(SecurityAlert::MultipleActiveSessions {
            user_id,
            session_count: active_sessions.len(),
        });
    }
    
    // Détection de géolocalisation inhabituelle
    if let Some(location) = &activity.location {
        let recent_locations = get_user_recent_locations(redis, user_id).await?;
        if is_unusual_location(location, &recent_locations) {
            alerts.push(SecurityAlert::UnusualLocation {
                user_id,
                location: location.clone(),
            });
        }
    }
    
    // Détection de volume de messages suspect
    let message_rate = get_user_message_rate(redis, user_id).await?;
    if message_rate > 100.0 { // messages par minute
        alerts.push(SecurityAlert::HighMessageVolume {
            user_id,
            rate: message_rate,
        });
    }
    
    Ok(alerts)
}
```

## 🛠️ Configuration Sécurisée

### **Variables d'Environnement**
```bash
# Secrets critiques
JWT_SECRET="your-super-secure-jwt-secret-key-here"
DATABASE_ENCRYPTION_KEY="your-database-encryption-key-here"
WEBHOOK_SECRET="your-webhook-secret-key"

# Configuration JWT
JWT_EXPIRY_MINUTES=15
JWT_REFRESH_EXPIRY_DAYS=7

# Rate Limiting
RATE_LIMIT_GLOBAL_RPM=1000
RATE_LIMIT_PER_USER_RPM=100
RATE_LIMIT_PER_IP_RPM=200

# Sécurité CORS
CORS_ALLOWED_ORIGINS="https://your-frontend.com,https://your-admin.com"
CORS_ALLOWED_METHODS="GET,POST,PUT,DELETE"
CORS_MAX_AGE=3600

# Sessions
SESSION_TIMEOUT_MINUTES=30
MAX_CONCURRENT_SESSIONS=3

# Upload de fichiers
MAX_FILE_SIZE_MB=10
ALLOWED_FILE_TYPES="jpg,jpeg,png,gif,pdf,txt,docx"
VIRUS_SCAN_ENABLED=true

# Monitoring
PROMETHEUS_METRICS_ENABLED=true
AUDIT_LOG_RETENTION_DAYS=90
SECURITY_ALERT_WEBHOOK="https://your-alerts.com/webhook"
```

### **Configuration TLS**
```toml
# Cargo.toml - Dépendances de sécurité
[dependencies]
rustls = "0.21"
tokio-rustls = "0.24"
webpki-roots = "0.25"
ring = "0.16"
argon2 = "0.5"
aes-gcm = "0.10"
sha2 = "0.10"
hmac = "0.12"
jwt = "0.16"
csrf = "0.4"
ammonia = "3.3"
```

## 🚨 Réponse aux Incidents

### **Procédures d'Urgence**

#### **Révocation de Tokens**
```rust
pub async fn revoke_all_user_tokens(
    redis: &mut Connection,
    user_id: i32,
    reason: &str,
) -> Result<(), SecurityError> {
    // Obtenir tous les tokens actifs
    let active_tokens = get_user_active_tokens(redis, user_id).await?;
    
    // Marquer comme révoqués
    for token in active_tokens {
        redis.sadd("revoked_tokens", &token.jti).await?;
        redis.expire(&format!("revoked_tokens:{}", token.jti), 86400).await?;
    }
    
    // Log d'audit
    log_audit_event(
        &pool,
        AuditEvent::TokensRevoked { user_id, reason: reason.to_string() },
        AuditContext::system(),
    ).await?;
    
    // Notification utilisateur
    send_security_notification(user_id, "Vos sessions ont été révoquées pour des raisons de sécurité").await?;
    
    Ok(())
}
```

#### **Blocage d'IP**
```rust
pub async fn block_ip_address(
    redis: &mut Connection,
    ip_address: &str,
    duration: Duration,
    reason: &str,
) -> Result<(), SecurityError> {
    let block_key = format!("blocked_ip:{}", ip_address);
    
    redis.setex(&block_key, duration.as_secs() as usize, reason).await?;
    
    // Log d'audit
    log_audit_event(
        &pool,
        AuditEvent::IpBlocked {
            ip_address: ip_address.to_string(),
            duration: duration.as_secs(),
            reason: reason.to_string(),
        },
        AuditContext::system(),
    ).await?;
    
    Ok(())
}
```

## 📚 Bonnes Pratiques

### **1. Développement Sécurisé**
- **Validation stricte** de toutes les entrées utilisateur
- **Principe du moindre privilège** pour les permissions
- **Tests de sécurité** automatisés dans la CI/CD
- **Revue de code** obligatoire pour les changements sensibles

### **2. Déploiement Sécurisé**
- **Chiffrement** de toutes les communications
- **Isolation** des environnements (dev/staging/prod)
- **Secrets management** avec rotation automatique
- **Monitoring** continu de sécurité

### **3. Maintenance Sécurisée**
- **Mises à jour** régulières des dépendances
- **Scans de vulnérabilités** automatisés
- **Backup chiffrés** avec tests de restauration
- **Plans de réponse** aux incidents documentés

### **4. Conformité**
- **RGPD** : Droit à l'oubli, portabilité des données
- **Audit trails** complets et immuables
- **Chiffrement** selon les standards industriels
- **Rétention** des données selon les politiques légales

---

Cette architecture de sécurité multicouches assure une protection robuste contre les menaces modernes tout en maintenant une expérience utilisateur fluide. 