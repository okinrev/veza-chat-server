use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use serde::{Serialize, Deserialize};
use serde_json::json;
use crate::error::Result;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum UserStatus {
    Online,
    Away,
    Busy,
    Invisible,
    Offline,
}

#[derive(Debug, Clone, Serialize)]
pub struct UserPresence {
    pub user_id: i32,
    pub username: String,
    pub status: UserStatus,
    #[serde(skip)] // Skip Instant car non sérialisable
    pub last_seen: Instant,
    pub status_message: Option<String>,
    pub current_room: Option<String>,
}

impl UserPresence {
    pub fn new(user_id: i32, username: String) -> Self {
        Self {
            user_id,
            username,
            status: UserStatus::Online,
            last_seen: Instant::now(),
            status_message: None,
            current_room: None,
        }
    }

    pub fn update_activity(&mut self) {
        self.last_seen = Instant::now();
        if self.status == UserStatus::Away {
            self.status = UserStatus::Online;
        }
    }

    pub fn set_away_if_inactive(&mut self, away_threshold: Duration) {
        if self.status == UserStatus::Online && self.last_seen.elapsed() > away_threshold {
            self.status = UserStatus::Away;
        }
    }
}

/// Gestionnaire de présence des utilisateurs
pub struct PresenceManager {
    users: Arc<RwLock<HashMap<i32, UserPresence>>>,
    away_threshold: Duration,
}

impl PresenceManager {
    pub fn new() -> Self {
        Self {
            users: Arc::new(RwLock::new(HashMap::new())),
            away_threshold: Duration::from_secs(300), // 5 minutes
        }
    }

    /// Enregistre un utilisateur comme en ligne
    pub async fn user_online(&self, user_id: i32, username: String) {
        let mut users = self.users.write().await;
        let presence = UserPresence::new(user_id, username.clone());
        
        tracing::info!(user_id = %user_id, username = %username, "👋 Utilisateur en ligne");
        users.insert(user_id, presence);
    }

    /// Marque un utilisateur comme hors ligne
    pub async fn user_offline(&self, user_id: i32) {
        let mut users = self.users.write().await;
        if let Some(mut presence) = users.remove(&user_id) {
            presence.status = UserStatus::Offline;
            tracing::info!(user_id = %user_id, username = %presence.username, "👋 Utilisateur hors ligne");
        }
    }

    /// Met à jour l'activité d'un utilisateur
    pub async fn update_user_activity(&self, user_id: i32) {
        let mut users = self.users.write().await;
        if let Some(presence) = users.get_mut(&user_id) {
            presence.update_activity();
        }
    }

    /// Change le statut d'un utilisateur
    pub async fn set_user_status(&self, user_id: i32, status: UserStatus, message: Option<String>) -> Result<()> {
        let mut users = self.users.write().await;
        if let Some(presence) = users.get_mut(&user_id) {
            presence.status = status.clone();
            presence.status_message = message.clone();
            
            tracing::info!(
                user_id = %user_id, 
                username = %presence.username, 
                status = ?status, 
                message = ?message,
                "📊 Statut utilisateur mis à jour"
            );
        }
        Ok(())
    }

    /// Met à jour le salon actuel d'un utilisateur
    pub async fn set_user_room(&self, user_id: i32, room: Option<String>) {
        let mut users = self.users.write().await;
        if let Some(presence) = users.get_mut(&user_id) {
            presence.current_room = room.clone();
            tracing::debug!(user_id = %user_id, room = ?room, "🏠 Salon actuel mis à jour");
        }
    }

    /// Obtient la présence d'un utilisateur
    pub async fn get_user_presence(&self, user_id: i32) -> Option<UserPresence> {
        let users = self.users.read().await;
        users.get(&user_id).cloned()
    }

    /// Obtient la liste des utilisateurs en ligne dans un salon
    pub async fn get_room_users(&self, room: &str) -> Vec<UserPresence> {
        let users = self.users.read().await;
        users.values()
            .filter(|presence| {
                presence.current_room.as_ref().map(|r| r.as_str()) == Some(room) && 
                presence.status != UserStatus::Offline &&
                presence.status != UserStatus::Invisible
            })
            .cloned()
            .collect()
    }

    /// Obtient tous les utilisateurs en ligne
    pub async fn get_online_users(&self) -> Vec<UserPresence> {
        let users = self.users.read().await;
        users.values()
            .filter(|presence| {
                presence.status != UserStatus::Offline &&
                presence.status != UserStatus::Invisible
            })
            .cloned()
            .collect()
    }

    /// Nettoie les utilisateurs inactifs (les marque comme "away")
    pub async fn cleanup_inactive_users(&self) {
        let mut users = self.users.write().await;
        let mut updated_users = Vec::new();

        for presence in users.values_mut() {
            let old_status = presence.status.clone();
            presence.set_away_if_inactive(self.away_threshold);
            
            if old_status != presence.status {
                updated_users.push(presence.clone());
            }
        }

        if !updated_users.is_empty() {
            tracing::info!(count = %updated_users.len(), "😴 Utilisateurs marqués comme inactifs");
        }
    }

    /// Génère un événement de présence pour diffusion
    pub fn create_presence_event(&self, presence: &UserPresence, event_type: &str) -> serde_json::Value {
        json!({
            "type": "presence_update",
            "data": {
                "event": event_type,
                "user_id": presence.user_id,
                "username": presence.username,
                "status": presence.status,
                "status_message": presence.status_message,
                "current_room": presence.current_room
            }
        })
    }
}

/// Système de notifications push
pub struct NotificationManager {
    // Ici on pourrait intégrer avec des services comme Firebase, Apple Push, etc.
}

impl NotificationManager {
    pub fn new() -> Self {
        Self {}
    }

    /// Envoie une notification push à un utilisateur
    pub async fn send_push_notification(
        &self, 
        user_id: i32, 
        title: &str, 
        body: &str, 
        _data: Option<serde_json::Value>
    ) -> Result<()> {
        // Implémentation des notifications push
        tracing::info!(
            user_id = %user_id, 
            title = %title, 
            body = %body,
            "📱 Notification push envoyée"
        );
        
        // TODO: Intégrer avec Firebase Cloud Messaging, Apple Push Notification, etc.
        Ok(())
    }

    /// Notification pour un nouveau message direct
    pub async fn notify_new_dm(&self, to_user: i32, from_username: &str, preview: &str) -> Result<()> {
        let title = format!("Nouveau message de {}", from_username);
        let body = if preview.len() > 50 {
            format!("{}...", &preview[..47])
        } else {
            preview.to_string()
        };

        self.send_push_notification(
            to_user, 
            &title, 
            &body, 
            Some(json!({"type": "dm", "from": from_username}))
        ).await
    }

    /// Notification pour mention dans un salon
    pub async fn notify_room_mention(&self, user_id: i32, room: &str, from_username: &str, message: &str) -> Result<()> {
        let title = format!("Mention dans #{}", room);
        let body = format!("{}: {}", from_username, 
            if message.len() > 50 {
                format!("{}...", &message[..47])
            } else {
                message.to_string()
            }
        );

        self.send_push_notification(
            user_id, 
            &title, 
            &body, 
            Some(json!({"type": "mention", "room": room, "from": from_username}))
        ).await
    }
} 