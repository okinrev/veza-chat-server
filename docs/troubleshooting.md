# 🔧 Troubleshooting - Guide de Dépannage

**Version :** 0.2.0  
**Dernière mise à jour :** $(date +"%Y-%m-%d")

## 📋 Vue d'Ensemble

Ce guide couvre les problèmes les plus courants rencontrés avec le serveur de chat Veza et leurs solutions. Il est organisé par catégorie pour faciliter le diagnostic.

## 🚨 Diagnostic Rapide

### **Vérifications de Base**
```bash
# 1. Santé du serveur
curl -f http://localhost:8080/health

# 2. Logs du serveur
docker-compose logs veza-chat

# 3. Base de données
docker-compose exec postgres pg_isready -U veza_user

# 4. Redis
docker-compose exec redis redis-cli ping

# 5. Connectivité réseau
netstat -tlnp | grep :8080
```

### **États du Système**
| Composant | Commande de Vérification | État Attendu |
|-----------|-------------------------|--------------|
| Serveur Chat | `curl localhost:8080/health` | `200 OK` |
| PostgreSQL | `pg_isready -h localhost` | `accepting connections` |
| Redis | `redis-cli ping` | `PONG` |
| WebSocket | `wscat -c ws://localhost:8080/ws` | Connexion établie |

## 🔌 Problèmes de Connexion

### **❌ Impossible de se connecter au serveur**

#### **Symptômes**
```
curl: (7) Failed to connect to localhost port 8080: Connection refused
```

#### **Causes Possibles**
1. Le serveur n'est pas démarré
2. Port déjà utilisé
3. Problème de configuration réseau
4. Firewall bloquant

#### **Solutions**
```bash
# Vérifier si le serveur fonctionne
docker-compose ps veza-chat

# Redémarrer le serveur
docker-compose restart veza-chat

# Vérifier les ports utilisés
sudo netstat -tlnp | grep :8080

# Vérifier les logs
docker-compose logs veza-chat --tail=50
```

### **❌ WebSocket Connection Failed**

#### **Symptômes**
```javascript
WebSocket connection to 'ws://localhost:8080/ws' failed
```

#### **Causes Possibles**
1. Serveur WebSocket non disponible
2. Problème de proxy/reverse proxy
3. Headers manquants
4. Token d'authentification invalide

#### **Solutions**
```bash
# Test WebSocket basique
wscat -c ws://localhost:8080/ws

# Avec authentification
wscat -c ws://localhost:8080/ws -H "Authorization: Bearer YOUR_TOKEN"

# Vérifier la configuration Nginx
nginx -t && nginx -s reload

# Logs WebSocket
grep "websocket" /var/log/nginx/error.log
```

## 🔐 Problèmes d'Authentification

### **❌ Token JWT Invalide**

#### **Symptômes**
```json
{
  "error": {
    "code": "INVALID_TOKEN",
    "message": "Token JWT invalide ou expiré"
  }
}
```

#### **Diagnostic**
```bash
# Vérifier la validité du token
echo "YOUR_JWT_TOKEN" | base64 -d

# Vérifier l'expiration
node -e "
const token = 'YOUR_JWT_TOKEN';
const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64'));
console.log('Expires:', new Date(payload.exp * 1000));
console.log('Now:', new Date());
"
```

#### **Solutions**
```bash
# Générer un nouveau token
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"user","password":"password"}'

# Rafraîchir le token
curl -X POST http://localhost:8080/api/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token":"YOUR_REFRESH_TOKEN"}'
```

### **❌ Trop de tentatives de connexion**

#### **Symptômes**
```json
{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Trop de tentatives de connexion"
  }
}
```

#### **Solutions**
```bash
# Vérifier le rate limiting dans Redis
redis-cli --scan --pattern "rate_limit:*"

# Réinitialiser les limites pour un utilisateur
redis-cli DEL "rate_limit:user:123"

# Réinitialiser les limites pour une IP
redis-cli DEL "rate_limit:ip:192.168.1.100"
```

## 💾 Problèmes de Base de Données

### **❌ Connection Pool Exhausted**

#### **Symptômes**
```
SQLX error: PoolTimedOut: timed out waiting for an open connection
```

#### **Diagnostic**
```sql
-- Vérifier les connexions actives
SELECT count(*) as active_connections 
FROM pg_stat_activity 
WHERE state = 'active';

-- Voir les requêtes longues
SELECT now() - pg_stat_activity.query_start AS duration, query 
FROM pg_stat_activity 
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';
```

#### **Solutions**
```bash
# Augmenter la taille du pool de connexions
export DATABASE_MAX_CONNECTIONS=50

# Redémarrer le serveur
docker-compose restart veza-chat

# Optimiser PostgreSQL
echo "max_connections = 200" >> /etc/postgresql/postgresql.conf
systemctl restart postgresql
```

### **❌ Migrations Failed**

#### **Symptômes**
```
Migration 002_advanced_features.sql failed: relation already exists
```

#### **Solutions**
```bash
# Vérifier l'état des migrations
psql -d veza_chat -c "SELECT * FROM _sqlx_migrations;"

# Forcer une migration spécifique
psql -d veza_chat -f migrations/002_advanced_features.sql

# Réinitialiser complètement la base
./scripts/maintenance/reset_db.sh
```

## 📱 Problèmes de Messages

### **❌ Messages non reçus en temps réel**

#### **Symptômes**
- Les messages n'apparaissent pas immédiatement
- Latence élevée dans l'affichage

#### **Diagnostic**
```bash
# Vérifier les connexions WebSocket actives
redis-cli HGETALL "websocket_connections"

# Vérifier la latence Redis
redis-cli --latency -h localhost -p 6379

# Métriques du serveur
curl http://localhost:8080/metrics | grep websocket
```

#### **Solutions**
```bash
# Redémarrer Redis
docker-compose restart redis

# Vérifier la configuration WebSocket
grep -r "websocket" docker-compose.yml

# Optimiser Redis
redis-cli CONFIG SET save ""
redis-cli CONFIG SET maxmemory-policy allkeys-lru
```

### **❌ Upload de fichiers échoue**

#### **Symptômes**
```json
{
  "error": {
    "code": "FILE_TOO_LARGE",
    "message": "Fichier trop volumineux"
  }
}
```

#### **Solutions**
```bash
# Vérifier les limites de taille
grep MAX_FILE_SIZE .env

# Augmenter les limites Nginx
echo "client_max_body_size 50M;" >> nginx.conf

# Vérifier l'espace disque
df -h /app/uploads

# Nettoyer les anciens fichiers
find /app/uploads -mtime +30 -delete
```

## 🔧 Problèmes de Performance

### **❌ Latence élevée**

#### **Diagnostic**
```bash
# Métriques de performance
curl http://localhost:8080/metrics | grep -E "(duration|latency)"

# Profiling des requêtes SQL
psql -d veza_chat -c "
SELECT query, mean_time, calls, total_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;"

# Métriques système
top -p $(pgrep veza-chat-server)
```

#### **Solutions**
```bash
# Optimiser PostgreSQL
echo "shared_buffers = 256MB" >> postgresql.conf
echo "effective_cache_size = 1GB" >> postgresql.conf

# Optimiser Redis
redis-cli CONFIG SET maxmemory 512mb
redis-cli CONFIG SET maxmemory-policy allkeys-lru

# Scaling horizontal
docker-compose up --scale veza-chat=3
```

### **❌ Consommation mémoire excessive**

#### **Diagnostic**
```bash
# Mémoire utilisée par le serveur
docker stats veza-chat-server

# Analyse mémoire Redis
redis-cli INFO memory

# Profiling mémoire
valgrind --tool=massif ./veza-chat-server
```

#### **Solutions**
```bash
# Limiter la mémoire Docker
echo "services:
  veza-chat:
    deploy:
      resources:
        limits:
          memory: 512M" >> docker-compose.override.yml

# Optimiser le cache Redis
redis-cli CONFIG SET maxmemory 256mb
redis-cli FLUSHDB

# Redémarrer avec moins de workers
export WORKERS=2
docker-compose restart veza-chat
```

## 🌐 Problèmes Réseau

### **❌ CORS Errors**

#### **Symptômes**
```
Access to fetch at 'http://localhost:8080/api' from origin 'http://localhost:3000' has been blocked by CORS policy
```

#### **Solutions**
```bash
# Ajouter l'origine dans la configuration
export CORS_ALLOWED_ORIGINS="http://localhost:3000,https://yourapp.com"

# Vérifier la configuration Nginx
grep -r "add_header.*Access-Control" nginx.conf

# Redémarrer le serveur
docker-compose restart veza-chat nginx
```

### **❌ Problèmes SSL/TLS**

#### **Symptômes**
```
SSL_connect: SSL_ERROR_SYSCALL
```

#### **Solutions**
```bash
# Vérifier les certificats
openssl x509 -in /etc/nginx/ssl/cert.pem -text -noout

# Renouveler les certificats Let's Encrypt
certbot renew --nginx

# Tester la configuration SSL
nginx -t
```

## 📊 Monitoring et Logs

### **Analyse des Logs**

#### **Logs d'Erreur**
```bash
# Erreurs serveur
docker-compose logs veza-chat | grep ERROR

# Erreurs base de données
docker-compose logs postgres | grep ERROR

# Erreurs Redis
docker-compose logs redis | grep WARNING
```

#### **Logs d'Accès**
```bash
# Requêtes les plus fréquentes
awk '{print $7}' /var/log/nginx/access.log | sort | uniq -c | sort -rn

# IPs avec le plus de requêtes
awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn

# Codes d'erreur
awk '{print $9}' /var/log/nginx/access.log | grep -E '^[4-5]' | sort | uniq -c
```

### **Métriques Importantes**

#### **Métriques Serveur**
```bash
# Connexions WebSocket actives
curl -s http://localhost:8080/metrics | grep websocket_connections_active

# Requêtes par seconde
curl -s http://localhost:8080/metrics | grep http_requests_total

# Latence moyenne
curl -s http://localhost:8080/metrics | grep http_request_duration
```

#### **Métriques Base de Données**
```sql
-- Requêtes lentes
SELECT query, mean_time, calls 
FROM pg_stat_statements 
WHERE mean_time > 100 
ORDER BY mean_time DESC;

-- Connexions actives
SELECT count(*) FROM pg_stat_activity WHERE state = 'active';

-- Cache hit ratio
SELECT 
  sum(heap_blks_read) as heap_read,
  sum(heap_blks_hit) as heap_hit,
  sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio
FROM pg_statio_user_tables;
```

## 🔨 Outils de Diagnostic

### **Scripts de Diagnostic**
```bash
#!/bin/bash
# scripts/diagnose.sh

echo "=== Diagnostic Veza Chat ==="

echo "1. Services Status:"
docker-compose ps

echo "2. Health Checks:"
curl -f http://localhost:8080/health || echo "❌ Server unhealthy"
docker-compose exec postgres pg_isready -U veza_user || echo "❌ DB unhealthy"
docker-compose exec redis redis-cli ping || echo "❌ Redis unhealthy"

echo "3. Resource Usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

echo "4. Recent Errors:"
docker-compose logs veza-chat --tail=20 | grep ERROR

echo "5. Network Connectivity:"
netstat -tlnp | grep -E ":8080|:5432|:6379"

echo "=== End Diagnostic ==="
```

### **Test de Charge**
```bash
#!/bin/bash
# scripts/load-test.sh

# Test HTTP
wrk -t12 -c400 -d30s http://localhost:8080/health

# Test WebSocket
wscat -c ws://localhost:8080/ws -w 10 &
for i in {1..100}; do
    wscat -c ws://localhost:8080/ws &
done
wait
```

## 📞 Support et Escalade

### **Informations à Collecter**
Avant de demander de l'aide, collectez ces informations :

```bash
# Version du serveur
docker-compose exec veza-chat veza-chat-server --version

# Configuration système
uname -a
docker --version
docker-compose --version

# Logs récents
docker-compose logs veza-chat --tail=100 > logs_veza.txt
docker-compose logs postgres --tail=50 > logs_db.txt
docker-compose logs redis --tail=50 > logs_redis.txt

# Configuration
cat .env | grep -v PASSWORD > config_sanitized.txt

# Métriques
curl -s http://localhost:8080/metrics > metrics.txt
```

### **Niveaux d'Escalade**

#### **Niveau 1 - Self-Service**
- Consulter cette documentation
- Vérifier les logs
- Redémarrer les services

#### **Niveau 2 - Configuration**
- Problèmes de configuration
- Optimisation des performances
- Intégration avec d'autres systèmes

#### **Niveau 3 - Bug/Code**
- Bugs logiciels
- Comportements inattendus
- Demandes de fonctionnalités

---

Cette documentation de troubleshooting couvre les problèmes les plus courants. Pour des problèmes spécifiques non couverts ici, consultez les logs détaillés et les métriques système. 