#!/bin/bash

# 🚀 Script de déploiement automatisé - Veza Chat Server v0.2.0
# Déploiement production-ready avec vérifications de sécurité

set -euo pipefail  # Arrêt immédiat en cas d'erreur

# ================================================================
# CONFIGURATION
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_ROOT/backups"
LOG_FILE="$PROJECT_ROOT/deploy.log"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ================================================================
# FONCTIONS UTILITAIRES
# ================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

check_requirements() {
    log "🔍 Vérification des prérequis..."
    
    # Vérifier Rust
    if ! command -v cargo &> /dev/null; then
        error "Cargo/Rust non trouvé. Installez Rust: https://rustup.rs/"
        exit 1
    fi
    
    # Vérifier PostgreSQL
    if ! command -v psql &> /dev/null; then
        error "PostgreSQL client (psql) non trouvé"
        exit 1
    fi
    
    # Vérifier SQLx CLI
    if ! command -v sqlx &> /dev/null; then
        warning "SQLx CLI non trouvé. Installation..."
        cargo install sqlx-cli --no-default-features --features postgres
    fi
    
    log "✅ Prérequis OK"
}

create_backup() {
    log "💾 Création de la sauvegarde..."
    
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).sql"
    
    if [[ -n "${DATABASE_URL:-}" ]]; then
        pg_dump "$DATABASE_URL" > "$backup_file" 2>/dev/null || {
            warning "Impossible de créer la sauvegarde (base vide ou inexistante)"
            return 0
        }
        log "✅ Sauvegarde créée: $backup_file"
    else
        warning "DATABASE_URL non définie, sauvegarde ignorée"
    fi
}

setup_database() {
    log "🗄️  Configuration de la base de données..."
    
    if [[ -z "${DATABASE_URL:-}" ]]; then
        error "DATABASE_URL doit être définie"
        exit 1
    fi
    
    # Créer la base si nécessaire
    info "Création de la base de données si nécessaire..."
    sqlx database create --database-url "$DATABASE_URL" 2>/dev/null || true
    
    # Appliquer les migrations
    info "Application des migrations..."
    cd "$PROJECT_ROOT"
    sqlx migrate run --database-url "$DATABASE_URL"
    
    log "✅ Base de données configurée"
}

build_application() {
    log "🔨 Compilation de l'application..."
    
    cd "$PROJECT_ROOT"
    
    # Nettoyage
    cargo clean
    
    # Build optimisé pour production
    RUSTFLAGS="-C target-cpu=native" cargo build --release
    
    # Vérifier que le binaire existe
    if [[ ! -f "target/release/chat-server" ]]; then
        error "Échec de compilation"
        exit 1
    fi
    
    log "✅ Compilation terminée"
}

run_tests() {
    log "🧪 Exécution des tests..."
    
    cd "$PROJECT_ROOT"
    
    # Tests unitaires
    info "Tests unitaires..."
    cargo test --release
    
    # Tests d'intégration si disponibles
    if cargo test --list | grep -q "integration"; then
        info "Tests d'intégration..."
        cargo test --release --test integration
    fi
    
    log "✅ Tests passés"
}

security_check() {
    log "🔒 Vérifications de sécurité..."
    
    cd "$PROJECT_ROOT"
    
    # Audit des dépendances
    if command -v cargo-audit &> /dev/null; then
        info "Audit des vulnérabilités..."
        cargo audit
    else
        warning "cargo-audit non installé, audit ignoré"
    fi
    
    # Vérifier la configuration
    if [[ -f ".env" ]]; then
        if grep -q "your-super-secret" .env; then
            error "Secret JWT par défaut détecté! Changez CHAT_SERVER__SECURITY__JWT_SECRET"
            exit 1
        fi
        
        if grep -q "password@localhost" .env; then
            warning "Mot de passe par défaut détecté en production"
        fi
    fi
    
    log "✅ Vérifications de sécurité OK"
}

deploy_binary() {
    log "🚀 Déploiement du binaire..."
    
    local target_dir="${DEPLOY_DIR:-/opt/veza-chat}"
    local service_user="${SERVICE_USER:-veza-chat}"
    
    # Créer l'utilisateur de service si nécessaire
    if ! id "$service_user" &>/dev/null; then
        info "Création de l'utilisateur de service..."
        sudo useradd --system --home "$target_dir" --shell /bin/false "$service_user"
    fi
    
    # Créer les répertoires
    sudo mkdir -p "$target_dir"/{bin,config,logs}
    
    # Copier le binaire
    sudo cp "$PROJECT_ROOT/target/release/chat-server" "$target_dir/bin/"
    sudo chmod +x "$target_dir/bin/chat-server"
    
    # Copier la configuration
    if [[ -f "$PROJECT_ROOT/config/production.toml" ]]; then
        sudo cp "$PROJECT_ROOT/config/production.toml" "$target_dir/config/"
    fi
    
    # Permissions
    sudo chown -R "$service_user:$service_user" "$target_dir"
    
    log "✅ Binaire déployé dans $target_dir"
}

setup_systemd() {
    log "⚙️  Configuration du service systemd..."
    
    local service_file="/etc/systemd/system/veza-chat.service"
    local target_dir="${DEPLOY_DIR:-/opt/veza-chat}"
    local service_user="${SERVICE_USER:-veza-chat}"
    
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Veza Chat Server
Documentation=https://github.com/veza/chat-server
After=network.target postgresql.service redis.service
Wants=postgresql.service redis.service

[Service]
Type=exec
User=$service_user
Group=$service_user
WorkingDirectory=$target_dir
ExecStart=$target_dir/bin/chat-server --config-file $target_dir/config/production.toml
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
TimeoutStopSec=30

# Sécurité
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$target_dir/logs

# Variables d'environnement
Environment=RUST_LOG=info
EnvironmentFile=-$target_dir/.env

# Limits
LimitNOFILE=65536
LimitNPROC=32768

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable veza-chat.service
    
    log "✅ Service systemd configuré"
}

setup_nginx() {
    log "🌐 Configuration du proxy Nginx..."
    
    local nginx_config="/etc/nginx/sites-available/veza-chat"
    local domain="${DOMAIN:-localhost}"
    
    sudo tee "$nginx_config" > /dev/null << EOF
upstream veza_chat_backend {
    server 127.0.0.1:8080;
    keepalive 32;
}

server {
    listen 80;
    server_name $domain;
    
    # Redirection HTTPS en production
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $domain;
    
    # Certificats SSL (à configurer)
    # ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    # Sécurité SSL
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
    ssl_prefer_server_ciphers off;
    ssl_dhparam /etc/nginx/dhparam.pem;
    
    # Headers de sécurité
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header Referrer-Policy "strict-origin-when-cross-origin";
    
    # WebSocket
    location / {
        proxy_pass http://veza_chat_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Health checks
    location /health {
        proxy_pass http://veza_chat_backend/health;
        access_log off;
    }
    
    # Métriques (accès restreint)
    location /metrics {
        proxy_pass http://veza_chat_backend/metrics;
        allow 127.0.0.1;
        allow 10.0.0.0/8;
        deny all;
    }
}
EOF

    sudo ln -sf "$nginx_config" /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl reload nginx
    
    log "✅ Nginx configuré"
}

start_service() {
    log "▶️  Démarrage du service..."
    
    sudo systemctl start veza-chat.service
    sleep 5
    
    # Vérifier le statut
    if sudo systemctl is-active --quiet veza-chat.service; then
        log "✅ Service démarré avec succès"
        
        # Test de connectivité
        if curl -sf http://localhost:8080/health > /dev/null; then
            log "✅ Health check OK"
        else
            warning "Health check échoué"
        fi
    else
        error "Échec du démarrage du service"
        sudo systemctl status veza-chat.service
        exit 1
    fi
}

show_status() {
    log "📊 État du déploiement:"
    
    echo
    info "Service Status:"
    sudo systemctl status veza-chat.service --no-pager -l
    
    echo
    info "Logs récents:"
    sudo journalctl -u veza-chat.service --no-pager -l -n 10
    
    echo
    info "URLs d'accès:"
    echo "  - WebSocket: ws://localhost:8080"
    echo "  - Health: http://localhost:8080/health"
    echo "  - Metrics: http://localhost:8080/metrics"
    
    if [[ -n "${DOMAIN:-}" ]]; then
        echo "  - Production: https://$DOMAIN"
    fi
}

# ================================================================
# FONCTION PRINCIPALE
# ================================================================

main() {
    local action="${1:-deploy}"
    
    echo
    log "🚀 Déploiement Veza Chat Server v0.2.0"
    log "Action: $action"
    echo
    
    # Chargement de l'environnement
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        source "$PROJECT_ROOT/.env"
    fi
    
    case "$action" in
        "deploy")
            check_requirements
            create_backup
            build_application
            run_tests
            security_check
            setup_database
            deploy_binary
            setup_systemd
            start_service
            show_status
            ;;
        "update")
            log "🔄 Mise à jour de l'application..."
            create_backup
            build_application
            run_tests
            security_check
            sudo systemctl stop veza-chat.service
            deploy_binary
            setup_database
            sudo systemctl start veza-chat.service
            show_status
            ;;
        "status")
            show_status
            ;;
        "logs")
            sudo journalctl -u veza-chat.service -f
            ;;
        "restart")
            sudo systemctl restart veza-chat.service
            show_status
            ;;
        "stop")
            sudo systemctl stop veza-chat.service
            log "✅ Service arrêté"
            ;;
        *)
            echo "Usage: $0 {deploy|update|status|logs|restart|stop}"
            echo
            echo "  deploy  - Déploiement complet"
            echo "  update  - Mise à jour de l'application"
            echo "  status  - Afficher le statut"
            echo "  logs    - Afficher les logs en temps réel"
            echo "  restart - Redémarrer le service"
            echo "  stop    - Arrêter le service"
            exit 1
            ;;
    esac
    
    echo
    log "✅ Action '$action' terminée avec succès!"
}

# ================================================================
# EXÉCUTION
# ================================================================

main "$@" 