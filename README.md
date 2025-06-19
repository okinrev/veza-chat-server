# Veza Chat Server

Serveur de chat WebSocket haute performance écrit en Rust avec fonctionnalités avancées.

## 🚀 Fonctionnalités

### Communication en temps réel
- **Salons de chat** - Salons publics et privés avec gestion des membres
- **Messages directs** - Conversations privées entre utilisateurs
- **WebSocket** - Communication en temps réel bidirectionnelle

### Fonctionnalités avancées
- **Système de réactions** - Réactions emoji sur tous les messages
- **Messages épinglés** - Épinglage dans les salons et conversations DM
- **Threads de discussion** - Réponses et discussions organisées
- **Mentions utilisateur** - Système de mentions @username
- **Édition de messages** - Modification des messages avec historique

### Sécurité et modération
- **Authentification JWT** - Tokens sécurisés avec refresh
- **Rate limiting** - Protection contre le spam
- **Audit complet** - Logs de toutes les actions
- **Modération intégrée** - Blocage, sanctions, signalements
- **Filtrage de contenu** - Protection contre le contenu inapproprié

### Administration
- **Statistiques temps réel** - Métriques de performance
- **Gestion des permissions** - Système de rôles flexible
- **Monitoring** - Surveillance et alertes
- **Cache Redis** - Performance optimisée (optionnel)

## 🏗️ Architecture

```
src/
├── hub/                    # Hub central de chat
│   ├── common.rs          # Structures communes
│   ├── channels.rs        # Gestion des salons
│   ├── direct_messages.rs # Messages directs
│   ├── reactions.rs       # Système de réactions
│   ├── audit.rs          # Audit et logs
│   ├── channel_websocket.rs      # WebSocket salons
│   └── direct_messages_websocket.rs # WebSocket DM
├── auth.rs               # Authentification
├── cache.rs              # Système de cache
├── config.rs             # Configuration
├── error.rs              # Gestion d'erreurs
├── security.rs           # Sécurité et validation
├── moderation.rs         # Système de modération
└── ...
```

## 🛠️ Installation

### Prérequis
- **Rust** 1.70+
- **PostgreSQL** 14+
- **Redis** 6+ (optionnel, pour le cache)

### Configuration

1. **Variables d'environnement**
```bash
cp .env.example .env
# Éditer .env avec vos paramètres
```

2. **Base de données**
```bash
# Créer la base de données
createdb veza_chat

# Exécuter les migrations
./scripts/database/run_migration.sh
```

### Compilation

```bash
# Mode développement
cargo run

# Mode production
cargo build --release
./target/release/chat-server
```

## 📊 Configuration

Le serveur utilise un fichier de configuration TOML flexible :

```toml
[server]
bind_addr = "127.0.0.1:8080"
environment = "development"

[database]
url = "postgresql://user:pass@localhost/veza_chat"
max_connections = 10

[security]
jwt_secret = "your-secret-key"
jwt_access_duration = "15m"

[limits]
max_message_length = 2000
max_connections_per_user = 5
```

## 🧪 Tests

```bash
# Tests unitaires
cargo test

# Tests d'intégration
./scripts/testing/test_dm_enrichis.sh
./scripts/testing/test_salons_enrichis.sh
```

## 🚀 Déploiement

```bash
# Déploiement automatique
./scripts/deploy.sh

# Ou manuel
cargo build --release
./target/release/chat-server --config production.toml
```

## 📡 API WebSocket

### Connexion
```javascript
const ws = new WebSocket('ws://localhost:8080/ws');
```

### Messages salon
```json
{
  "type": "join_room",
  "data": { "room_id": 123 }
}

{
  "type": "send_message",
  "data": {
    "room_id": 123,
    "content": "Hello world!",
    "parent_id": null
  }
}
```

### Messages directs
```json
{
  "type": "create_dm",
  "data": { "user1_id": 1, "user2_id": 2 }
}

{
  "type": "send_dm",
  "data": {
    "conversation_id": 456,
    "content": "Message privé"
  }
}
```

## 🛡️ Sécurité

- **HTTPS/WSS** en production
- **Validation stricte** des entrées
- **Rate limiting** par utilisateur
- **Audit logs** complets
- **Filtrage de contenu** automatique
- **Sessions sécurisées** avec timeout

## 📈 Performance

- **Architecture async** avec Tokio
- **Pool de connexions** PostgreSQL optimisé
- **Cache Redis** pour les données fréquentes
- **Compression WebSocket** (optionnelle)
- **Metrics Prometheus** intégrées

## 🤝 Contribution

1. Fork le projet
2. Créer une branche (`git checkout -b feature/nouvelle-fonctionnalite`)
3. Commit (`git commit -m 'Ajout nouvelle fonctionnalité'`)
4. Push (`git push origin feature/nouvelle-fonctionnalite`)
5. Ouvrir une Pull Request

## 📄 Licence

MIT License - voir le fichier [LICENSE](LICENSE) pour plus de détails.

## 🔗 Liens utiles

- **Documentation API** : `/docs` (en développement)
- **Monitoring** : `/metrics` (Prometheus)
- **Health Check** : `/health`

---

Développé avec ❤️ par l'équipe Veza 