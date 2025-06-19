use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

#[derive(Debug, Clone)]
struct UserBucket {
    messages: Vec<Instant>,
    last_cleanup: Instant,
}

impl UserBucket {
    fn new() -> Self {
        Self {
            messages: Vec::new(),
            last_cleanup: Instant::now(),
        }
    }

    fn cleanup(&mut self, window: Duration) {
        let cutoff = Instant::now() - window;
        self.messages.retain(|&timestamp| timestamp > cutoff);
        self.last_cleanup = Instant::now();
    }

    fn can_send(&mut self, limit: usize, window: Duration) -> bool {
        // Nettoyer les anciens messages si nécessaire
        if self.last_cleanup.elapsed() > Duration::from_secs(10) {
            self.cleanup(window);
        }

        let cutoff = Instant::now() - window;
        let recent_messages = self.messages.iter().filter(|&&t| t > cutoff).count();
        
        if recent_messages >= limit {
            false
        } else {
            self.messages.push(Instant::now());
            true
        }
    }
}

#[derive(Debug)]
pub struct RateLimiter {
    buckets: Arc<RwLock<HashMap<i32, UserBucket>>>,
    messages_per_minute: usize,
    window: Duration,
}

impl RateLimiter {
    pub fn new(messages_per_minute: u32) -> Self {
        Self {
            buckets: Arc::new(RwLock::new(HashMap::new())),
            messages_per_minute: messages_per_minute as usize,
            window: Duration::from_secs(60),
        }
    }

    pub async fn check_and_update(&self, user_id: i32) -> bool {
        let mut buckets = self.buckets.write().await;
        let bucket = buckets.entry(user_id).or_insert_with(UserBucket::new);
        bucket.can_send(self.messages_per_minute, self.window)
    }

    pub async fn cleanup_old_buckets(&self) {
        let mut buckets = self.buckets.write().await;
        let cutoff = Instant::now() - Duration::from_secs(300); // 5 minutes
        
        buckets.retain(|_, bucket| bucket.last_cleanup > cutoff);
        
        tracing::debug!(active_buckets = buckets.len(), "🧹 Nettoyage des buckets de rate limiting");
    }
} 