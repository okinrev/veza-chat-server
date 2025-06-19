# 🌐 API WebSocket - Documentation Complète

Cette documentation détaille l'API WebSocket du serveur de chat Veza, essentielle pour l'intégration avec des frontends React et backends Go.

## 📡 Connexion WebSocket

### URL de Connexion
```
ws://localhost:8080/ws
wss://your-domain.com/ws  # Production avec SSL
```

### Headers Optionnels
```http
Authorization: Bearer <jwt_token>
User-Agent: YourApp/1.0
X-Client-Version: 1.0.0
```

## 🔐 Authentification

### 1. Authentification par Token JWT
```json
{
    "type": "authenticate",
    "data": {
        "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
    }
}
```

**Réponse Succès :**
```json
{
    "type": "auth_success",
    "data": {
        "user_id": 123,
        "username": "john_doe",
        "role": "user",
        "session_id": "session_uuid",
        "server_time": "2024-01-01T12:00:00Z"
    }
}
```

**Réponse Erreur :**
```json
{
    "type": "auth_error",
    "data": {
        "code": "INVALID_TOKEN",
        "message": "Token JWT invalide ou expiré",
        "retry_after": null
    }
}
```

## 💬 Messages de Salon (Channels)

### Rejoindre un Salon
```json
{
    "type": "join_room",
    "data": {
        "room_id": 456
    }
}
```

**Réponse :**
```json
{
    "type": "room_joined",
    "data": {
        "room_id": 456,
        "room_name": "General",
        "member_count": 25,
        "user_role": "member",
        "is_public": true,
        "last_message_id": 789
    }
}
```

### Envoyer un Message
```json
{
    "type": "send_message",
    "data": {
        "room_id": 456,
        "content": "Hello everyone! 👋",
        "parent_id": null,  // Pour réponse/thread
        "metadata": {
            "client_id": "local_uuid_for_deduplication"
        }
    }
}
```

**Réponse :**
```json
{
    "type": "message_sent",
    "data": {
        "message_id": 789,
        "room_id": 456,
        "author_id": 123,
        "username": "john_doe",
        "content": "Hello everyone! 👋",
        "parent_id": null,
        "thread_count": 0,
        "is_pinned": false,
        "created_at": "2024-01-01T12:00:00Z",
        "reactions": [],
        "mentions": []
    }
}
```

### Diffusion aux Membres du Salon
Tous les membres du salon reçoivent :
```json
{
    "type": "room_message",
    "data": {
        "message_id": 789,
        "room_id": 456,
        "room_name": "General",
        "author_id": 123,
        "username": "john_doe",
        "content": "Hello everyone! 👋",
        "parent_id": null,
        "thread_count": 0,
        "is_pinned": false,
        "is_edited": false,
        "created_at": "2024-01-01T12:00:00Z",
        "reactions": [],
        "mention_count": 0
    }
}
```

### Récupérer l'Historique
```json
{
    "type": "get_history",
    "data": {
        "room_id": 456,
        "limit": 50,
        "before_id": null  // Pour pagination
    }
}
```

**Réponse :**
```json
{
    "type": "room_history",
    "data": {
        "room_id": 456,
        "messages": [
            {
                "id": 789,
                "author_id": 123,
                "username": "john_doe",
                "content": "Hello everyone! 👋",
                "parent_id": null,
                "thread_count": 0,
                "is_pinned": false,
                "is_edited": false,
                "created_at": "2024-01-01T12:00:00Z",
                "reactions": [],
                "mention_count": 0
            }
        ],
        "has_more": true,
        "total_count": 1250
    }
}
```

### Épingler/Désépingler un Message
```json
{
    "type": "pin_message",
    "data": {
        "room_id": 456,
        "message_id": 789,
        "pin": true
    }
}
```

### Quitter un Salon
```json
{
    "type": "leave_room",
    "data": {
        "room_id": 456
    }
}
```

## 📱 Messages Directs (DM)

### Créer/Récupérer une Conversation DM
```json
{
    "type": "create_dm",
    "data": {
        "user1_id": 123,
        "user2_id": 456
    }
}
```

**Réponse :**
```json
{
    "type": "dm_created",
    "data": {
        "conversation_id": 789,
        "user1_id": 123,
        "user2_id": 456,
        "is_blocked": false,
        "created_at": "2024-01-01T12:00:00Z"
    }
}
```

### Envoyer un Message Direct
```json
{
    "type": "send_dm",
    "data": {
        "conversation_id": 789,
        "content": "Hello! How are you?",
        "parent_id": null,
        "metadata": {
            "client_id": "local_uuid"
        }
    }
}
```

**Diffusion aux Participants :**
```json
{
    "type": "dm_message",
    "data": {
        "message_id": 1001,
        "conversation_id": 789,
        "author_id": 123,
        "username": "john_doe",
        "content": "Hello! How are you?",
        "parent_id": null,
        "thread_count": 0,
        "is_pinned": false,
        "is_edited": false,
        "created_at": "2024-01-01T12:00:00Z"
    }
}
```

### Bloquer/Débloquer une Conversation
```json
{
    "type": "block_dm",
    "data": {
        "conversation_id": 789,
        "block": true
    }
}
```

### Lister les Conversations DM
```json
{
    "type": "list_dms",
    "data": {
        "limit": 20
    }
}
```

**Réponse :**
```json
{
    "type": "dm_list",
    "data": {
        "conversations": [
            {
                "conversation_id": 789,
                "other_user": {
                    "user_id": 456,
                    "username": "jane_doe",
                    "is_online": true,
                    "last_seen": "2024-01-01T11:55:00Z"
                },
                "last_message": {
                    "content": "Hello! How are you?",
                    "author_id": 123,
                    "created_at": "2024-01-01T12:00:00Z"
                },
                "unread_count": 2,
                "is_blocked": false
            }
        ]
    }
}
```

## 🎭 Réactions

### Ajouter une Réaction
```json
{
    "type": "add_reaction",
    "data": {
        "message_id": 789,
        "emoji": "👍"
    }
}
```

**Diffusion :**
```json
{
    "type": "reaction_added",
    "data": {
        "message_id": 789,
        "user_id": 123,
        "username": "john_doe",
        "emoji": "👍",
        "timestamp": "2024-01-01T12:00:00Z"
    }
}
```

### Supprimer une Réaction
```json
{
    "type": "remove_reaction",
    "data": {
        "message_id": 789,
        "emoji": "👍"
    }
}
```

### Récupérer les Réactions
```json
{
    "type": "get_reactions",
    "data": {
        "message_id": 789
    }
}
```

**Réponse :**
```json
{
    "type": "message_reactions",
    "data": {
        "message_id": 789,
        "total_reactions": 5,
        "reactions": [
            {
                "emoji": "👍",
                "count": 3,
                "users": [
                    {"user_id": 123, "username": "john_doe"},
                    {"user_id": 456, "username": "jane_doe"},
                    {"user_id": 789, "username": "bob_smith"}
                ]
            },
            {
                "emoji": "❤️",
                "count": 2,
                "users": [
                    {"user_id": 123, "username": "john_doe"},
                    {"user_id": 456, "username": "jane_doe"}
                ]
            }
        ]
    }
}
```

## 👥 Présence et Statut

### Mise à Jour du Statut
```json
{
    "type": "update_status",
    "data": {
        "status": "online",  // online, away, busy, invisible
        "message": "Working on the project"
    }
}
```

### Notification de Présence
```json
{
    "type": "user_presence",
    "data": {
        "user_id": 456,
        "username": "jane_doe",
        "status": "online",
        "message": "Available",
        "last_seen": "2024-01-01T12:00:00Z",
        "current_room": "General"
    }
}
```

## 🔧 Administration et Modération

### Obtenir les Statistiques d'un Salon
```json
{
    "type": "get_room_stats",
    "data": {
        "room_id": 456
    }
}
```

### Obtenir les Logs d'Audit
```json
{
    "type": "get_audit_logs",
    "data": {
        "room_id": 456,
        "limit": 50
    }
}
```

## 📊 Événements Système

### Heartbeat/Ping
```json
{
    "type": "ping",
    "data": {
        "timestamp": "2024-01-01T12:00:00Z"
    }
}
```

**Réponse Automatique :**
```json
{
    "type": "pong",
    "data": {
        "timestamp": "2024-01-01T12:00:00Z",
        "server_time": "2024-01-01T12:00:00Z"
    }
}
```

### Déconnexion Gracieuse
```json
{
    "type": "disconnect",
    "data": {
        "reason": "User logout"
    }
}
```

## ❌ Gestion d'Erreurs

### Format d'Erreur Standard
```json
{
    "type": "error",
    "data": {
        "code": "RATE_LIMIT_EXCEEDED",
        "message": "Trop de messages envoyés",
        "severity": "medium",
        "retry_after": 30,
        "details": {
            "current_rate": 65,
            "limit": 60,
            "window": 60
        }
    }
}
```

### Codes d'Erreur Principaux

| Code | Description | Action Recommandée |
|------|-------------|-------------------|
| `INVALID_TOKEN` | Token JWT invalide | Rafraîchir le token |
| `RATE_LIMIT_EXCEEDED` | Limite de débit dépassée | Attendre retry_after |
| `ROOM_NOT_FOUND` | Salon inexistant | Vérifier l'ID du salon |
| `PERMISSION_DENIED` | Permissions insuffisantes | Vérifier les droits |
| `MESSAGE_TOO_LONG` | Message trop long | Réduire la taille |
| `USER_BLOCKED` | Utilisateur bloqué | Informer l'utilisateur |
| `CONVERSATION_BLOCKED` | Conversation bloquée | Empêcher l'envoi |

## 🔄 Flux d'Intégration Type

### 1. Frontend React
```javascript
class ChatWebSocket {
    constructor(token) {
        this.ws = new WebSocket('ws://localhost:8080/ws');
        this.setupEventHandlers();
        this.authenticate(token);
    }
    
    setupEventHandlers() {
        this.ws.onopen = () => console.log('Connected');
        this.ws.onmessage = (event) => {
            const message = JSON.parse(event.data);
            this.handleMessage(message);
        };
        this.ws.onerror = (error) => console.error('WebSocket error:', error);
        this.ws.onclose = () => this.reconnect();
    }
    
    authenticate(token) {
        this.send('authenticate', { token });
    }
    
    joinRoom(roomId) {
        this.send('join_room', { room_id: roomId });
    }
    
    sendMessage(roomId, content) {
        this.send('send_message', {
            room_id: roomId,
            content,
            metadata: { client_id: generateUUID() }
        });
    }
    
    send(type, data) {
        this.ws.send(JSON.stringify({ type, data }));
    }
}
```

### 2. Backend Go (Monitoring)
```go
type ChatMonitor struct {
    conn *websocket.Conn
    done chan struct{}
}

func (m *ChatMonitor) Connect(token string) error {
    conn, err := websocket.Dial("ws://localhost:8080/ws", "", "http://localhost/")
    if err != nil {
        return err
    }
    m.conn = conn
    
    // Authentification
    authMsg := map[string]interface{}{
        "type": "authenticate",
        "data": map[string]string{"token": token},
    }
    return websocket.JSON.Send(m.conn, authMsg)
}

func (m *ChatMonitor) ListenForEvents() {
    for {
        select {
        case <-m.done:
            return
        default:
            var message map[string]interface{}
            if err := websocket.JSON.Receive(m.conn, &message); err != nil {
                log.Printf("Error receiving message: %v", err)
                continue
            }
            m.handleMessage(message)
        }
    }
}
```

Cette API WebSocket fournit une interface complète pour toutes les fonctionnalités de chat temps réel, optimisée pour l'intégration avec des applications modernes. 