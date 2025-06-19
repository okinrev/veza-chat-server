# 💬 Guide des Messages Directs (DM) Enrichis - Veza Chat Server

## 🎯 Vue d'ensemble

Les **DM Enrichis** apportent toutes les fonctionnalités avancées des salons aux messages directs, créant une **parité complète** entre les deux systèmes de communication.

### ✅ Fonctionnalités Complètes DM vs Salons

| Fonctionnalité | DM | Salons | Status |
|---|---|---|---|
| Messages de base | ✅ | ✅ | **PARITÉ** |
| Historique paginé | ✅ | ✅ | **PARITÉ** |
| Multi-utilisateurs | ✅ (2 users) | ✅ (N users) | **PARITÉ** |
| Réactions emoji | ✅ | ✅ | **PARITÉ** |
| Messages épinglés | ✅ | ✅ | **PARITÉ** |
| Threads/Réponses | ✅ | ✅ | **PARITÉ** |
| Mentions @user | ✅ | ✅ | **PARITÉ** |
| Modération | ✅ (Blocage) | ✅ (Rôles) | **PARITÉ** |
| Audit logs | ✅ | ✅ | **PARITÉ** |
| Métadonnées | ✅ | ✅ | **PARITÉ** |

## 🏗️ Architecture

### Structure de Base de Données

```sql
-- Table des conversations DM
CREATE TABLE dm_conversations (
    id BIGSERIAL PRIMARY KEY,
    uuid UUID UNIQUE NOT NULL,
    user1_id BIGINT NOT NULL,  -- Toujours le plus petit ID
    user2_id BIGINT NOT NULL,  -- Toujours le plus grand ID
    is_blocked BOOLEAN DEFAULT FALSE,
    blocked_by BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Les messages DM utilisent la table messages existante
-- avec conversation_id pointant vers dm_conversations.id
```

### Modules Rust

```
src/hub/
├── dm_enhanced.rs          # Logique métier DM enrichie
├── dm_websocket_handler.rs # Gestionnaire WebSocket DM
├── reactions.rs            # Système de réactions (partagé)
├── audit.rs               # Logs d'audit (partagé)
└── mod.rs                 # Exports des modules
```

## 🚀 Installation et Migration

### 1. Exécuter la Migration

```bash
# Migrer vers les DM enrichis
./scripts/run_dm_migration.sh

# Vérifier avec les tests
./scripts/test_dm_enrichis.sh
```

### 2. Compiler l'Application

```bash
cargo build --release
```

## 📡 API WebSocket DM

### Messages Supportés

#### Gestion des Conversations
```json
{
  "type": "create_dm_conversation",
  "data": {
    "user1Id": 123,
    "user2Id": 456
  }
}

{
  "type": "block_dm_conversation", 
  "data": {
    "conversationId": 789,
    "userId": 123,
    "block": true
  }
}

{
  "type": "list_dm_conversations",
  "data": {
    "userId": 123,
    "limit": 50
  }
}
```

#### Messages Enrichis
```json
{
  "type": "send_dm_message",
  "data": {
    "conversationId": 789,
    "userId": 123,
    "username": "alice",
    "content": "Salut! Comment ça va?",
    "parentId": null  // ou ID du message parent pour thread
  }
}

{
  "type": "edit_dm_message",
  "data": {
    "messageId": 456,
    "userId": 123,
    "newContent": "Message corrigé",
    "editReason": "Correction typo"
  }
}
```

#### Historique et Recherche
```json
{
  "type": "get_dm_history",
  "data": {
    "conversationId": 789,
    "userId": 123,
    "limit": 50,
    "beforeId": 999  // Pour pagination
  }
}

{
  "type": "get_pinned_dm_messages",
  "data": {
    "conversationId": 789,
    "userId": 123
  }
}
```

#### Réactions
```json
{
  "type": "add_dm_reaction",
  "data": {
    "messageId": 456,
    "userId": 123,
    "emoji": "😊"
  }
}

{
  "type": "remove_dm_reaction",
  "data": {
    "messageId": 456,
    "userId": 123,
    "emoji": "😊"
  }
}
```

#### Épinglage
```json
{
  "type": "pin_dm_message",
  "data": {
    "conversationId": 789,
    "messageId": 456,
    "userId": 123
  }
}

{
  "type": "unpin_dm_message",
  "data": {
    "conversationId": 789,
    "messageId": 456,
    "userId": 123
  }
}
```

#### Administration
```json
{
  "type": "get_dm_stats",
  "data": {
    "conversationId": 789,
    "userId": 123
  }
}

{
  "type": "get_dm_audit_logs",
  "data": {
    "conversationId": 789,
    "userId": 123,
    "limit": 50
  }
}
```

## 🔧 Utilisation Programmatique

### Créer une Conversation DM

```rust
use crate::hub::dm_enhanced;

// Créer ou récupérer une conversation DM
let conversation = dm_enhanced::get_or_create_dm_conversation(
    &hub, 
    user1_id, 
    user2_id
).await?;

println!("Conversation ID: {}", conversation.id);
```

### Envoyer un Message Enrichi

```rust
// Envoyer un message DM avec métadonnées
let message_id = dm_enhanced::send_dm_message(
    &hub,
    conversation_id,
    author_id,
    "alice",
    "Salut! @bob regarde ça 😊",
    None, // parent_message_id pour thread
    Some(json!({
        "type": "greeting",
        "priority": "normal",
        "has_mentions": true
    }))
).await?;
```

### Gérer les Réactions

```rust
use crate::hub::reactions;

// Ajouter une réaction (même système que les salons)
reactions::add_reaction(&hub, message_id, user_id, "👍").await?;

// Récupérer toutes les réactions
let reactions = reactions::get_message_reactions(&hub, message_id, user_id).await?;
```

### Épingler des Messages

```rust
// Épingler un message DM
dm_enhanced::pin_dm_message(
    &hub, 
    conversation_id, 
    message_id, 
    user_id, 
    true
).await?;

// Récupérer les messages épinglés
let pinned = dm_enhanced::fetch_pinned_dm_messages(
    &hub, 
    conversation_id, 
    user_id
).await?;
```

### Historique Paginé

```rust
// Récupérer l'historique avec pagination
let messages = dm_enhanced::fetch_dm_history(
    &hub,
    conversation_id,
    user_id,
    50,           // limit
    Some(last_message_id) // before_id pour pagination
).await?;
```

## 📊 Fonctionnalités Avancées

### 1. Système de Threads

```rust
// Envoyer une réponse dans un thread
let reply_id = dm_enhanced::send_dm_message(
    &hub,
    conversation_id,
    user_id,
    "bob",
    "Réponse dans le thread",
    Some(parent_message_id), // Crée un thread
    None
).await?;
```

### 2. Mentions Automatiques

```rust
// Les mentions @username sont automatiquement détectées
let message_id = dm_enhanced::send_dm_message(
    &hub,
    conversation_id,
    user_id,
    "alice",
    "Hey @bob, peux-tu regarder ça?", // Mention détectée automatiquement
    None,
    None
).await?;
```

### 3. Édition avec Historique

```rust
// Éditer un message avec raison
dm_enhanced::edit_dm_message(
    &hub,
    message_id,
    user_id,
    "Contenu corrigé",
    Some("Correction d'une typo")
).await?;
```

### 4. Blocage de Conversations

```rust
// Bloquer une conversation
dm_enhanced::block_dm_conversation(
    &hub,
    conversation_id,
    user_id,
    true // block = true
).await?;
```

### 5. Statistiques Complètes

```rust
// Obtenir les statistiques d'une conversation
let stats = dm_enhanced::get_dm_stats(&hub, conversation_id, user_id).await?;

println!("Messages: {}", stats.total_messages);
println!("Épinglés: {}", stats.pinned_messages);
println!("Threads: {}", stats.thread_messages);
println!("Réactions: {}", stats.total_reactions);
```

## 🔒 Sécurité et Permissions

### Contrôles d'Accès

- **Participation**: Seuls les 2 participants peuvent accéder à la conversation
- **Édition**: Seul l'auteur peut éditer ses messages
- **Épinglage**: Les deux participants peuvent épingler des messages
- **Blocage**: Chaque participant peut bloquer la conversation
- **Audit**: Tous les actions sont loggées

### Validation des Données

```rust
// Toutes les entrées sont validées
validate_user_id(user_id as i32)?;
validate_message_content(content, max_length)?;
validate_limit(limit)?;
```

## 📈 Performance

### Index Optimisés

```sql
-- Index pour les performances DM
CREATE INDEX idx_dm_conversations_user1 ON dm_conversations(user1_id);
CREATE INDEX idx_dm_conversations_user2 ON dm_conversations(user2_id);
CREATE INDEX idx_dm_conversations_updated_at ON dm_conversations(updated_at DESC);
```

### Requêtes Optimisées

```sql
-- Historique DM avec réactions et mentions
SELECT 
    m.*, u.username,
    json_agg(DISTINCT mr.emoji) as reactions,
    COUNT(DISTINCT mm.id) as mention_count
FROM messages m
JOIN users u ON u.id = m.author_id
LEFT JOIN message_reactions mr ON mr.message_id = m.id
LEFT JOIN message_mentions mm ON mm.message_id = m.id
WHERE m.conversation_id = $1
GROUP BY m.id, u.username
ORDER BY m.created_at DESC
LIMIT $2;
```

## 🧪 Tests et Validation

### Exécuter les Tests

```bash
# Tests complets des DM enrichis
./scripts/test_dm_enrichis.sh

# Tests spécifiques
./scripts/test_dm_enrichis.sh --test-reactions
./scripts/test_dm_enrichis.sh --test-threads
```

### Métriques de Test

- ✅ **Messages enrichis**: Métadonnées, threads, statuts
- ✅ **Réactions**: Ajout, suppression, statistiques
- ✅ **Épinglage**: Pin/unpin, récupération
- ✅ **Mentions**: Détection automatique, notifications
- ✅ **Édition**: Historique, raisons, logs
- ✅ **Blocage**: Permissions, états
- ✅ **Audit**: Logs complets, sécurité
- ✅ **Performance**: Requêtes complexes < 50ms

## 🎯 Exemples d'Usage

### Client JavaScript

```javascript
// WebSocket DM enrichi
const ws = new WebSocket('ws://localhost:8080/ws');

// Envoyer un message DM avec thread
ws.send(JSON.stringify({
    type: 'send_dm_message',
    data: {
        conversationId: 123,
        userId: 456,
        username: 'alice',
        content: 'Réponse dans le thread @bob',
        parentId: 789  // Thread
    }
}));

// Ajouter une réaction
ws.send(JSON.stringify({
    type: 'add_dm_reaction',
    data: {
        messageId: 999,
        userId: 456,
        emoji: '❤️'
    }
}));

// Épingler un message
ws.send(JSON.stringify({
    type: 'pin_dm_message',
    data: {
        conversationId: 123,
        messageId: 999,
        userId: 456
    }
}));
```

### Interface Utilisateur

```typescript
interface DmConversation {
    id: number;
    uuid: string;
    user1Id: number;
    user2Id: number;
    isBlocked: boolean;
    blockedBy?: number;
    createdAt: string;
    updatedAt: string;
}

interface EnhancedDmMessage {
    id: number;
    uuid: string;
    authorId: number;
    authorUsername: string;
    conversationId: number;
    content: string;
    parentMessageId?: number;
    threadCount: number;
    status: string;
    isEdited: boolean;
    editCount: number;
    isPinned: boolean;
    metadata: any;
    reactions: any[];
    mentionCount: number;
    createdAt: string;
    updatedAt: string;
    editedAt?: string;
}
```

## 🔧 Configuration

### Variables d'Environnement

```bash
# Base de données
DATABASE_URL="postgresql://user:pass@host/db"

# Limites DM
MAX_DM_MESSAGE_LENGTH=4000
MAX_DM_REACTIONS_PER_MESSAGE=50
MAX_DM_MENTIONS_PER_MESSAGE=10

# Rate limiting
DM_RATE_LIMIT_MESSAGES_PER_MINUTE=30
DM_RATE_LIMIT_REACTIONS_PER_MINUTE=60
```

### Configuration Rust

```rust
#[derive(Serialize, Deserialize)]
pub struct DmConfig {
    pub max_message_length: usize,
    pub max_reactions_per_message: usize,
    pub max_mentions_per_message: usize,
    pub enable_message_editing: bool,
    pub enable_message_pinning: bool,
    pub enable_conversation_blocking: bool,
}
```

## 🚀 Déploiement

### Checklist de Déploiement

- [ ] Migration de base de données exécutée
- [ ] Tests passés avec succès
- [ ] Application compilée sans erreur
- [ ] Configuration mise à jour
- [ ] Logs d'audit activés
- [ ] Monitoring en place

### Commandes de Déploiement

```bash
# 1. Migration
./scripts/run_dm_migration.sh

# 2. Tests
./scripts/test_dm_enrichis.sh

# 3. Compilation
cargo build --release

# 4. Démarrage
./target/release/veza-chat-server
```

## 📚 Documentation API

### Endpoints REST (Futurs)

```
GET    /api/dm/conversations          # Lister les conversations
POST   /api/dm/conversations          # Créer une conversation
GET    /api/dm/conversations/:id      # Détails d'une conversation
PATCH  /api/dm/conversations/:id      # Bloquer/débloquer

GET    /api/dm/conversations/:id/messages     # Historique
POST   /api/dm/conversations/:id/messages     # Envoyer message
PATCH  /api/dm/messages/:id                   # Éditer message
POST   /api/dm/messages/:id/pin               # Épingler
DELETE /api/dm/messages/:id/pin               # Désépingler

POST   /api/dm/messages/:id/reactions         # Ajouter réaction
DELETE /api/dm/messages/:id/reactions/:emoji  # Supprimer réaction

GET    /api/dm/conversations/:id/stats        # Statistiques
GET    /api/dm/conversations/:id/audit        # Logs d'audit
```

## 🎉 Conclusion

Les **DM Enrichis** apportent une **parité complète** avec les salons :

### ✅ Fonctionnalités Identiques
- Messages avec métadonnées et threads
- Système de réactions emoji
- Messages épinglés
- Mentions automatiques
- Édition avec historique
- Modération (blocage vs rôles)
- Logs d'audit complets
- Historique paginé avancé

### 🚀 Avantages Techniques
- **Architecture unifiée**: Même système pour DM et salons
- **Performance optimisée**: Index et requêtes optimisées
- **Sécurité renforcée**: Contrôles d'accès stricts
- **Extensibilité**: Facilement extensible

### 🎯 Résultat Final
**DM = Salons** en termes de fonctionnalités ! 🎉

Votre serveur de chat dispose maintenant d'un système de communication unifié et complet, prêt pour la production.

---

*Guide généré pour Veza Chat Server - DM Enrichis v1.0* 