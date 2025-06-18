# Chat Server - Documentation

## Vue d'ensemble

Le Chat Server est un serveur WebSocket en temps réel développé en Rust utilisant Tokio. Il permet la gestion de conversations en temps réel avec support des salons de discussion (rooms) et des messages privés (DM).

## Architecture

### Structure du projet

```
src/
├── main.rs           # Point d'entrée et gestion des connexions WebSocket
├── auth.rs           # Authentification JWT
├── client.rs         # Structure et méthodes du client
├── messages.rs       # Définition des messages WebSocket entrants
└── hub/
    ├── mod.rs        # Module principal du hub
    ├── common.rs     # Structure ChatHub et méthodes communes
    ├── room.rs       # Gestion des salons de discussion
    └── dm.rs         # Gestion des messages privés
```

## Fonctionnalités principales

### 1. Authentification JWT
- Validation des tokens JWT dans les en-têtes `Authorization` ou paramètres de requête
- Support des tokens Bearer et query parameters (`?token=...`)
- Extraction des informations utilisateur (user_id, username)

### 2. Gestion des connexions WebSocket
- Connexions concurrentes multiples
- Gestion automatique des déconnexions
- Système de canaux pour l'envoi de messages

### 3. Salons de discussion (Rooms)
- Rejoindre des salons existants
- Diffusion de messages à tous les membres d'un salon
- Historique des messages par salon
- Vérification d'existence des salons

### 4. Messages privés (DM)
- Envoi de messages directs entre utilisateurs
- Historique des conversations privées
- Vérification d'existence des utilisateurs

## Configuration

### Variables d'environnement

```bash
# Base de données PostgreSQL
DATABASE_URL=postgresql://user:password@localhost/database

# Adresse de binding du serveur WebSocket
WS_BIND_ADDR=127.0.0.1:9001

# Clé secrète pour la validation JWT
JWT_SECRET=your_secret_key
```

### Dépendances principales

```toml
[dependencies]
tokio = { version = "1", features = ["full"] }
tokio-tungstenite = "0.20"
sqlx = { version = "0.7", features = ["postgres", "runtime-tokio-native-tls", "chrono"] }
jsonwebtoken = "9"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tracing = "0.1"
```

## Protocole WebSocket

### Messages entrants (Client → Serveur)

#### 1. Rejoindre un salon
```json
{
  "type": "join",
  "room": "nom_du_salon"
}
```

#### 2. Envoyer un message dans un salon
```json
{
  "type": "message",
  "room": "nom_du_salon",
  "content": "Contenu du message"
}
```

#### 3. Envoyer un message privé
```json
{
  "type": "dm",
  "to": 123,
  "content": "Message privé"
}
```

#### 4. Récupérer l'historique d'un salon
```json
{
  "type": "room_history",
  "room": "nom_du_salon",
  "limit": 50
}
```

#### 5. Récupérer l'historique d'une conversation privée
```json
{
  "type": "dm_history",
  "with": 123,
  "limit": 50
}
```

### Messages sortants (Serveur → Client)

#### 1. Confirmation de connexion à un salon
```json
{
  "type": "join_ack",
  "data": {
    "room": "nom_du_salon",
    "status": "ok"
  }
}
```

#### 2. Nouveau message dans un salon
```json
{
  "type": "message",
  "data": {
    "id": 123,
    "fromUser": 456,
    "username": "alice",
    "content": "Hello world!",
    "timestamp": "2025-01-01T12:00:00Z",
    "room": "general"
  }
}
```

#### 3. Nouveau message privé
```json
{
  "type": "dm",
  "data": {
    "id": 789,
    "fromUser": 456,
    "username": "alice",
    "content": "Message privé",
    "timestamp": "2025-01-01T12:00:00Z"
  }
}
```

#### 4. Historique des messages
```json
{
  "type": "dm_history",
  "data": [
    {
      "username": "alice",
      "fromUser": 456,
      "content": "Message 1",
      "timestamp": "2025-01-01T12:00:00Z"
    }
  ]
}
```

#### 5. Messages d'erreur
```json
{
  "type": "error",
  "data": {
    "message": "Description de l'erreur"
  }
}
```

## Structure de la base de données

### Table `users`
```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR NOT NULL UNIQUE,
    -- autres champs...
);
```

### Table `rooms`
```sql
CREATE TABLE rooms (
    id SERIAL PRIMARY KEY,
    name VARCHAR NOT NULL UNIQUE,
    -- autres champs...
);
```

### Table `messages`
```sql
CREATE TABLE messages (
    id SERIAL PRIMARY KEY,
    from_user INTEGER REFERENCES users(id),
    to_user INTEGER REFERENCES users(id), -- NULL pour les messages de salon
    room VARCHAR, -- NULL pour les messages privés
    content TEXT NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

## API interne

### Structure `ChatHub`

```rust
pub struct ChatHub {
    pub db: PgPool,
    pub clients: RwLock<HashMap<i32, Client>>,
    pub rooms: RwLock<HashMap<String, Vec<i32>>>,
}
```

#### Méthodes principales

```rust
impl ChatHub {
    // Création d'une nouvelle instance
    pub fn new(db: PgPool) -> Arc<Self>
    
    // Gestion des clients
    pub async fn register(&self, user_id: i32, client: Client)
    pub async fn unregister(&self, user_id: i32)
    
    // Gestion des salons (via room.rs)
    pub async fn join_room(&self, room: &str, user_id: i32)
    pub async fn broadcast_to_room(&self, user_id: i32, username: &str, room: &str, msg: &str)
    pub async fn fetch_room_history(&self, room: &str, limit: i64) -> Vec<RoomMessage>
    pub async fn room_exists(&self, room: &str) -> bool
    
    // Gestion des messages privés (via dm.rs)
    pub async fn send_dm(&self, from_user: i32, to_user: i32, username: &str, content: &str)
    pub async fn fetch_dm_history(&self, user_id: i32, with: i32, limit: i64) -> Vec<DmMessage>
    pub async fn user_exists(&self, user_id: i32) -> bool
}
```

### Structure `Client`

```rust
pub struct Client {
    pub user_id: i32,
    pub username: String,
    pub sender: mpsc::UnboundedSender<Message>,
}

impl Client {
    pub fn send_text(&self, text: &str)
    pub fn send_json<T: serde::Serialize>(&self, value: &T)
}
```

## Gestion des erreurs

### Types d'erreurs gérées

1. **Authentification**
   - JWT invalide ou expiré
   - En-têtes d'autorisation manquants

2. **Base de données**
   - Connexion échouée
   - Requêtes SQL invalides

3. **WebSocket**
   - Messages malformés
   - Connexions fermées inopinément

4. **Logique métier**
   - Salon inexistant
   - Utilisateur introuvable
   - Permissions insuffisantes

## Logging et monitoring

### Configuration du logging

```rust
tracing_subscriber::fmt()
    .with_env_filter("chat_server=debug")
    .with_target(true)
    .init();
```

### Événements tracés

- Connexions/déconnexions clients
- Envoi/réception de messages
- Erreurs d'authentification
- Opérations base de données
- Événements de debug pour le développement

## Déploiement

### Compilation

```bash
cd backend/modules/chat_server
cargo build --release
```

### Exécution

```bash
# Avec les variables d'environnement
export DATABASE_URL="postgresql://..."
export JWT_SECRET="your_secret"
export WS_BIND_ADDR="0.0.0.0:9001"

./target/release/chat_server
```

### Docker (exemple)

```dockerfile
FROM rust:1.70 as builder
WORKDIR /app
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates
COPY --from=builder /app/target/release/chat_server /usr/local/bin/
EXPOSE 9001
CMD ["chat_server"]
```

## Sécurité

### Mesures de sécurité implémentées

1. **Authentification JWT obligatoire**
2. **Validation des permissions** avant les opérations
3. **Sanitisation des entrées** via serde
4. **Protection contre l'injection SQL** avec sqlx
5. **Limitation d'accès** aux ressources par utilisateur

### Recommandations

- Utiliser HTTPS en production
- Configurer des limites de débit
- Implémenter une rotation des clés JWT
- Ajouter des logs de sécurité
- Monitorer les connexions suspectes

## Performance

### Optimisations implémentées

- **Pool de connexions** PostgreSQL
- **Channels asynchrones** pour les messages
- **Lectures/écritures concurrentes** avec RwLock
- **Requêtes SQL optimisées** avec limit

### Métriques recommandées

- Nombre de connexions actives
- Latence des messages
- Utilisation mémoire
- Charge base de données
- Débit de messages par seconde

## Développement

### Tests

```bash
# Tests unitaires
cargo test

# Tests d'intégration avec base de données
cargo test --features "integration-tests"
```

### Debugging

1. **Logs détaillés** avec `RUST_LOG=debug`
2. **Inspection WebSocket** avec outils navigateur
3. **Monitoring base de données** avec logs PostgreSQL
4. **Profiling mémoire** avec `cargo flamegraph`

### Contribution

1. Respecter le style de code Rust standard
2. Ajouter des tests pour nouvelles fonctionnalités
3. Documenter les API publiques
4. Utiliser les logs structurés avec tracing