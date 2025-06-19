# 🔗 API REST - Documentation Complète

**Version :** 0.2.0  
**Dernière mise à jour :** $(date +"%Y-%m-%d")

## 📋 Vue d'Ensemble

L'API REST du serveur de chat Veza fournit une interface HTTP complète pour toutes les opérations de chat. Cette API est idéale pour les intégrations backend, les webhooks, et les opérations batch.

## 🔐 Authentification

### **Token JWT**
Toutes les requêtes doivent inclure un token JWT valide dans le header `Authorization`.

```http
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### **Obtenir un Token**

#### `POST /api/v1/auth/login`
```http
POST /api/v1/auth/login
Content-Type: application/json

{
  "username": "john_doe",
  "password": "secure_password123"
}
```

**Réponse :**
```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "f4a2c8e1-8b5d-4c9e-9f2a-1e3d5c7b9a0f",
    "expires_in": 900,
    "user": {
      "id": 123,
      "username": "john_doe",
      "email": "john@example.com",
      "role": "user",
      "created_at": "2024-01-01T00:00:00Z"
    }
  }
}
```

#### `POST /api/v1/auth/refresh`
```http
POST /api/v1/auth/refresh
Content-Type: application/json

{
  "refresh_token": "f4a2c8e1-8b5d-4c9e-9f2a-1e3d5c7b9a0f"
}
```

#### `POST /api/v1/auth/logout`
```http
POST /api/v1/auth/logout
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

## 🏠 Gestion des Salons

### **Lister les Salons**

#### `GET /api/v1/rooms`
```http
GET /api/v1/rooms?limit=20&offset=0&filter=public
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Paramètres :**
- `limit` (optionnel) : Nombre de salons à retourner (défaut: 50, max: 100)
- `offset` (optionnel) : Décalage pour la pagination (défaut: 0)
- `filter` (optionnel) : `public`, `private`, `joined`, `owned`
- `search` (optionnel) : Recherche par nom de salon

**Réponse :**
```json
{
  "success": true,
  "data": {
    "rooms": [
      {
        "id": 1,
        "uuid": "550e8400-e29b-41d4-a716-446655440000",
        "name": "General",
        "description": "Salon de discussion générale",
        "is_public": true,
        "owner_id": 1,
        "member_count": 25,
        "unread_count": 3,
        "last_activity": "2024-01-15T12:30:00Z",
        "created_at": "2024-01-01T00:00:00Z",
        "updated_at": "2024-01-15T12:30:00Z"
      }
    ],
    "total": 1,
    "has_more": false
  }
}
```

### **Créer un Salon**

#### `POST /api/v1/rooms`
```http
POST /api/v1/rooms
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "name": "Équipe Dev",
  "description": "Discussions de l'équipe développement",
  "is_public": false,
  "max_members": 50
}
```

**Réponse :**
```json
{
  "success": true,
  "data": {
    "id": 15,
    "uuid": "123e4567-e89b-12d3-a456-426614174000",
    "name": "Équipe Dev",
    "description": "Discussions de l'équipe développement",
    "is_public": false,
    "owner_id": 123,
    "member_count": 1,
    "max_members": 50,
    "created_at": "2024-01-15T14:20:00Z",
    "updated_at": "2024-01-15T14:20:00Z"
  }
}
```

### **Obtenir un Salon**

#### `GET /api/v1/rooms/{room_id}`
```http
GET /api/v1/rooms/15
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### **Modifier un Salon**

#### `PUT /api/v1/rooms/{room_id}`
```http
PUT /api/v1/rooms/15
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "name": "Dev Team - Nouveau nom",
  "description": "Discussions mises à jour"
}
```

### **Supprimer un Salon**

#### `DELETE /api/v1/rooms/{room_id}`
```http
DELETE /api/v1/rooms/15
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

## 👥 Gestion des Membres

### **Lister les Membres d'un Salon**

#### `GET /api/v1/rooms/{room_id}/members`
```http
GET /api/v1/rooms/1/members?limit=50&role=all
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Paramètres :**
- `limit` (optionnel) : Nombre de membres (défaut: 50)
- `role` (optionnel) : `owner`, `moderator`, `member`, `all`

**Réponse :**
```json
{
  "success": true,
  "data": {
    "members": [
      {
        "user_id": 123,
        "username": "john_doe",
        "role": "owner",
        "joined_at": "2024-01-01T00:00:00Z",
        "is_online": true,
        "last_seen": "2024-01-15T14:30:00Z"
      },
      {
        "user_id": 456,
        "username": "jane_smith",
        "role": "member",
        "joined_at": "2024-01-05T10:15:00Z",
        "is_online": false,
        "last_seen": "2024-01-15T09:22:00Z"
      }
    ],
    "total": 25
  }
}
```

### **Ajouter un Membre**

#### `POST /api/v1/rooms/{room_id}/members`
```http
POST /api/v1/rooms/1/members
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "user_id": 789,
  "role": "member"
}
```

### **Modifier le Rôle d'un Membre**

#### `PUT /api/v1/rooms/{room_id}/members/{user_id}`
```http
PUT /api/v1/rooms/1/members/456
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "role": "moderator"
}
```

### **Retirer un Membre**

#### `DELETE /api/v1/rooms/{room_id}/members/{user_id}`
```http
DELETE /api/v1/rooms/1/members/456
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

## 💬 Gestion des Messages

### **Lister les Messages d'un Salon**

#### `GET /api/v1/rooms/{room_id}/messages`
```http
GET /api/v1/rooms/1/messages?limit=50&before_id=1000&include_threads=true
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Paramètres :**
- `limit` (optionnel) : Nombre de messages (défaut: 50, max: 100)
- `before_id` (optionnel) : ID du message pour pagination
- `after_id` (optionnel) : ID du message pour pagination inverse
- `include_threads` (optionnel) : Inclure les réponses (défaut: false)
- `pinned_only` (optionnel) : Seulement les messages épinglés

**Réponse :**
```json
{
  "success": true,
  "data": {
    "messages": [
      {
        "id": 1001,
        "uuid": "msg-550e8400-e29b-41d4-a716-446655440000",
        "author_id": 123,
        "username": "john_doe",
        "content": "Salut tout le monde ! 👋",
        "parent_message_id": null,
        "thread_count": 2,
        "is_pinned": false,
        "is_edited": false,
        "edit_count": 0,
        "reactions": {
          "👍": {
            "count": 3,
            "users": [
              {"user_id": 456, "username": "jane_smith"},
              {"user_id": 789, "username": "bob_wilson"}
            ]
          }
        },
        "mentions": [456],
        "metadata": {
          "client": "web",
          "ip_address": "192.168.1.100"
        },
        "created_at": "2024-01-15T12:30:00Z",
        "updated_at": "2024-01-15T12:30:00Z"
      }
    ],
    "has_more": true,
    "total_count": 1250
  }
}
```

### **Envoyer un Message**

#### `POST /api/v1/rooms/{room_id}/messages`
```http
POST /api/v1/rooms/1/messages
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "content": "Voici un nouveau message avec @jane_smith mention",
  "parent_message_id": null,
  "metadata": {
    "source": "api",
    "priority": "normal"
  }
}
```

**Réponse :**
```json
{
  "success": true,
  "data": {
    "id": 1002,
    "uuid": "msg-123e4567-e89b-12d3-a456-426614174000",
    "author_id": 123,
    "username": "john_doe",
    "content": "Voici un nouveau message avec @jane_smith mention",
    "parent_message_id": null,
    "thread_count": 0,
    "is_pinned": false,
    "is_edited": false,
    "mentions": [456],
    "created_at": "2024-01-15T14:35:00Z"
  }
}
```

### **Modifier un Message**

#### `PUT /api/v1/messages/{message_id}`
```http
PUT /api/v1/messages/1002
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "content": "Message modifié avec nouveau contenu",
  "edit_reason": "Correction de typo"
}
```

### **Supprimer un Message**

#### `DELETE /api/v1/messages/{message_id}`
```http
DELETE /api/v1/messages/1002
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### **Épingler/Désépingler un Message**

#### `POST /api/v1/messages/{message_id}/pin`
```http
POST /api/v1/messages/1001/pin
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "pinned": true
}
```

## 📱 Messages Directs

### **Lister les Conversations**

#### `GET /api/v1/conversations`
```http
GET /api/v1/conversations?limit=20&include_last_message=true
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Réponse :**
```json
{
  "success": true,
  "data": {
    "conversations": [
      {
        "id": 501,
        "uuid": "conv-550e8400-e29b-41d4-a716-446655440000",
        "other_user": {
          "id": 456,
          "username": "jane_smith",
          "is_online": true,
          "last_seen": "2024-01-15T14:30:00Z"
        },
        "last_message": {
          "id": 2001,
          "content": "Merci pour l'info !",
          "author_id": 456,
          "created_at": "2024-01-15T14:25:00Z"
        },
        "unread_count": 2,
        "is_blocked": false,
        "created_at": "2024-01-10T09:00:00Z",
        "updated_at": "2024-01-15T14:25:00Z"
      }
    ],
    "total": 5
  }
}
```

### **Créer/Récupérer une Conversation**

#### `POST /api/v1/conversations`
```http
POST /api/v1/conversations
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "user_id": 789
}
```

### **Messages d'une Conversation**

#### `GET /api/v1/conversations/{conversation_id}/messages`
```http
GET /api/v1/conversations/501/messages?limit=50&before_id=2000
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### **Envoyer un Message Direct**

#### `POST /api/v1/conversations/{conversation_id}/messages`
```http
POST /api/v1/conversations/501/messages
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "content": "Salut ! Comment ça va ?",
  "parent_message_id": null
}
```

### **Bloquer/Débloquer une Conversation**

#### `POST /api/v1/conversations/{conversation_id}/block`
```http
POST /api/v1/conversations/501/block
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "blocked": true
}
```

## 🎭 Réactions

### **Ajouter une Réaction**

#### `POST /api/v1/messages/{message_id}/reactions`
```http
POST /api/v1/messages/1001/reactions
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "emoji": "👍"
}
```

### **Supprimer une Réaction**

#### `DELETE /api/v1/messages/{message_id}/reactions/{emoji}`
```http
DELETE /api/v1/messages/1001/reactions/👍
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### **Lister les Réactions**

#### `GET /api/v1/messages/{message_id}/reactions`
```http
GET /api/v1/messages/1001/reactions
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Réponse :**
```json
{
  "success": true,
  "data": {
    "message_id": 1001,
    "total_reactions": 5,
    "reactions": [
      {
        "emoji": "👍",
        "count": 3,
        "users": [
          {"user_id": 456, "username": "jane_smith", "created_at": "2024-01-15T12:35:00Z"},
          {"user_id": 789, "username": "bob_wilson", "created_at": "2024-01-15T12:36:00Z"}
        ]
      },
      {
        "emoji": "❤️",
        "count": 2,
        "users": [
          {"user_id": 123, "username": "john_doe", "created_at": "2024-01-15T12:40:00Z"}
        ]
      }
    ]
  }
}
```

## 📁 Upload de Fichiers

### **Upload d'un Fichier**

#### `POST /api/v1/files/upload`
```http
POST /api/v1/files/upload
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: multipart/form-data

--boundary123
Content-Disposition: form-data; name="file"; filename="document.pdf"
Content-Type: application/pdf

[binary file data]
--boundary123
Content-Disposition: form-data; name="room_id"

1
--boundary123
Content-Disposition: form-data; name="description"

Document important
--boundary123--
```

**Réponse :**
```json
{
  "success": true,
  "data": {
    "file_id": 101,
    "filename": "document.pdf",
    "original_filename": "document.pdf",
    "size": 245760,
    "mime_type": "application/pdf",
    "url": "/api/v1/files/101/download",
    "thumbnail_url": "/api/v1/files/101/thumbnail",
    "uploaded_at": "2024-01-15T14:45:00Z"
  }
}
```

### **Télécharger un Fichier**

#### `GET /api/v1/files/{file_id}/download`
```http
GET /api/v1/files/101/download
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### **Supprimer un Fichier**

#### `DELETE /api/v1/files/{file_id}`
```http
DELETE /api/v1/files/101
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

## 👤 Gestion des Utilisateurs

### **Profil Utilisateur**

#### `GET /api/v1/users/me`
```http
GET /api/v1/users/me
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### `PUT /api/v1/users/me`
```http
PUT /api/v1/users/me
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "username": "nouveau_nom",
  "email": "nouveau@email.com",
  "status_message": "En développement"
}
```

### **Rechercher des Utilisateurs**

#### `GET /api/v1/users/search`
```http
GET /api/v1/users/search?q=john&limit=10
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### **Obtenir un Utilisateur**

#### `GET /api/v1/users/{user_id}`
```http
GET /api/v1/users/456
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

## 📊 Statistiques et Administration

### **Statistiques d'un Salon**

#### `GET /api/v1/rooms/{room_id}/stats`
```http
GET /api/v1/rooms/1/stats?period=7d
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Réponse :**
```json
{
  "success": true,
  "data": {
    "room_id": 1,
    "period": "7d",
    "message_count": 1250,
    "active_users": 18,
    "new_members": 3,
    "pinned_messages": 5,
    "reactions_count": 89,
    "peak_activity": {
      "date": "2024-01-14",
      "hour": 15,
      "message_count": 45
    },
    "top_contributors": [
      {"user_id": 123, "username": "john_doe", "message_count": 127},
      {"user_id": 456, "username": "jane_smith", "message_count": 89}
    ]
  }
}
```

### **Logs d'Audit**

#### `GET /api/v1/rooms/{room_id}/audit`
```http
GET /api/v1/rooms/1/audit?limit=50&action=message_deleted
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Réponse :**
```json
{
  "success": true,
  "data": {
    "logs": [
      {
        "id": 5001,
        "action": "message_deleted",
        "details": {
          "message_id": 999,
          "content": "Message supprimé",
          "reason": "Contenu inapproprié"
        },
        "user_id": 123,
        "moderator_id": 456,
        "ip_address": "192.168.1.100",
        "created_at": "2024-01-15T13:20:00Z"
      }
    ],
    "total": 125
  }
}
```

### **Statistiques Globales du Serveur**

#### `GET /api/v1/admin/stats`
```http
GET /api/v1/admin/stats
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

## 🔔 Webhooks

### **Configurer un Webhook**

#### `POST /api/v1/webhooks`
```http
POST /api/v1/webhooks
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "url": "https://your-app.com/webhook/chat",
  "events": ["message_sent", "user_joined", "user_left"],
  "secret": "webhook_secret_key",
  "room_id": 1
}
```

### **Lister les Webhooks**

#### `GET /api/v1/webhooks`
```http
GET /api/v1/webhooks
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### **Tester un Webhook**

#### `POST /api/v1/webhooks/{webhook_id}/test`
```http
POST /api/v1/webhooks/201/test
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

## ❌ Gestion d'Erreurs

### **Format d'Erreur Standard**
```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "Les données fournies ne sont pas valides",
    "details": {
      "field": "content",
      "reason": "Le message est trop long",
      "max_length": 2000,
      "actual_length": 2150
    },
    "timestamp": "2024-01-15T14:50:00Z",
    "request_id": "req_123456789"
  }
}
```

### **Codes de Statut HTTP**

| Code | Signification | Description |
|------|---------------|-------------|
| `200` | OK | Requête réussie |
| `201` | Created | Ressource créée |
| `204` | No Content | Opération réussie sans contenu |
| `400` | Bad Request | Données de requête invalides |
| `401` | Unauthorized | Token manquant ou invalide |
| `403` | Forbidden | Permissions insuffisantes |
| `404` | Not Found | Ressource non trouvée |
| `409` | Conflict | Conflit de données |
| `422` | Unprocessable Entity | Données valides mais non traitables |
| `429` | Too Many Requests | Rate limiting dépassé |
| `500` | Internal Server Error | Erreur serveur |

### **Codes d'Erreur Spécifiques**

| Code | Description |
|------|-------------|
| `INVALID_TOKEN` | Token JWT invalide ou expiré |
| `RATE_LIMIT_EXCEEDED` | Limite de taux dépassée |
| `ROOM_NOT_FOUND` | Salon inexistant |
| `MESSAGE_TOO_LONG` | Message trop long |
| `PERMISSION_DENIED` | Permissions insuffisantes |
| `USER_BLOCKED` | Utilisateur bloqué |
| `VALIDATION_FAILED` | Validation des données échouée |
| `RESOURCE_CONFLICT` | Conflit de ressource |

## 📚 Exemples d'Intégration

### **Client Python Simple**

```python
import requests
import json

class VezaChatAPI:
    def __init__(self, base_url, username, password):
        self.base_url = base_url
        self.session = requests.Session()
        self.token = self._login(username, password)
        self.session.headers.update({
            'Authorization': f'Bearer {self.token}',
            'Content-Type': 'application/json'
        })
    
    def _login(self, username, password):
        response = self.session.post(f'{self.base_url}/auth/login', json={
            'username': username,
            'password': password
        })
        response.raise_for_status()
        return response.json()['data']['access_token']
    
    def get_rooms(self, limit=50):
        response = self.session.get(f'{self.base_url}/rooms', params={'limit': limit})
        response.raise_for_status()
        return response.json()['data']['rooms']
    
    def send_message(self, room_id, content):
        response = self.session.post(f'{self.base_url}/rooms/{room_id}/messages', json={
            'content': content
        })
        response.raise_for_status()
        return response.json()['data']
    
    def get_messages(self, room_id, limit=50):
        response = self.session.get(f'{self.base_url}/rooms/{room_id}/messages', params={'limit': limit})
        response.raise_for_status()
        return response.json()['data']['messages']

# Utilisation
api = VezaChatAPI('http://localhost:8080/api/v1', 'username', 'password')
rooms = api.get_rooms()
api.send_message(1, 'Hello from Python!')
```

### **Webhook Handler (Node.js)**

```javascript
const express = require('express');
const crypto = require('crypto');

const app = express();
app.use(express.json());

function verifyWebhookSignature(payload, signature, secret) {
    const expectedSignature = crypto
        .createHmac('sha256', secret)
        .update(payload)
        .digest('hex');
    
    return crypto.timingSafeEqual(
        Buffer.from(signature, 'hex'),
        Buffer.from(expectedSignature, 'hex')
    );
}

app.post('/webhook/chat', (req, res) => {
    const signature = req.headers['x-webhook-signature'];
    const payload = JSON.stringify(req.body);
    
    if (!verifyWebhookSignature(payload, signature, process.env.WEBHOOK_SECRET)) {
        return res.status(401).send('Invalid signature');
    }
    
    const { event, data } = req.body;
    
    switch (event) {
        case 'message_sent':
            console.log(`New message in room ${data.room_id}: ${data.content}`);
            break;
        case 'user_joined':
            console.log(`User ${data.username} joined room ${data.room_id}`);
            break;
        case 'user_left':
            console.log(`User ${data.username} left room ${data.room_id}`);
            break;
    }
    
    res.status(200).send('OK');
});

app.listen(3000, () => {
    console.log('Webhook server listening on port 3000');
});
```

## 🚀 Bonnes Pratiques

### **1. Authentification**
- Toujours vérifier la validité du token avant les requêtes
- Implémenter le rafraîchissement automatique des tokens
- Ne jamais exposer les tokens dans les logs

### **2. Rate Limiting**
- Respecter les limites de taux (voir headers `X-RateLimit-*`)
- Implémenter un backoff exponentiel en cas de 429
- Utiliser la mise en cache pour réduire les appels API

### **3. Pagination**
- Utiliser la pagination cursor-based pour de meilleures performances
- Limiter les requêtes à 100 éléments maximum
- Implémenter le lazy loading côté client

### **4. Gestion d'Erreurs**
- Toujours vérifier les codes de statut HTTP
- Parser et gérer les codes d'erreur spécifiques
- Logger les erreurs avec suffisamment de contexte

### **5. Performance**
- Utiliser des connexions HTTP persistantes
- Compresser les requêtes avec gzip
- Mettre en cache les données statiques

---

Cette API REST offre une interface complète et robuste pour toutes les opérations de chat. Pour des fonctionnalités temps réel, utilisez l'[API WebSocket](./websocket_api.md) en complément. 