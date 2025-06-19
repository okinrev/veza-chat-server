# Guide des Salons Enrichis - Veza Chat Server

## 🎯 Vue d'ensemble

Les salons ont été considérablement enrichis pour offrir une expérience équivalente aux messages directs avec des fonctionnalités avancées :

### ✨ Nouvelles fonctionnalités

#### 🏗️ **Gestion complète des salons**
- Création de salons avec propriétaire
- Gestion des membres avec rôles (owner, moderator, member)
- Salons publics/privés avec limite de membres
- Archive des salons

#### 📝 **Messages avancés**
- Messages avec threads (réponses)
- Messages épinglés
- Édition et historique des modifications
- Métadonnées personnalisées
- Statuts de messages (sent, edited, deleted)

#### 😊 **Système de réactions**
- Réactions emoji sur tous les messages
- Comptage en temps réel
- Limitations anti-spam (max 10 réactions/user/message)
- Emojis populaires et statistiques

#### 🔍 **Historique et recherche**
- Historique paginé avec UUID
- Filtrage par date/utilisateur
- Messages épinglés séparés
- Recherche dans le contenu

#### 📊 **Audit et logs**
- Logs complets de toutes les actions
- Événements de sécurité
- Détection d'activité suspecte
- Rapports d'activité périodiques
- Traces de modération

#### 🛡️ **Modération intégrée**
- Rôles et permissions
- Actions de modération (warn, mute, kick, ban)
- Durées temporaires
- Raisons obligatoires
- Historique des sanctions

## 🏛️ Architecture des modules

### 📁 Structure des fichiers

```
src/hub/
├── room_enhanced.rs     # Gestion complète des salons
├── reactions.rs         # Système de réactions
├── audit.rs            # Logs et audit de sécurité
├── websocket_handler.rs # Gestionnaire WebSocket enrichi
└── mod.rs              # Exports et intégration
```

### 🔗 Intégration avec la base de données

Utilise la nouvelle structure de base de données avec :
- `conversations` (salons et DM unifiés)
- `conversation_members` (membres avec rôles)
- `messages` (messages avec UUID et métadonnées)
- `message_reactions` (réactions emoji)
- `message_mentions` (système de mentions)
- `audit_logs` (historique des actions)
- `security_events` (événements de sécurité)

## 🚀 Utilisation

### 1. Création d'un salon

```rust
use crate::hub::room_enhanced;

let room = room_enhanced::create_room(
    &hub,
    owner_id,
    "Mon Salon",
    Some("Description du salon"),
    true,  // public
    Some(100)  // max 100 membres
).await?;
```

### 2. Envoi de message avec thread

```rust
let message_id = room_enhanced::send_room_message(
    &hub,
    room_id,
    author_id,
    "username",
    "Contenu du message",
    Some(parent_message_id),  // Réponse à un message
    Some(json!({"priority": "high"}))  // Métadonnées
).await?;
```

### 3. Ajout de réaction

```rust
use crate::hub::reactions;

reactions::add_reaction(&hub, message_id, user_id, "👍").await?;
```

### 4. Épinglage de message

```rust
room_enhanced::pin_message(&hub, room_id, message_id, user_id, true).await?;
```

### 5. Récupération de l'historique

```rust
let messages = room_enhanced::fetch_room_history(
    &hub,
    room_id,
    user_id,
    50,  // limite
    Some(before_message_id)  // pagination
).await?;
```

### 6. Logs d'audit

```rust
use crate::hub::audit;

// Logs automatiques pour toutes les actions
audit::log_member_change(&hub, room_id, "Salon Test", user_id, None, "joined", None).await?;

// Récupération des logs
let logs = audit::get_room_audit_logs(&hub, room_id, user_id, 100, None).await?;
```

## 📡 API WebSocket

### Messages supportés

#### Gestion des salons
```json
{
  "type": "join_room",
  "data": {
    "roomId": 123,
    "userId": 456
  }
}
```

#### Envoi de message
```json
{
  "type": "send_message",
  "data": {
    "roomId": 123,
    "userId": 456,
    "username": "alice",
    "content": "Hello world!",
    "parentId": 789  // optionnel pour thread
  }
}
```

#### Réactions
```json
{
  "type": "add_reaction",
  "data": {
    "messageId": 789,
    "userId": 456,
    "emoji": "👍"
  }
}
```

#### Épinglage
```json
{
  "type": "pin_message",
  "data": {
    "roomId": 123,
    "messageId": 789,
    "userId": 456
  }
}
```

#### Historique
```json
{
  "type": "get_history",
  "data": {
    "roomId": 123,
    "userId": 456,
    "limit": 50,
    "beforeId": 999  // optionnel pour pagination
  }
}
```

## 🔐 Sécurité et permissions

### Rôles disponibles
- **owner** : Toutes les permissions
- **moderator** : Modération + gestion des membres
- **member** : Envoi de messages

### Permissions par rôle

| Action | Member | Moderator | Owner |
|--------|--------|-----------|-------|
| Envoyer messages | ✅ | ✅ | ✅ |
| Réagir aux messages | ✅ | ✅ | ✅ |
| Épingler messages | ❌ | ✅ | ✅ |
| Supprimer messages | ❌ | ✅ | ✅ |
| Gérer membres | ❌ | ✅ | ✅ |
| Modifier salon | ❌ | ❌ | ✅ |
| Voir logs d'audit | ❌ | ✅ | ✅ |

### Rate limiting
- Messages : limite globale du hub
- Réactions : 10 réactions max par message par utilisateur
- Actions de modération : 100 actions/heure par modérateur

## 📈 Monitoring et statistiques

### Statistiques disponibles
- Nombre total de messages
- Membres actifs/inactifs
- Messages épinglés
- Actions de modération
- Événements de sécurité

### Détection d'anomalies
- Activité suspecte (trop d'actions en peu de temps)
- Patterns inhabituels de modération
- Tentatives d'abus des réactions

### Rapports d'activité
- Rapports quotidiens/hebdomadaires/mensuels
- Top utilisateurs par activité
- Actions par type
- Événements de sécurité

## 🔧 Configuration

### Variables d'environnement
```bash
# Limites de réactions
MAX_REACTIONS_PER_MESSAGE_PER_USER=10

# Détection d'anomalies
SUSPICIOUS_ACTIVITY_THRESHOLD=50
SECURITY_MONITORING_ENABLED=true

# Rate limiting
ROOM_MESSAGE_RATE_LIMIT=60  # messages par minute
MODERATION_ACTION_RATE_LIMIT=100  # actions par heure
```

### Base de données
Assurez-vous que les migrations sont appliquées :
```bash
./scripts/run_migration.sh
```

## 🚨 Gestion des erreurs

### Erreurs courantes
- `unauthorized` : Permissions insuffisantes
- `rate_limit_exceeded` : Trop de requêtes
- `room_full` : Salon plein
- `already_member` : Déjà membre du salon
- `message_not_found` : Message inexistant

### Logs d'erreur
Tous les événements sont tracés avec tracing :
```rust
tracing::error!(room_id = %room_id, user_id = %user_id, "❌ Erreur lors de l'action");
```

## 🔮 Roadmap

### Fonctionnalités prévues
- [ ] Notification push pour mentions
- [ ] Messages programmés
- [ ] Sondages intégrés
- [ ] Partage de fichiers
- [ ] Appels vocaux/vidéo
- [ ] Intégration avec bots
- [ ] Recherche full-text
- [ ] Archivage automatique
- [ ] Backup/restore des salons

### Améliorations techniques
- [ ] Cache Redis pour les messages fréquents
- [ ] Clustering pour la scalabilité
- [ ] Métriques Prometheus
- [ ] Tests d'intégration complets
- [ ] Documentation OpenAPI

## 📞 Support

Pour toute question ou problème :
1. Consultez les logs : `tail -f veza-chat.log`
2. Vérifiez la base de données : tables `audit_logs` et `security_events`
3. Utilisez les outils de diagnostic intégrés

---

**Version** : 1.0.0  
**Dernière mise à jour** : 2024-12-19 