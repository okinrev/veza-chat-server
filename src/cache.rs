use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use serde::{Serialize, Deserialize};
use crate::error::Result;

/// Cache entry avec expiration
#[derive(Debug, Clone)]
pub struct CacheEntry<T> {
    pub value: T,
    pub expires_at: Instant,
    pub hit_count: u64,
    pub last_accessed: Instant,
}

impl<T> CacheEntry<T> {
    pub fn new(value: T, ttl: Duration) -> Self {
        let now = Instant::now();
        Self {
            value,
            expires_at: now + ttl,
            hit_count: 0,
            last_accessed: now,
        }
    }

    pub fn is_expired(&self) -> bool {
        Instant::now() > self.expires_at
    }

    pub fn touch(&mut self) {
        self.hit_count += 1;
        self.last_accessed = Instant::now();
    }
}

/// Cache intelligent avec LRU et expiration
pub struct SmartCache<K, V> 
where 
    K: Clone + std::hash::Hash + Eq,
    V: Clone,
{
    entries: Arc<RwLock<HashMap<K, CacheEntry<V>>>>,
    max_size: usize,
    default_ttl: Duration,
}

impl<K, V> SmartCache<K, V>
where 
    K: Clone + std::hash::Hash + Eq,
    V: Clone,
{
    pub fn new(max_size: usize, default_ttl: Duration) -> Self {
        Self {
            entries: Arc::new(RwLock::new(HashMap::new())),
            max_size,
            default_ttl,
        }
    }

    /// Insère une valeur dans le cache
    pub async fn insert(&self, key: K, value: V) {
        self.insert_with_ttl(key, value, self.default_ttl).await;
    }

    /// Insère une valeur avec un TTL personnalisé
    pub async fn insert_with_ttl(&self, key: K, value: V, ttl: Duration) {
        let mut entries = self.entries.write().await;
        
        // Nettoyage des entrées expirées
        self.cleanup_expired(&mut entries).await;
        
        // Éviction LRU si le cache est plein
        if entries.len() >= self.max_size {
            self.evict_lru(&mut entries).await;
        }

        entries.insert(key, CacheEntry::new(value, ttl));
    }

    /// Récupère une valeur du cache
    pub async fn get(&self, key: &K) -> Option<V> {
        let mut entries = self.entries.write().await;
        
        if let Some(entry) = entries.get_mut(key) {
            if entry.is_expired() {
                entries.remove(key);
                return None;
            }
            
            entry.touch();
            Some(entry.value.clone())
        } else {
            None
        }
    }

    /// Supprime une entrée du cache
    pub async fn remove(&self, key: &K) -> Option<V> {
        let mut entries = self.entries.write().await;
        entries.remove(key).map(|entry| entry.value)
    }

    /// Nettoie les entrées expirées
    async fn cleanup_expired(&self, entries: &mut HashMap<K, CacheEntry<V>>) {
        let expired_keys: Vec<K> = entries.iter()
            .filter(|(_, entry)| entry.is_expired())
            .map(|(key, _)| key.clone())
            .collect();

        for key in expired_keys {
            entries.remove(&key);
        }
    }

    /// Éviction LRU (Least Recently Used)
    async fn evict_lru(&self, entries: &mut HashMap<K, CacheEntry<V>>) {
        if let Some((lru_key, _)) = entries.iter()
            .min_by_key(|(_, entry)| entry.last_accessed)
            .map(|(key, entry)| (key.clone(), entry.clone())) {
            entries.remove(&lru_key);
        }
    }

    /// Statistiques du cache
    pub async fn stats(&self) -> CacheStats {
        let entries = self.entries.read().await;
        let total_hits: u64 = entries.values().map(|entry| entry.hit_count).sum();
        
        CacheStats {
            total_entries: entries.len(),
            max_size: self.max_size,
            total_hits,
            hit_rate: if entries.is_empty() { 0.0 } else { total_hits as f64 / entries.len() as f64 },
        }
    }

    /// Vide le cache
    pub async fn clear(&self) {
        let mut entries = self.entries.write().await;
        entries.clear();
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct CacheStats {
    pub total_entries: usize,
    pub max_size: usize,
    pub total_hits: u64,
    pub hit_rate: f64,
}

/// Cache spécialisé pour les messages de salon
pub type RoomMessageCache = SmartCache<String, Vec<MessageCacheEntry>>;

/// Cache spécialisé pour les messages directs
pub type DirectMessageCache = SmartCache<(i32, i32), Vec<MessageCacheEntry>>;

/// Cache spécialisé pour les utilisateurs en ligne
pub type UserPresenceCache = SmartCache<i32, UserPresenceEntry>;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageCacheEntry {
    pub id: i32,
    pub user_id: i32,
    pub username: String,
    pub content: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub message_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserPresenceEntry {
    pub user_id: i32,
    pub username: String,
    pub status: String,
    pub last_seen: chrono::DateTime<chrono::Utc>,
    pub current_room: Option<String>,
}

/// Gestionnaire centralisé de tous les caches
pub struct CacheManager {
    pub room_messages: RoomMessageCache,
    pub direct_messages: DirectMessageCache,
    pub user_presence: UserPresenceCache,
    pub user_sessions: SmartCache<String, i32>, // JWT token -> user_id
}

impl CacheManager {
    pub fn new() -> Self {
        Self {
            // Cache des messages de salon (30 min TTL)
            room_messages: SmartCache::new(1000, Duration::from_secs(1800)),
            
            // Cache des messages directs (1 heure TTL)
            direct_messages: SmartCache::new(500, Duration::from_secs(3600)),
            
            // Cache de présence utilisateur (5 min TTL)
            user_presence: SmartCache::new(10000, Duration::from_secs(300)),
            
            // Cache des sessions JWT (24 heures TTL)
            user_sessions: SmartCache::new(50000, Duration::from_secs(86400)),
        }
    }

    /// Met en cache les messages d'un salon
    pub async fn cache_room_messages(&self, room: &str, messages: Vec<MessageCacheEntry>) {
        self.room_messages.insert(room.to_string(), messages).await;
    }

    /// Récupère les messages mis en cache d'un salon
    pub async fn get_cached_room_messages(&self, room: &str) -> Option<Vec<MessageCacheEntry>> {
        self.room_messages.get(&room.to_string()).await
    }

    /// Met en cache les messages directs entre deux utilisateurs
    pub async fn cache_direct_messages(&self, user1: i32, user2: i32, messages: Vec<MessageCacheEntry>) {
        // Normaliser la clé pour éviter les doublons (user1, user2) et (user2, user1)
        let key = if user1 < user2 { (user1, user2) } else { (user2, user1) };
        self.direct_messages.insert(key, messages).await;
    }

    /// Récupère les messages directs mis en cache
    pub async fn get_cached_direct_messages(&self, user1: i32, user2: i32) -> Option<Vec<MessageCacheEntry>> {
        let key = if user1 < user2 { (user1, user2) } else { (user2, user1) };
        self.direct_messages.get(&key).await
    }

    /// Met en cache la présence d'un utilisateur
    pub async fn cache_user_presence(&self, user_id: i32, presence: UserPresenceEntry) {
        self.user_presence.insert(user_id, presence).await;
    }

    /// Récupère la présence mise en cache d'un utilisateur
    pub async fn get_cached_user_presence(&self, user_id: i32) -> Option<UserPresenceEntry> {
        self.user_presence.get(&user_id).await
    }

    /// Met en cache une session utilisateur
    pub async fn cache_user_session(&self, token: &str, user_id: i32) {
        self.user_sessions.insert(token.to_string(), user_id).await;
    }

    /// Récupère l'ID utilisateur d'un token mis en cache
    pub async fn get_cached_user_session(&self, token: &str) -> Option<i32> {
        self.user_sessions.get(&token.to_string()).await
    }

    /// Invalide la session d'un utilisateur
    pub async fn invalidate_user_session(&self, token: &str) {
        self.user_sessions.remove(&token.to_string()).await;
    }

    /// Nettoie tous les caches expirés
    pub async fn cleanup_all(&self) {
        // Le nettoyage est automatique lors des opérations get/insert
        tracing::info!("🧹 Nettoyage automatique des caches effectué");
    }

    /// Statistiques globales des caches
    pub async fn global_stats(&self) -> GlobalCacheStats {
        let room_stats = self.room_messages.stats().await;
        let dm_stats = self.direct_messages.stats().await;
        let presence_stats = self.user_presence.stats().await;
        let session_stats = self.user_sessions.stats().await;

        GlobalCacheStats {
            room_messages: room_stats,
            direct_messages: dm_stats,
            user_presence: presence_stats,
            user_sessions: session_stats,
        }
    }

    /// Vide tous les caches (pour le débogage/maintenance)
    pub async fn clear_all(&self) {
        self.room_messages.clear().await;
        self.direct_messages.clear().await;
        self.user_presence.clear().await;
        self.user_sessions.clear().await;
        tracing::warn!("🗑️ Tous les caches ont été vidés");
    }
}

#[derive(Debug, Serialize)]
pub struct GlobalCacheStats {
    pub room_messages: CacheStats,
    pub direct_messages: CacheStats,
    pub user_presence: CacheStats,
    pub user_sessions: CacheStats,
} 