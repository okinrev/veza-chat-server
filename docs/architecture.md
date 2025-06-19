# 🏗️ Architecture Système Complète

**Version :** 0.2.0  
**Dernière mise à jour :** $(date +"%Y-%m-%d")

## 📋 Vue d'Ensemble

Le serveur de chat Veza est conçu selon une **architecture moderne asynchrone** basée sur Rust et Tokio, optimisée pour la **haute performance**, la **scalabilité** et la **sécurité**. Cette documentation détaille chaque composant et leurs interactions.

## 🎯 Principes Architecturaux

### **1. Performance et Scalabilité**
- **Asynchrone par défaut** : Tokio runtime pour gestion concurrentielle massive
- **Zero-copy** : Minimisation des allocations mémoire
- **Connection pooling** : Gestion optimisée des connexions base de données
- **Cache intelligent** : Redis pour réduire la latence

### **2. Sécurité par Design**
- **Principle of least privilege** : Permissions granulaires
- **Defense in depth** : Multiples couches de sécurité
- **Input validation** : Validation stricte à tous les niveaux
- **Audit trail** : Traçabilité complète des actions

### **3. Maintenabilité**
- **Séparation des responsabilités** : Modules découplés
- **Error handling centralisé** : Gestion d'erreurs cohérente
- **Configuration externalisée** : Paramètres modifiables sans recompilation
- **Logging structuré** : Debugging et monitoring facilités

## 🏗️ Architecture Globale

```mermaid
graph TB
    subgraph "Clients"
        Web[Applications Web]
        Mobile[Applications Mobile]
        API_Client[Clients API]
    end
    
    subgraph "Load Balancer"
        LB[HAProxy/Nginx]
    end
    
    subgraph "Chat Server (Rust/Tokio)"
        WS[WebSocket Handler]
        REST[REST API Handler]
        Hub[Chat Hub Central]
        Auth[Authentication]
        Security[Security Layer]
        Cache[Cache Manager]
        Monitoring[Metrics]
    end
    
    subgraph "Storage Layer"
        PG[(PostgreSQL Primary)]
        PG_R[(PostgreSQL Replica)]
        Redis[(Redis Cache)]
        Files[File Storage]
    end
    
    subgraph "External Services"
        SMTP[Email Service]
        Push[Push Notifications]
        Webhooks[Webhook Endpoints]
        Monitor[Monitoring Stack]
    end
    
    Web --> LB
    Mobile --> LB
    API_Client --> LB
    
    LB --> WS
    LB --> REST
    
    WS --> Hub
    REST --> Hub
    
    Hub --> Auth
    Hub --> Security
    Hub --> Cache
    Hub --> Monitoring
    
    Auth --> PG
    Security --> PG
    Cache --> Redis
    Cache --> PG_R
    
    Hub --> SMTP
    Hub --> Push
    Hub --> Webhooks
    
    Monitoring --> Monitor
```

## 🎮 Chat Hub Central

Le **Chat Hub** est le cœur orchestrateur du système, gérant toutes les interactions en temps réel.

### **Structure du Hub**
```rust
pub struct ChatHub {
    // Gestion des connexions actives
    pub clients: Arc<RwLock<HashMap<i32, Client>>>,
    pub rooms: Arc<RwLock<HashMap<String, Vec<i32>>>>,
    
    // Services intégrés
    pub db: PgPool,                    // Pool de connexions PostgreSQL
    pub rate_limiter: RateLimiter,     // Limitation de taux
    pub config: ServerConfig,          // Configuration globale
    pub stats: Arc<RwLock<HubStats>>,  // Statistiques temps réel
    
    // Systèmes spécialisés
    pub cache: CacheManager,           // Gestionnaire de cache
    pub metrics: ChatMetrics,          // Métriques Prometheus
    pub presence: PresenceManager,     // Gestion de présence
}
```

### **Responsabilités du Hub**
1. **Gestion des connexions** : Registration/unregistration des clients
2. **Routage des messages** : Distribution intelligente selon le type
3. **Coordination des services** : Orchestration cache, DB, monitoring
4. **Enforcement des politiques** : Rate limiting, permissions, validation

### **Flux de Traitement des Messages**

```mermaid
sequenceDiagram
    participant C as Client
    participant H as Hub
    participant V as Validation
    participant S as Security
    participant D as Database
    participant B as Broadcast
    
    C->>H: Message WebSocket
    H->>V: Validate Format
    V->>S: Security Check
    S->>H: Rate Limit Check
    H->>D: Store Message
    D->>H: Message ID
    H->>B: Broadcast to Recipients
    B->>C: Deliver Message
```

## 📡 Couche WebSocket

### **Gestionnaire de Connexions**
```rust
// Structure d'un client connecté
pub struct Client {
    pub user_id: i32,
    pub username: String,
    pub sender: UnboundedSender<Message>,
    pub last_heartbeat: Arc<RwLock<Instant>>,
    pub connected_at: Instant,
}
```

### **Types de Messages WebSocket**

#### **1. Messages de Salon**
```json
{
  "type": "join_room",
  "data": {
    "room_id": 123,
    "user_id": 456
  }
}

{
  "type": "send_message", 
  "data": {
    "room_id": 123,
    "content": "Hello world!",
    "parent_id": null,
    "metadata": {}
  }
}
```

#### **2. Messages Directs**
```json
{
  "type": "create_dm",
  "data": {
    "user1_id": 123,
    "user2_id": 456
  }
}

{
  "type": "send_dm",
  "data": {
    "conversation_id": 789,
    "content": "Message privé",
    "parent_id": null
  }
}
```

#### **3. Réactions et Interactions**
```json
{
  "type": "add_reaction",
  "data": {
    "message_id": 123,
    "emoji": "👍"
  }
}

{
  "type": "pin_message",
  "data": {
    "room_id": 123,
    "message_id": 456
  }
}
```

### **Heartbeat et Reconnexion**
```mermaid
sequenceDiagram
    participant C as Client
    participant S as Server
    
    loop Every 30s
        S->>C: Ping
        C->>S: Pong
    end
    
    Note over S: Si pas de Pong pendant 60s
    S->>S: Marquer client comme déconnecté
    S->>S: Nettoyer les ressources
```

## 🗄️ Couche de Persistance

### **Architecture Base de Données**

#### **PostgreSQL Primary/Replica**
```mermaid
graph LR
    subgraph "Database Cluster"
        PG_M[(Primary<br/>Read/Write)]
        PG_R1[(Replica 1<br/>Read Only)]
        PG_R2[(Replica 2<br/>Read Only)]
    end
    
    subgraph "Application"
        Write[Write Operations]
        Read[Read Operations]
    end
    
    Write --> PG_M
    Read --> PG_R1
    Read --> PG_R2
    
    PG_M -.->|Replication| PG_R1
    PG_M -.->|Replication| PG_R2
```

#### **Modèle de Données Principal**

```sql
-- Utilisateurs avec sécurité renforcée
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role user_role NOT NULL DEFAULT 'user',
    is_active BOOLEAN DEFAULT true,
    last_activity TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Conversations unifiées (salons + DM)
CREATE TABLE conversations (
    id BIGSERIAL PRIMARY KEY,
    uuid UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
    name VARCHAR(100),
    description TEXT,
    type conversation_type NOT NULL,
    is_public BOOLEAN DEFAULT false,
    owner_id BIGINT REFERENCES users(id),
    max_members INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Messages avec métadonnées étendues
CREATE TABLE messages (
    id BIGSERIAL PRIMARY KEY,
    uuid UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
    author_id BIGINT NOT NULL REFERENCES users(id),
    conversation_id BIGINT NOT NULL REFERENCES conversations(id),
    content TEXT NOT NULL,
    message_type message_type DEFAULT 'text',
    parent_message_id BIGINT REFERENCES messages(id),
    thread_count INTEGER DEFAULT 0,
    status message_status DEFAULT 'sent',
    is_edited BOOLEAN DEFAULT false,
    edit_count INTEGER DEFAULT 0,
    is_pinned BOOLEAN DEFAULT false,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    edited_at TIMESTAMPTZ
);
```

### **Stratégie de Cache Redis**

#### **Structure de Cache**
```redis
# Messages de salon (LRU, TTL 1h)
room_messages:123 -> [list of message objects]

# Messages directs (LRU, TTL 30min)  
dm_messages:123:456 -> [list of message objects]

# Présence utilisateur (TTL 5min)
user_presence:123 -> {status: "online", room: "general"}

# Sessions actives (TTL variable)
session:token_hash -> user_id

# Rate limiting (TTL 1min)
rate_limit:123:send_message -> {count: 5, window_start: timestamp}
```

#### **Politiques de Cache**
1. **Write-through** : Écriture simultanée en cache et DB
2. **Read-aside** : Lecture en cache d'abord, fallback sur DB
3. **TTL intelligent** : Expiration basée sur l'usage
4. **Invalidation sélective** : Suppression ciblée lors des modifications

## 🛡️ Couche de Sécurité

### **Architecture de Sécurité Multi-couches**

```mermaid
graph TD
    Input[Input Data] --> Validation[Input Validation]
    Validation --> Auth[Authentication]
    Auth --> Authz[Authorization]
    Authz --> RateLimit[Rate Limiting]
    RateLimit --> Content[Content Filtering]
    Content --> Business[Business Logic]
    Business --> Audit[Audit Logging]
```

### **1. Authentification JWT**

#### **Structure des Tokens**
```json
{
  "header": {
    "alg": "HS256",
    "typ": "JWT"
  },
  "payload": {
    "user_id": 123,
    "username": "alice",
    "role": "user",
    "iat": 1642680000,
    "exp": 1642683600,
    "aud": "veza-chat",
    "iss": "veza-auth"
  }
}
```

#### **Cycle de Vie des Tokens**
```mermaid
sequenceDiagram
    participant C as Client
    participant A as Auth Service
    participant DB as Database
    
    C->>A: Login (username/password)
    A->>DB: Verify credentials
    DB->>A: User data
    A->>A: Generate JWT + Refresh Token
    A->>DB: Store refresh token
    A->>C: Return tokens
    
    Note over C: Access token expires (15min)
    
    C->>A: Refresh request + Refresh Token
    A->>DB: Validate refresh token
    A->>A: Generate new JWT
    A->>C: New access token
```

### **2. Rate Limiting Intelligent**

#### **Algorithme Token Bucket par Action**
```rust
pub struct RateLimiter {
    // Limites par type d'action
    send_message: u32,      // 60 msg/min
    join_room: u32,         // 10 /min
    create_room: u32,       // 3 /min
    upload_file: u32,       // 5 /min
    
    // Fenêtres temporelles
    window_duration: Duration,
    
    // État par utilisateur
    user_buckets: HashMap<(i32, ActionType), TokenBucket>,
}
```

#### **Rate Limiting Adaptatif**
- **Utilisateurs nouveaux** : Limites plus strictes
- **Utilisateurs confirmés** : Limites plus souples  
- **Modérateurs** : Limites étendues
- **Détection de spam** : Réduction automatique des limites

### **3. Validation et Filtrage de Contenu**

#### **Pipeline de Validation**
```rust
pub async fn validate_message_content(content: &str) -> Result<String> {
    // 1. Validation basique
    validate_length(content, MAX_MESSAGE_LENGTH)?;
    validate_encoding(content)?;
    
    // 2. Sanitisation HTML
    let sanitized = sanitize_html(content);
    
    // 3. Détection de spam
    if detect_spam(&sanitized).await? {
        return Err(ChatError::SpamDetected);
    }
    
    // 4. Filtrage de toxicité
    if detect_toxicity(&sanitized).await? {
        return Err(ChatError::InappropriateContent);
    }
    
    // 5. Validation des mentions
    validate_mentions(&sanitized).await?;
    
    Ok(sanitized)
}
```

## 📊 Monitoring et Observabilité

### **Architecture de Monitoring**

```mermaid
graph LR
    subgraph "Chat Server"
        App[Application]
        Metrics[Metrics Collector]
        Logs[Structured Logs]
    end
    
    subgraph "Monitoring Stack"
        Prometheus[Prometheus]
        Grafana[Grafana]
        AlertManager[Alert Manager]
        Loki[Loki]
    end
    
    subgraph "Notifications"
        Slack[Slack]
        Email[Email]
        PagerDuty[PagerDuty]
    end
    
    Metrics --> Prometheus
    Logs --> Loki
    
    Prometheus --> Grafana
    Prometheus --> AlertManager
    Loki --> Grafana
    
    AlertManager --> Slack
    AlertManager --> Email
    AlertManager --> PagerDuty
```

### **Métriques Clés**

#### **Métriques Applicatives**
```prometheus
# Connexions WebSocket
chat_websocket_connections_total
chat_websocket_connections_active
chat_websocket_connection_duration_seconds

# Messages
chat_messages_sent_total{type="room|dm", room_id}
chat_messages_received_total{type="room|dm"}
chat_message_processing_duration_seconds{operation}
chat_message_size_bytes{type="room|dm"}

# Authentification
chat_auth_requests_total{status="success|failure", method}
chat_auth_duration_seconds{method}

# Base de données
chat_db_operations_total{operation="select|insert|update|delete"}
chat_db_operation_duration_seconds{operation}
chat_db_connections_active
chat_db_connections_total

# Cache
chat_cache_hits_total{cache_type}
chat_cache_misses_total{cache_type}
chat_cache_operations_duration_seconds{operation}

# Erreurs
chat_errors_total{type="validation|auth|database|network", severity}
chat_rate_limit_exceeded_total{action_type}
```

#### **Métriques Système**
```prometheus
# Ressources système
process_resident_memory_bytes
process_cpu_seconds_total
process_open_fds

# Tokio runtime
tokio_worker_threads_total
tokio_blocking_queue_depth
tokio_budget_forced_yield_count
```

### **Alertes Critiques**

#### **Règles d'Alerting Prometheus**
```yaml
groups:
- name: chat_server_critical
  rules:
  - alert: HighErrorRate
    expr: rate(chat_errors_total[5m]) > 0.1
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Taux d'erreur élevé détecté"
      
  - alert: DatabaseConnectionsExhausted
    expr: chat_db_connections_active / chat_db_connections_total > 0.9
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Pool de connexions DB saturé"
      
  - alert: MemoryUsageHigh
    expr: process_resident_memory_bytes > 1e9  # 1GB
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Utilisation mémoire élevée"
```

## 🔄 Patterns d'Intégration

### **1. Intégration Synchrone (REST API)**

#### **Authentification**
```http
POST /api/v1/auth/login
Content-Type: application/json

{
  "username": "alice",
  "password": "secret123"
}

HTTP/1.1 200 OK
{
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...",
  "refresh_token": "f4a2c8e1-8b5d-4c9e-9f2a-1e3d5c7b9a0f",
  "expires_in": 900,
  "user": {
    "id": 123,
    "username": "alice",
    "role": "user"
  }
}
```

#### **Envoi de Message**
```http
POST /api/v1/rooms/123/messages
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...
Content-Type: application/json

{
  "content": "Hello from REST API!",
  "parent_message_id": null,
  "metadata": {
    "source": "mobile_app",
    "version": "1.2.0"
  }
}

HTTP/1.1 201 Created
{
  "id": 456,
  "uuid": "550e8400-e29b-41d4-a716-446655440000",
  "content": "Hello from REST API!",
  "author_id": 123,
  "created_at": "2024-01-15T10:30:00Z"
}
```

### **2. Intégration Asynchrone (WebSocket)**

#### **Client Go avec Reconnexion Automatique**
```go
type ChatClient struct {
    conn        *websocket.Conn
    url         string
    token       string
    messagesCh  chan []byte
    reconnectCh chan bool
    mu          sync.RWMutex
}

func (c *ChatClient) Connect() error {
    conn, _, err := websocket.DefaultDialer.Dial(c.url, nil)
    if err != nil {
        return err
    }
    
    c.mu.Lock()
    c.conn = conn
    c.mu.Unlock()
    
    // Authentification immédiate
    auth := map[string]interface{}{
        "type": "authenticate",
        "data": map[string]string{"token": c.token},
    }
    return c.conn.WriteJSON(auth)
}

func (c *ChatClient) handleReconnect() {
    for range c.reconnectCh {
        for {
            if err := c.Connect(); err == nil {
                log.Println("Reconnexion réussie")
                break
            }
            time.Sleep(5 * time.Second)
        }
    }
}
```

#### **Client React avec Hook Personnalisé**
```typescript
interface UseWebSocketReturn {
  isConnected: boolean;
  messages: Message[];
  sendMessage: (content: string, roomId?: number) => Promise<void>;
  joinRoom: (roomId: number) => Promise<void>;
  error: string | null;
}

export function useWebSocket(url: string, token: string): UseWebSocketReturn {
  const [ws, setWs] = useState<WebSocket | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [messages, setMessages] = useState<Message[]>([]);
  const [error, setError] = useState<string | null>(null);
  
  useEffect(() => {
    const websocket = new WebSocket(url);
    
    websocket.onopen = () => {
      setIsConnected(true);
      // Authentification automatique
      websocket.send(JSON.stringify({
        type: 'authenticate',
        data: { token }
      }));
    };
    
    websocket.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === 'message') {
        setMessages(prev => [...prev, data.data]);
      }
    };
    
    websocket.onclose = () => {
      setIsConnected(false);
      // Reconnexion automatique après 3s
      setTimeout(() => {
        setWs(new WebSocket(url));
      }, 3000);
    };
    
    setWs(websocket);
    
    return () => websocket.close();
  }, [url, token]);
  
  const sendMessage = useCallback(async (content: string, roomId?: number) => {
    if (!ws || !isConnected) throw new Error('Non connecté');
    
    ws.send(JSON.stringify({
      type: roomId ? 'send_message' : 'send_dm',
      data: { content, room_id: roomId }
    }));
  }, [ws, isConnected]);
  
  return { isConnected, messages, sendMessage, joinRoom, error };
}
```

## 🚀 Optimisations Performance

### **1. Optimisations Réseau**

#### **Compression WebSocket**
```rust
// Configuration de compression per-message-deflate
let compression = Compression::default()
    .client_max_window_bits(15)
    .server_max_window_bits(15)
    .client_no_context_takeover(false)
    .server_no_context_takeover(false);
```

#### **Batching des Messages**
```rust
pub struct MessageBatcher {
    pending: Vec<Message>,
    batch_size: usize,
    flush_interval: Duration,
}

impl MessageBatcher {
    pub async fn add_message(&mut self, msg: Message) {
        self.pending.push(msg);
        
        if self.pending.len() >= self.batch_size {
            self.flush().await;
        }
    }
    
    async fn flush(&mut self) {
        if !self.pending.is_empty() {
            let batch = std::mem::take(&mut self.pending);
            self.send_batch(batch).await;
        }
    }
}
```

### **2. Optimisations Base de Données**

#### **Prepared Statements avec Cache**
```rust
pub struct QueryCache {
    cache: HashMap<String, sqlx::query::Query<'static, Postgres, PgArguments>>,
}

impl QueryCache {
    pub fn get_or_prepare(&mut self, sql: &str) -> &sqlx::query::Query<'static, Postgres, PgArguments> {
        self.cache.entry(sql.to_string())
            .or_insert_with(|| sqlx::query(sql))
    }
}
```

#### **Pagination Efficace**
```sql
-- Pagination cursor-based (plus efficace que OFFSET)
SELECT * FROM messages 
WHERE conversation_id = $1 
  AND id < $2  -- cursor
ORDER BY id DESC 
LIMIT $3;
```

### **3. Optimisations Mémoire**

#### **Pool d'Objets pour Messages**
```rust
pub struct MessagePool {
    pool: Vec<Message>,
    capacity: usize,
}

impl MessagePool {
    pub fn get(&mut self) -> Message {
        self.pool.pop().unwrap_or_else(Message::new)
    }
    
    pub fn return_message(&mut self, mut msg: Message) {
        if self.pool.len() < self.capacity {
            msg.reset();
            self.pool.push(msg);
        }
    }
}
```

## 📏 Limites et Contraintes

### **Limites Techniques**

| Composant | Limite | Raison | Configurable |
|-----------|---------|---------|--------------|
| **Connexions simultanées** | 10,000 | Mémoire + File descriptors | ✅ |
| **Messages/seconde** | 1,000 | CPU + I/O base de données | ✅ |
| **Taille message** | 2MB | Mémoire + Réseau | ✅ |
| **Salons par utilisateur** | 100 | Performance queries | ✅ |
| **Fichiers/message** | 10 | Stockage + Performance | ✅ |

### **Contraintes de Sécurité**

| Contrainte | Valeur | Justification |
|------------|---------|---------------|
| **Longueur mot de passe** | 8+ caractères | Sécurité minimale |
| **Durée session** | 15 minutes | Compromis sécurité/UX |
| **Tentatives de login** | 5 par 15min | Anti brute-force |
| **Taille upload** | 10MB | Stockage + Sécurité |

## 🔧 Configuration Production

### **Optimisations Système**

#### **Paramètres OS (Linux)**
```bash
# Augmenter les limites de file descriptors
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# Optimisations réseau
echo "net.core.somaxconn = 65536" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog = 65536" >> /etc/sysctl.conf
sysctl -p
```

#### **Configuration PostgreSQL**
```postgresql
# postgresql.conf optimisations
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
```

#### **Configuration Redis**
```redis
# redis.conf optimisations
maxmemory 512mb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
```

---

**Cette architecture garantit une base solide pour un serveur de chat moderne, scalable et sécurisé. Chaque composant est conçu pour être maintenu, monitoré et étendu selon les besoins spécifiques de votre application.** 