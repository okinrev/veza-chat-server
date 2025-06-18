//file: backend/modules/chat_server/src/hub/common.rs

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use sqlx::PgPool;

use crate::client::Client;

pub struct ChatHub {
    pub clients: Arc<RwLock<HashMap<i32, Client>>>,
    pub rooms: Arc<RwLock<HashMap<String, Vec<i32>>>>,
    pub db: PgPool,
}

impl ChatHub {
    pub fn new(db: PgPool) -> Arc<Self> {
        tracing::info!("🏗️ Création d'un nouveau ChatHub");
        Arc::new(Self {
            clients: Arc::new(RwLock::new(HashMap::new())),
            rooms: Arc::new(RwLock::new(HashMap::new())),
            db,
        })
    }

    pub async fn register(&self, user_id: i32, client: Client) {
        tracing::debug!(user_id = %user_id, username = %client.username, "🔧 Début register");
        
        let mut clients = self.clients.write().await;
        let clients_before = clients.len();
        
        clients.insert(user_id, client);
        
        tracing::info!(user_id = %user_id, clients_before = %clients_before, clients_after = %clients.len(), "👤 Enregistrement du client");
    }

    pub async fn unregister(&self, user_id: i32) {
        tracing::debug!(user_id = %user_id, "🔧 Début unregister");
        
        let mut clients = self.clients.write().await;
        let clients_before = clients.len();
        
        if let Some(removed_client) = clients.remove(&user_id) {
            tracing::info!(user_id = %user_id, username = %removed_client.username, clients_before = %clients_before, clients_after = %clients.len(), "🚪 Déconnexion du client");
        } else {
            tracing::warn!(user_id = %user_id, clients_count = %clients.len(), "⚠️ Tentative de déconnexion d'un client non enregistré");
        }
        
        // Nettoyer les salons
        let mut rooms = self.rooms.write().await;
        let mut rooms_cleaned = 0;
        let mut total_removals = 0;
        
        for (room_name, user_list) in rooms.iter_mut() {
            let before_len = user_list.len();
            user_list.retain(|&id| id != user_id);
            let after_len = user_list.len();
            
            if before_len != after_len {
                total_removals += before_len - after_len;
                rooms_cleaned += 1;
                tracing::debug!(user_id = %user_id, room = %room_name, members_before = %before_len, members_after = %after_len, "🧹 Utilisateur retiré du salon");
            }
        }
        
        if rooms_cleaned > 0 {
            tracing::info!(user_id = %user_id, rooms_cleaned = %rooms_cleaned, total_removals = %total_removals, "🧹 Nettoyage des salons terminé");
        } else {
            tracing::debug!(user_id = %user_id, "🧹 Aucun salon à nettoyer");
        }
    }
}
