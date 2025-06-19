use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;
use serde::{Serialize, Deserialize};
use crate::error::Result;

/// Métrique individuelle avec historique
#[derive(Debug, Clone, Serialize)]
pub struct Metric {
    pub name: String,
    pub value: f64,
    pub timestamp: u64,
    pub labels: HashMap<String, String>,
}

/// Agrégation de métriques par type
#[derive(Debug, Clone, Serialize)]
pub struct MetricSummary {
    pub name: String,
    pub count: u64,
    pub avg: f64,
    pub min: f64,
    pub max: f64,
    pub sum: f64,
    pub labels: HashMap<String, String>,
}

/// Types de métriques supportées
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum MetricType {
    Counter,
    Gauge,
    Histogram,
    Timer,
}

/// Gestionnaire de métriques en temps réel
pub struct MetricsCollector {
    metrics: Arc<RwLock<HashMap<String, Vec<Metric>>>>,
    counters: Arc<RwLock<HashMap<String, u64>>>,
    gauges: Arc<RwLock<HashMap<String, f64>>>,
    histograms: Arc<RwLock<HashMap<String, Vec<f64>>>>,
    retention_duration: Duration,
}

impl MetricsCollector {
    pub fn new(retention_duration: Duration) -> Self {
        Self {
            metrics: Arc::new(RwLock::new(HashMap::new())),
            counters: Arc::new(RwLock::new(HashMap::new())),
            gauges: Arc::new(RwLock::new(HashMap::new())),
            histograms: Arc::new(RwLock::new(HashMap::new())),
            retention_duration,
        }
    }

    /// Incrémente un compteur
    pub async fn increment_counter(&self, name: &str, labels: HashMap<String, String>) {
        let key = self.create_key(name, &labels);
        let mut counters = self.counters.write().await;
        *counters.entry(key.clone()).or_insert(0) += 1;
        
        self.record_metric(name, counters.get(&key).unwrap_or(&0).clone() as f64, labels).await;
        
        tracing::debug!(metric_name = %name, key = %key, "📊 Counter incrémenté");
    }

    /// Met à jour une jauge
    pub async fn set_gauge(&self, name: &str, value: f64, labels: HashMap<String, String>) {
        let key = self.create_key(name, &labels);
        let mut gauges = self.gauges.write().await;
        gauges.insert(key, value);
        
        self.record_metric(name, value, labels).await;
        
        tracing::debug!(metric_name = %name, value = %value, "📊 Gauge mise à jour");
    }

    /// Ajoute une valeur à un histogramme
    pub async fn record_histogram(&self, name: &str, value: f64, labels: HashMap<String, String>) {
        let key = self.create_key(name, &labels);
        let mut histograms = self.histograms.write().await;
        histograms.entry(key).or_insert_with(Vec::new).push(value);
        
        self.record_metric(name, value, labels).await;
        
        tracing::debug!(metric_name = %name, value = %value, "📊 Valeur ajoutée à l'histogramme");
    }

    /// Mesure le temps d'exécution d'une opération
    pub async fn time_operation<F, T>(&self, name: &str, labels: HashMap<String, String>, operation: F) -> T
    where
        F: std::future::Future<Output = T>,
    {
        let start = Instant::now();
        let result = operation.await;
        let duration = start.elapsed().as_secs_f64();
        
        self.record_histogram(name, duration, labels).await;
        
        result
    }

    /// Enregistre une métrique brute
    async fn record_metric(&self, name: &str, value: f64, labels: HashMap<String, String>) {
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        
        let metric = Metric {
            name: name.to_string(),
            value,
            timestamp,
            labels,
        };
        
        let mut metrics = self.metrics.write().await;
        metrics.entry(name.to_string())
            .or_insert_with(Vec::new)
            .push(metric);
    }

    /// Crée une clé unique pour une métrique avec ses labels
    fn create_key(&self, name: &str, labels: &HashMap<String, String>) -> String {
        let mut key = name.to_string();
        let mut label_pairs: Vec<_> = labels.iter().collect();
        label_pairs.sort_by_key(|(k, _)| *k);
        
        for (k, v) in label_pairs {
            key.push_str(&format!("{}={}", k, v));
        }
        
        key
    }

    /// Obtient un résumé d'une métrique
    pub async fn get_metric_summary(&self, name: &str) -> Option<MetricSummary> {
        let metrics = self.metrics.read().await;
        let metric_values = metrics.get(name)?;
        
        if metric_values.is_empty() {
            return None;
        }
        
        let values: Vec<f64> = metric_values.iter().map(|m| m.value).collect();
        let count = values.len() as u64;
        let sum: f64 = values.iter().sum();
        let avg = sum / count as f64;
        let min = values.iter().fold(f64::INFINITY, |a, &b| a.min(b));
        let max = values.iter().fold(f64::NEG_INFINITY, |a, &b| a.max(b));
        
        // Prendre les labels de la dernière métrique
        let labels = metric_values.last()?.labels.clone();
        
        Some(MetricSummary {
            name: name.to_string(),
            count,
            avg,
            min,
            max,
            sum,
            labels,
        })
    }

    /// Obtient toutes les métriques actives
    pub async fn get_all_metrics(&self) -> HashMap<String, Vec<Metric>> {
        let metrics = self.metrics.read().await;
        metrics.clone()
    }

    /// Nettoie les métriques anciennes
    pub async fn cleanup_old_metrics(&self) {
        let cutoff_time = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs() - self.retention_duration.as_secs();
        
        let mut metrics = self.metrics.write().await;
        for values in metrics.values_mut() {
            values.retain(|m| m.timestamp > cutoff_time);
        }
        
        // Supprimer les entrées vides
        metrics.retain(|_, values| !values.is_empty());
        
        tracing::debug!("🧹 Nettoyage des métriques anciennes effectué");
    }
}

/// Métriques spécifiques au chat
pub struct ChatMetrics {
    collector: MetricsCollector,
}

impl ChatMetrics {
    pub fn new() -> Self {
        Self {
            collector: MetricsCollector::new(Duration::from_secs(3600)), // 1 heure de rétention
        }
    }

    /// Connexion WebSocket établie
    pub async fn websocket_connected(&self, user_id: i32) {
        let labels = HashMap::from([
            ("event".to_string(), "connection".to_string()),
            ("user_id".to_string(), user_id.to_string()),
        ]);
        self.collector.increment_counter("websocket_connections_total", labels).await;
    }

    /// Connexion WebSocket fermée
    pub async fn websocket_disconnected(&self, user_id: i32) {
        let labels = HashMap::from([
            ("event".to_string(), "disconnection".to_string()),
            ("user_id".to_string(), user_id.to_string()),
        ]);
        self.collector.increment_counter("websocket_disconnections_total", labels).await;
    }

    /// Message envoyé (salon ou DM)
    pub async fn message_sent(&self, message_type: &str, room: Option<&str>) {
        let mut labels = HashMap::from([
            ("type".to_string(), message_type.to_string()),
        ]);
        
        if let Some(room) = room {
            labels.insert("room".to_string(), room.to_string());
        }
        
        self.collector.increment_counter("messages_sent_total", labels).await;
    }

    /// Erreur survenue
    pub async fn error_occurred(&self, error_type: &str, context: &str) {
        let labels = HashMap::from([
            ("error_type".to_string(), error_type.to_string()),
            ("context".to_string(), context.to_string()),
        ]);
        self.collector.increment_counter("errors_total", labels).await;
    }

    /// Rate limit déclenché
    pub async fn rate_limit_triggered(&self, user_id: i32) {
        let labels = HashMap::from([
            ("user_id".to_string(), user_id.to_string()),
        ]);
        self.collector.increment_counter("rate_limits_triggered_total", labels).await;
    }

    /// Utilisateurs actifs
    pub async fn active_users(&self, count: u64) {
        let labels = HashMap::new();
        self.collector.set_gauge("active_users", count as f64, labels).await;
    }

    /// Salons actifs
    pub async fn active_rooms(&self, count: u64) {
        let labels = HashMap::new();
        self.collector.set_gauge("active_rooms", count as f64, labels).await;
    }

    /// Temps de traitement d'un message
    pub async fn message_processing_time(&self, duration: Duration, message_type: &str) {
        let labels = HashMap::from([
            ("message_type".to_string(), message_type.to_string()),
        ]);
        self.collector.record_histogram("message_processing_duration_seconds", duration.as_secs_f64(), labels).await;
    }

    /// Taille d'un message
    pub async fn message_size(&self, size_bytes: usize, message_type: &str) {
        let labels = HashMap::from([
            ("message_type".to_string(), message_type.to_string()),
        ]);
        self.collector.record_histogram("message_size_bytes", size_bytes as f64, labels).await;
    }

    /// Obtient toutes les métriques pour l'API de monitoring
    pub async fn get_all_metrics(&self) -> HashMap<String, Vec<Metric>> {
        self.collector.get_all_metrics().await
    }

    /// Nettoie les anciennes métriques
    pub async fn cleanup(&self) {
        self.collector.cleanup_old_metrics().await;
    }

    /// Mesure le temps d'une opération de base de données
    pub async fn time_db_operation<T>(&self, operation_type: &str, future: impl std::future::Future<Output = T>) -> T {
        let labels = HashMap::from([
            ("operation".to_string(), operation_type.to_string()),
        ]);
        
        self.collector.time_operation("database_operation_duration_seconds", labels, future).await
    }

    /// Mesure le temps d'authentification
    pub async fn time_auth_operation<T>(&self, future: impl std::future::Future<Output = T>) -> T {
        let labels = HashMap::new();
        self.collector.time_operation("auth_operation_duration_seconds", labels, future).await
    }
}

/// Point d'API pour exposer les métriques (format Prometheus ou JSON)
#[derive(Serialize)]
pub struct MetricsExport {
    pub timestamp: u64,
    pub metrics: HashMap<String, Vec<Metric>>,
    pub system_info: SystemInfo,
}

#[derive(Serialize)]
pub struct SystemInfo {
    pub uptime_seconds: u64,
    pub memory_usage_mb: u64,
    pub cpu_usage_percent: f64,
}

impl MetricsExport {
    pub async fn new(metrics: &ChatMetrics, start_time: Instant) -> Self {
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        
        let metrics_data = metrics.get_all_metrics().await;
        
        // Informations système basiques
        let system_info = SystemInfo {
            uptime_seconds: start_time.elapsed().as_secs(),
            memory_usage_mb: 0, // TODO: implémenter lecture mémoire réelle
            cpu_usage_percent: 0.0, // TODO: implémenter lecture CPU réelle
        };
        
        Self {
            timestamp,
            metrics: metrics_data,
            system_info,
        }
    }

    /// Exporte au format Prometheus
    pub fn to_prometheus_format(&self) -> String {
        let mut output = String::new();
        
        for (name, metrics) in &self.metrics {
            if !metrics.is_empty() {
                output.push_str(&format!("# HELP {} Auto-generated metric\n", name));
                output.push_str(&format!("# TYPE {} gauge\n", name));
                
                // Calculs basiques sur les métriques
                let count = metrics.len();
                let sum: f64 = metrics.iter().map(|m| m.value).sum();
                let avg = sum / count as f64;
                
                output.push_str(&format!("{}_count {}\n", name, count));
                output.push_str(&format!("{}_sum {}\n", name, sum));
                output.push_str(&format!("{}_avg {}\n", name, avg));
            }
        }
        
        // Métriques système
        output.push_str(&format!("chat_server_uptime_seconds {}\n", self.system_info.uptime_seconds));
        output.push_str(&format!("chat_server_memory_usage_mb {}\n", self.system_info.memory_usage_mb));
        output.push_str(&format!("chat_server_cpu_usage_percent {}\n", self.system_info.cpu_usage_percent));
        
        output
    }
} 