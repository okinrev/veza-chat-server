# 🚀 Guide de Migration Base de Données Veza

## 📋 Vue d'ensemble

Ce guide vous explique comment migrer votre base de données PostgreSQL existante vers la nouvelle structure optimisée pour la production.

## ⚠️ Prérequis Importants

### 1. Sauvegarde Obligatoire
**AVANT TOUTE CHOSE** : Créez une sauvegarde complète de votre base de données :

```bash
pg_dump -h 10.5.191.47 -U veza -d veza_db > backup_complet_$(date +%Y%m%d_%H%M%S).sql
```

### 2. Outils Nécessaires
- PostgreSQL client (`psql`) installé
- Accès réseau au serveur 10.5.191.47
- Permissions d'écriture sur le serveur de base de données

### 3. Temps d'Arrêt
Prévoyez 10-30 minutes d'arrêt de service selon la taille de vos données.

## 🔧 Processus de Migration

### Option 1 : Migration Automatisée (Recommandée)

```bash
# 1. Lancer le script de migration
./scripts/run_migration.sh

# 2. Vérifier le résultat
./scripts/verify_migration.sh
```

### Option 2 : Migration Manuelle

```bash
# 1. Tester la connexion
psql -h 10.5.191.47 -U veza -d veza_db -c "SELECT version();"

# 2. Exécuter la migration
psql -h 10.5.191.47 -U veza -d veza_db -f migrations/999_cleanup_production_ready_fixed.sql

# 3. Vérifier le résultat
./scripts/verify_migration.sh
```

## 📊 Modifications Apportées

### Tables Supprimées
- `users_enhanced`, `users_backup`
- `messages_enhanced`, `rooms_enhanced`
- `message_mentions_enhanced`, `message_mentions_secure`
- `message_reactions_enhanced`
- `user_sessions_enhanced`, `user_sessions_secure`
- `security_events_enhanced`, `security_events_secure`
- Tables métier obsolètes (`listings`, `categories`, etc.)

### Tables Modifiées

#### `users`
- ✅ Ajout de colonnes UUID
- ✅ Colonnes 2FA (two_factor_enabled, two_factor_secret)
- ✅ Colonnes de profil (display_name, avatar_url, bio)
- ✅ Métadonnées (last_login, last_activity, updated_at)
- ✅ Permissions (is_verified, is_active)
- ✅ Type `user_role` énuméré

#### `messages`
- ✅ Ajout UUID
- ✅ Renommage `from_user` → `author_id`
- ✅ Nouvelle colonne `conversation_id`
- ✅ Support des threads (`parent_message_id`)
- ✅ Statuts des messages (`status`)
- ✅ Métadonnées (is_edited, is_pinned, metadata JSONB)

### Nouvelles Tables Créées

#### `conversations`
- Unification des DM et rooms
- Types : `direct_message`, `public_room`, `private_room`, `group`
- Gestion des permissions et archivage

#### `conversation_members`
- Membres des conversations avec rôles
- Gestion des permissions par conversation

#### `message_reactions`
- Réactions emoji sur les messages
- Contraintes d'unicité

#### `message_mentions`
- Système de mentions @utilisateur
- Statut lu/non-lu

#### `message_history`
- Historique des modifications de messages
- Audit trail complet

#### `user_sessions`
- Sessions utilisateur avec tokens
- Gestion des appareils et IP

### Index de Performance Ajoutés

- `idx_users_username_active` - Recherche utilisateurs actifs  
- `idx_messages_conversation_time` - Messages par conversation
- `idx_messages_author_time` - Messages par auteur
- `idx_conversations_type_public` - Conversations publiques
- `idx_reactions_message` - Réactions par message
- `idx_mentions_user_unread` - Mentions non lues
- Index de recherche full-text sur le contenu

## 🔍 Vérifications Post-Migration

### Vérifications Critiques
1. **Nombre d'utilisateurs préservé**
2. **Messages existants conservés**
3. **Nouvelles tables créées**
4. **Index de performance présents**
5. **Contraintes d'intégrité valides**

### Commandes de Vérification Manuelle

```sql
-- Vérifier les utilisateurs
SELECT COUNT(*) FROM users;
SELECT COUNT(*) FROM users WHERE uuid IS NOT NULL;

-- Vérifier les messages
SELECT COUNT(*) FROM messages;
SELECT COUNT(*) FROM messages WHERE conversation_id IS NOT NULL;

-- Vérifier les nouvelles tables
SELECT COUNT(*) FROM conversations;
SELECT COUNT(*) FROM conversation_members;

-- Vérifier les index
SELECT indexname FROM pg_indexes WHERE tablename = 'messages';
```

## 🚨 Résolution de Problèmes

### Erreur de Connexion
```bash
# Vérifier la connectivité
ping 10.5.191.47
telnet 10.5.191.47 5432
```

### Erreur de Permissions
```sql
-- Vérifier les permissions
\dt
\du
```

### Rollback en Cas de Problème
```bash
# Restaurer la sauvegarde
psql -h 10.5.191.47 -U veza -d veza_db < backup_complet_YYYYMMDD_HHMMSS.sql
```

## 📈 Optimisations Post-Migration

### 1. Maintenance Immédiate
```sql
-- Actualiser les statistiques
ANALYZE;

-- Optimiser l'espace
VACUUM FULL;
```

### 2. Configuration Recommandée
```sql
-- Configurer la mémoire partagée
-- Dans postgresql.conf :
shared_buffers = 256MB
work_mem = 4MB
maintenance_work_mem = 64MB
```

### 3. Surveillance
- Surveiller les performances des requêtes
- Vérifier l'utilisation des index
- Monitorer l'espace disque

## 🔄 Mise à Jour de l'Application

Après la migration, vous devrez mettre à jour votre code application :

1. **Modèles de données** : Adapter aux nouvelles structures
2. **Requêtes SQL** : Utiliser les nouvelles colonnes
3. **Authentification** : Implémenter le 2FA si souhaité
4. **Conversations** : Migrer de room/DM vers conversations unifiées

## 📞 Support

En cas de problème :
1. Vérifiez les logs détaillés
2. Exécutez le script de vérification
3. Consultez la documentation PostgreSQL
4. Contactez l'équipe technique si nécessaire

## 🎯 Checklist de Migration

- [ ] Sauvegarde complète créée
- [ ] Application arrêtée (si en production)
- [ ] Migration exécutée avec succès
- [ ] Vérifications post-migration OK
- [ ] Tests de l'application
- [ ] Monitoring en place
- [ ] Documentation mise à jour
- [ ] Équipe informée

---

**💡 Conseil** : Testez d'abord la migration sur un environnement de développement avant la production ! 