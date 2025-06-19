# 🚀 Déploiement - Guide Complet

**Version :** 0.2.0  
**Dernière mise à jour :** $(date +"%Y-%m-%d")

## 📋 Vue d'Ensemble

Ce guide couvre tous les aspects du déploiement du serveur de chat Veza en production, incluant l'orchestration, le monitoring, la sécurité, la sauvegarde, et la haute disponibilité.

## 🐳 Déploiement Docker

### **Dockerfile Optimisé**
```dockerfile
# Build stage
FROM rust:1.75-alpine AS builder

# Install dependencies
RUN apk add --no-cache \
    musl-dev \
    pkgconfig \
    openssl-dev \
    postgresql-dev

WORKDIR /app

# Copy dependency files
COPY Cargo.toml Cargo.lock ./

# Create dummy main to cache dependencies
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release && rm src/main.rs

# Copy source code
COPY src ./src
COPY migrations ./migrations

# Build application
RUN touch src/main.rs && cargo build --release

# Runtime stage
FROM alpine:3.18

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    postgresql-client \
    redis-tools \
    curl \
    tzdata

# Create non-root user
RUN addgroup -g 1001 -S appuser && \
    adduser -u 1001 -S appuser -G appuser

# Create directories
RUN mkdir -p /app/uploads /app/logs && \
    chown -R appuser:appuser /app

# Copy binary
COPY --from=builder /app/target/release/veza-chat-server /usr/local/bin/veza-chat-server
RUN chmod +x /usr/local/bin/veza-chat-server

# Copy static files
COPY static /app/static

USER appuser
WORKDIR /app

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080

CMD ["veza-chat-server"]
```

### **Docker Compose Production**
```yaml
version: '3.8'

services:
  # Base de données principale
  postgres:
    image: postgres:15-alpine
    container_name: veza-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --locale=C"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./backups:/backups
      - ./init-db.sql:/docker-entrypoint-initdb.d/init-db.sql:ro
    ports:
      - "127.0.0.1:5432:5432"
    networks:
      - veza-network
    command: >
      postgres
      -c shared_preload_libraries=pg_stat_statements
      -c pg_stat_statements.track=all
      -c max_connections=200
      -c shared_buffers=256MB
      -c effective_cache_size=1GB
      -c maintenance_work_mem=64MB
      -c checkpoint_completion_target=0.9
      -c wal_buffers=16MB
      -c default_statistics_target=100
      -c random_page_cost=1.1
      -c effective_io_concurrency=200
      -c work_mem=4MB
      -c min_wal_size=1GB
      -c max_wal_size=4GB
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Cache Redis
  redis:
    image: redis:7-alpine
    container_name: veza-redis
    restart: unless-stopped
    environment:
      - REDIS_PASSWORD=${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
      - ./redis.conf:/usr/local/etc/redis/redis.conf:ro
    ports:
      - "127.0.0.1:6379:6379"
    networks:
      - veza-network
    command: redis-server /usr/local/etc/redis/redis.conf --requirepass ${REDIS_PASSWORD}
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    sysctls:
      - net.core.somaxconn=65535

  # Application principale
  veza-chat:
    build:
      context: .
      dockerfile: Dockerfile
      target: runtime
    container_name: veza-chat-server
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      # Base de données
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      
      # Redis
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
      
      # JWT
      JWT_SECRET: ${JWT_SECRET}
      JWT_EXPIRY_MINUTES: 15
      JWT_REFRESH_EXPIRY_DAYS: 7
      
      # Serveur
      HOST: 0.0.0.0
      PORT: 8080
      WORKERS: 4
      
      # Logging
      RUST_LOG: info
      LOG_LEVEL: info
      LOG_FORMAT: json
      
      # Uploads
      UPLOAD_PATH: /app/uploads
      MAX_FILE_SIZE: 10485760  # 10MB
      
      # Rate Limiting
      RATE_LIMIT_ENABLED: true
      RATE_LIMIT_REQUESTS_PER_MINUTE: 60
      
      # Monitoring
      METRICS_ENABLED: true
      HEALTH_CHECK_ENABLED: true
      
      # Sécurité
      CORS_ALLOWED_ORIGINS: ${CORS_ALLOWED_ORIGINS}
      SECURE_COOKIES: true
      
    volumes:
      - uploads:/app/uploads
      - logs:/app/logs
    ports:
      - "8080:8080"
    networks:
      - veza-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '1.0'
        reservations:
          memory: 256M
          cpus: '0.5'

  # Reverse Proxy Nginx
  nginx:
    image: nginx:1.25-alpine
    container_name: veza-nginx
    restart: unless-stopped
    depends_on:
      - veza-chat
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
      - nginx_logs:/var/log/nginx
    networks:
      - veza-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Monitoring - Prometheus
  prometheus:
    image: prom/prometheus:latest
    container_name: veza-prometheus
    restart: unless-stopped
    ports:
      - "127.0.0.1:9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    networks:
      - veza-network
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=30d'
      - '--web.enable-lifecycle'

  # Monitoring - Grafana
  grafana:
    image: grafana/grafana:latest
    container_name: veza-grafana
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_INSTALL_PLUGINS=grafana-piechart-panel
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/dashboards:/etc/grafana/provisioning/dashboards:ro
      - ./grafana/datasources:/etc/grafana/provisioning/datasources:ro
    networks:
      - veza-network

  # Monitoring - Node Exporter
  node-exporter:
    image: prom/node-exporter:latest
    container_name: veza-node-exporter
    restart: unless-stopped
    ports:
      - "127.0.0.1:9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    networks:
      - veza-network
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'

  # Backup automatisé
  backup:
    image: postgres:15-alpine
    container_name: veza-backup
    restart: "no"
    depends_on:
      - postgres
    environment:
      PGPASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ./backups:/backups
      - ./scripts/backup.sh:/backup.sh:ro
    networks:
      - veza-network
    profiles: ["backup"]

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
  uploads:
    driver: local
  logs:
    driver: local
  nginx_logs:
    driver: local
  prometheus_data:
    driver: local
  grafana_data:
    driver: local

networks:
  veza-network:
    driver: bridge
```

### **Configuration Nginx**
```nginx
# nginx.conf
user nginx;
worker_processes auto;
worker_rlimit_nofile 65535;

error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';

    access_log /var/log/nginx/access.log main;

    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=ws:10m rate=5r/s;
    limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;

    # Upstream backend
    upstream veza_backend {
        least_conn;
        server veza-chat:8080 max_fails=3 fail_timeout=30s;
        keepalive 32;
    }

    # SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' wss:";

    # Main server block
    server {
        listen 80;
        listen [::]:80;
        server_name your-domain.com www.your-domain.com;

        # Redirect HTTP to HTTPS
        return 301 https://$server_name$request_uri;
    }

    server {
        listen 443 ssl http2;
        listen [::]:443 ssl http2;
        server_name your-domain.com www.your-domain.com;

        # SSL certificates
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;

        # Rate limiting
        limit_req zone=api burst=20 nodelay;
        limit_conn conn_limit_per_ip 20;

        # Client settings
        client_max_body_size 10M;
        client_body_timeout 60s;
        client_header_timeout 60s;

        # Health check endpoint
        location /health {
            access_log off;
            proxy_pass http://veza_backend/health;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # WebSocket endpoint
        location /ws {
            limit_req zone=ws burst=10 nodelay;
            
            proxy_pass http://veza_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # WebSocket specific timeouts
            proxy_read_timeout 86400s;
            proxy_send_timeout 86400s;
            proxy_connect_timeout 60s;
        }

        # API endpoints
        location /api/ {
            limit_req zone=api burst=15 nodelay;
            
            proxy_pass http://veza_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # API specific timeouts
            proxy_connect_timeout 30s;
            proxy_send_timeout 30s;
            proxy_read_timeout 30s;
        }

        # File uploads
        location /api/v1/files/upload {
            limit_req zone=api burst=5 nodelay;
            client_max_body_size 50M;
            client_body_timeout 120s;
            
            proxy_pass http://veza_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            proxy_request_buffering off;
            proxy_connect_timeout 60s;
            proxy_send_timeout 120s;
            proxy_read_timeout 120s;
        }

        # Static files
        location /static/ {
            alias /app/static/;
            expires 1y;
            add_header Cache-Control "public, immutable";
            try_files $uri =404;
        }

        # File downloads
        location /files/ {
            proxy_pass http://veza_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Disable buffering for file downloads
            proxy_buffering off;
            proxy_request_buffering off;
        }

        # Metrics endpoint (protected)
        location /metrics {
            allow 127.0.0.1;
            allow 10.0.0.0/8;
            allow 172.16.0.0/12;
            allow 192.168.0.0/16;
            deny all;
            
            proxy_pass http://veza_backend/metrics;
            proxy_set_header Host $host;
        }

        # Deny access to sensitive files
        location ~ /\. {
            deny all;
            access_log off;
            log_not_found off;
        }

        # Default location
        location / {
            proxy_pass http://veza_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
```

## 🔧 Configuration Redis
```conf
# redis.conf
# Network
bind 127.0.0.1
port 6379
protected-mode yes

# General
daemonize no
supervised no
pidfile /var/run/redis_6379.pid
loglevel notice
logfile ""

# Snapshotting
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir ./

# Replication
replica-serve-stale-data yes
replica-read-only yes

# Security
requirepass yourredispassword

# Clients
maxclients 10000

# Memory management
maxmemory 256mb
maxmemory-policy allkeys-lru

# Lazy freeing
lazyfree-lazy-eviction no
lazyfree-lazy-expire no
lazyfree-lazy-server-del no
replica-lazy-flush no

# Append only file
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Lua scripting
lua-time-limit 5000

# Slow log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Latency monitoring
latency-monitor-threshold 100

# Event notification
notify-keyspace-events Ex

# Advanced config
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
stream-node-max-bytes 4096
stream-node-max-entries 100
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
tcp-keepalive 300
tcp-backlog 511
```

## 🔄 Scripts d'Automatisation

### **Script de Backup**
```bash
#!/bin/bash
# scripts/backup.sh

set -euo pipefail

# Configuration
BACKUP_DIR="/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
POSTGRES_HOST="postgres"
POSTGRES_DB="${POSTGRES_DB}"
POSTGRES_USER="${POSTGRES_USER}"
RETENTION_DAYS=30

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Créer le répertoire de backup
mkdir -p "${BACKUP_DIR}"

# Backup PostgreSQL
log "Starting PostgreSQL backup..."
POSTGRES_BACKUP_FILE="${BACKUP_DIR}/postgres_${TIMESTAMP}.sql.gz"

if pg_dump -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" --verbose | gzip > "${POSTGRES_BACKUP_FILE}"; then
    log "PostgreSQL backup completed: ${POSTGRES_BACKUP_FILE}"
else
    error "PostgreSQL backup failed"
fi

# Backup Redis (si nécessaire)
log "Starting Redis backup..."
REDIS_BACKUP_FILE="${BACKUP_DIR}/redis_${TIMESTAMP}.rdb"

if redis-cli -h redis --rdb "${REDIS_BACKUP_FILE}"; then
    log "Redis backup completed: ${REDIS_BACKUP_FILE}"
else
    warn "Redis backup failed, continuing..."
fi

# Backup des uploads
log "Starting uploads backup..."
UPLOADS_BACKUP_FILE="${BACKUP_DIR}/uploads_${TIMESTAMP}.tar.gz"

if tar -czf "${UPLOADS_BACKUP_FILE}" -C /app uploads/; then
    log "Uploads backup completed: ${UPLOADS_BACKUP_FILE}"
else
    warn "Uploads backup failed, continuing..."
fi

# Nettoyage des anciens backups
log "Cleaning old backups (older than ${RETENTION_DAYS} days)..."
find "${BACKUP_DIR}" -name "*.sql.gz" -mtime +${RETENTION_DAYS} -delete
find "${BACKUP_DIR}" -name "*.rdb" -mtime +${RETENTION_DAYS} -delete
find "${BACKUP_DIR}" -name "*.tar.gz" -mtime +${RETENTION_DAYS} -delete

# Vérification de l'intégrité
log "Verifying backup integrity..."
if gzip -t "${POSTGRES_BACKUP_FILE}"; then
    log "PostgreSQL backup integrity check passed"
else
    error "PostgreSQL backup is corrupted"
fi

# Upload vers S3 (optionnel)
if [ "${AWS_S3_BACKUP_BUCKET:-}" ]; then
    log "Uploading backups to S3..."
    aws s3 cp "${POSTGRES_BACKUP_FILE}" "s3://${AWS_S3_BACKUP_BUCKET}/postgres/"
    aws s3 cp "${REDIS_BACKUP_FILE}" "s3://${AWS_S3_BACKUP_BUCKET}/redis/" 2>/dev/null || true
    aws s3 cp "${UPLOADS_BACKUP_FILE}" "s3://${AWS_S3_BACKUP_BUCKET}/uploads/" 2>/dev/null || true
    log "S3 upload completed"
fi

log "Backup process completed successfully"

# Envoyer notification de succès
if [ "${WEBHOOK_URL:-}" ]; then
    curl -X POST "${WEBHOOK_URL}" \
        -H "Content-Type: application/json" \
        -d "{\"text\":\"✅ Veza Chat backup completed successfully at $(date)\"}" \
        2>/dev/null || true
fi
```

### **Script de Déploiement**
```bash
#!/bin/bash
# scripts/deploy.sh

set -euo pipefail

# Configuration
COMPOSE_FILE="docker-compose.yml"
SERVICE_NAME="veza-chat"
BACKUP_BEFORE_DEPLOY=true
HEALTH_CHECK_TIMEOUT=60

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[DEPLOY] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[DEPLOY] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[DEPLOY] ERROR: $1${NC}"
    exit 1
}

# Vérifications pré-déploiement
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Vérifier Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed"
    fi
    
    # Vérifier Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is not installed"
    fi
    
    # Vérifier le fichier .env
    if [ ! -f .env ]; then
        error ".env file not found"
    fi
    
    log "Prerequisites check passed"
}

# Backup avant déploiement
backup_before_deploy() {
    if [ "$BACKUP_BEFORE_DEPLOY" = true ]; then
        log "Creating backup before deployment..."
        docker-compose run --rm backup /backup.sh
        log "Backup completed"
    fi
}

# Déploiement
deploy() {
    log "Starting deployment..."
    
    # Arrêter l'ancien service
    log "Stopping old service..."
    docker-compose stop $SERVICE_NAME
    
    # Construire la nouvelle image
    log "Building new image..."
    docker-compose build $SERVICE_NAME
    
    # Démarrer le nouveau service
    log "Starting new service..."
    docker-compose up -d $SERVICE_NAME
    
    # Attendre que le service soit prêt
    log "Waiting for service to be ready..."
    wait_for_service
    
    log "Deployment completed successfully"
}

# Vérifier la santé du service
wait_for_service() {
    local timeout=$HEALTH_CHECK_TIMEOUT
    local count=0
    
    while [ $count -lt $timeout ]; do
        if curl -f http://localhost:8080/health >/dev/null 2>&1; then
            log "Service is healthy"
            return 0
        fi
        
        sleep 1
        count=$((count + 1))
        
        if [ $((count % 10)) -eq 0 ]; then
            log "Still waiting for service... ($count/$timeout)"
        fi
    done
    
    error "Service did not become healthy within $timeout seconds"
}

# Rollback en cas d'erreur
rollback() {
    warn "Rolling back to previous version..."
    
    # Arrêter le service défaillant
    docker-compose stop $SERVICE_NAME
    
    # Redémarrer avec l'ancienne image
    docker-compose up -d $SERVICE_NAME
    
    warn "Rollback completed"
}

# Test post-déploiement
post_deploy_tests() {
    log "Running post-deployment tests..."
    
    # Test de santé de base
    if ! curl -f http://localhost:8080/health >/dev/null 2>&1; then
        error "Health check failed"
    fi
    
    # Test WebSocket
    if ! timeout 5 bash -c "</dev/tcp/localhost/8080"; then
        error "WebSocket port not accessible"
    fi
    
    # Test base de données
    if ! docker-compose exec -T postgres pg_isready -U ${POSTGRES_USER} >/dev/null 2>&1; then
        error "Database not ready"
    fi
    
    log "Post-deployment tests passed"
}

# Nettoyage des ressources
cleanup() {
    log "Cleaning up old resources..."
    
    # Supprimer les anciennes images
    docker image prune -f
    
    # Supprimer les volumes non utilisés
    docker volume prune -f
    
    log "Cleanup completed"
}

# Main
main() {
    log "Starting Veza Chat deployment process..."
    
    # Trap pour le rollback en cas d'erreur
    trap rollback ERR
    
    check_prerequisites
    backup_before_deploy
    deploy
    post_deploy_tests
    cleanup
    
    log "🚀 Deployment completed successfully!"
    
    # Notification de succès
    if [ "${WEBHOOK_URL:-}" ]; then
        curl -X POST "${WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"🚀 Veza Chat deployed successfully at $(date)\"}" \
            2>/dev/null || true
    fi
}

# Exécuter le script principal
main "$@"
```

## 📊 Configuration Monitoring

### **Prometheus Configuration**
```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alert_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  # Veza Chat Server
  - job_name: 'veza-chat'
    static_configs:
      - targets: ['veza-chat:8080']
    metrics_path: '/metrics'
    scrape_interval: 10s
    
  # PostgreSQL
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']
    
  # Redis
  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']
    
  # Node Exporter
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
    
  # Nginx
  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx-exporter:9113']
```

### **Règles d'Alerte**
```yaml
# alert_rules.yml
groups:
  - name: veza-chat-alerts
    rules:
      # Service indisponible
      - alert: VezaChatDown
        expr: up{job="veza-chat"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Veza Chat service is down"
          description: "Veza Chat service has been down for more than 1 minute"
      
      # Forte charge CPU
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% for more than 5 minutes"
      
      # Utilisation mémoire élevée
      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 90% for more than 5 minutes"
      
      # Base de données inaccessible
      - alert: PostgreSQLDown
        expr: pg_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL is down"
          description: "PostgreSQL database is not responding"
      
      # Redis inaccessible
      - alert: RedisDown
        expr: redis_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Redis is down"
          description: "Redis cache is not responding"
      
      # Trop de connexions WebSocket
      - alert: HighWebSocketConnections
        expr: veza_websocket_connections_active > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High number of WebSocket connections"
          description: "More than 1000 active WebSocket connections"
      
      # Taux d'erreur élevé
      - alert: HighErrorRate
        expr: rate(veza_http_requests_total{status=~"5.."}[5m]) / rate(veza_http_requests_total[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"
          description: "Error rate is above 10% for more than 5 minutes"
```

## 🔐 Configuration Sécurité

### **Configuration Firewall (UFW)**
```bash
#!/bin/bash
# scripts/setup-firewall.sh

# Réinitialiser UFW
ufw --force reset

# Politique par défaut
ufw default deny incoming
ufw default allow outgoing

# SSH (à adapter selon votre configuration)
ufw allow 22/tcp

# HTTP/HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Monitoring (accès local uniquement)
ufw allow from 10.0.0.0/8 to any port 3000  # Grafana
ufw allow from 10.0.0.0/8 to any port 9090  # Prometheus

# PostgreSQL (accès local uniquement)
ufw allow from 172.16.0.0/12 to any port 5432

# Redis (accès local uniquement)
ufw allow from 172.16.0.0/12 to any port 6379

# Activer le firewall
ufw --force enable

echo "Firewall configuration completed"
```

### **Configuration Fail2Ban**
```ini
# /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 10

[veza-chat-auth]
enabled = true
filter = veza-chat-auth
logpath = /app/logs/auth.log
maxretry = 3
bantime = 1800
```

## 🚀 Déploiement Kubernetes

### **Déploiement Kubernetes**
```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: veza-chat
  labels:
    app: veza-chat
spec:
  replicas: 3
  selector:
    matchLabels:
      app: veza-chat
  template:
    metadata:
      labels:
        app: veza-chat
    spec:
      containers:
      - name: veza-chat
        image: veza-chat:latest
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: veza-secrets
              key: database-url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: veza-secrets
              key: redis-url
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: veza-secrets
              key: jwt-secret
        resources:
          limits:
            memory: "512Mi"
            cpu: "500m"
          requests:
            memory: "256Mi"
            cpu: "250m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: veza-chat-service
spec:
  selector:
    app: veza-chat
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: veza-chat-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/rate-limit: "100"
spec:
  tls:
  - hosts:
    - your-domain.com
    secretName: veza-chat-tls
  rules:
  - host: your-domain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: veza-chat-service
            port:
              number: 80
```

## 📈 Optimisations Performance

### **Configuration Système**
```bash
#!/bin/bash
# scripts/optimize-system.sh

# Optimisations réseau
echo 'net.core.somaxconn = 65535' >> /etc/sysctl.conf
echo 'net.core.netdev_max_backlog = 5000' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_max_syn_backlog = 65535' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_keepalive_time = 600' >> /etc/sysctl.conf

# Optimisations fichiers
echo 'fs.file-max = 2097152' >> /etc/sysctl.conf
echo '* soft nofile 65535' >> /etc/security/limits.conf
echo '* hard nofile 65535' >> /etc/security/limits.conf

# Optimisations mémoire
echo 'vm.swappiness = 10' >> /etc/sysctl.conf
echo 'vm.dirty_ratio = 15' >> /etc/sysctl.conf
echo 'vm.dirty_background_ratio = 5' >> /etc/sysctl.conf

# Appliquer les changements
sysctl -p
```

---

Ce guide de déploiement couvre tous les aspects nécessaires pour mettre en production le serveur de chat Veza de manière robuste et sécurisée. 