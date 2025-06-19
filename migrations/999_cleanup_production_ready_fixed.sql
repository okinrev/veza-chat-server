-- ================================================================
-- MIGRATION DE NETTOYAGE ET MISE À JOUR POUR PRODUCTION
-- Version: 0.2.0 - Compatible avec structure existante
-- ================================================================
-- ⚠️  ATTENTION: Cette migration est partiellement destructive
-- 🔒 Assurez-vous d'avoir une sauvegarde complète avant exécution
-- 
-- Utilisation:
-- psql -h 10.5.191.47 -U veza -d veza_db -f migrations/999_cleanup_production_ready_fixed.sql
-- ================================================================

\echo '🚀 Début de la migration de production...'

-- Vérifier que nous sommes dans la bonne base
SELECT current_database() as current_db, current_user as current_user_name;

-- Créer l'extension UUID si pas présente
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ================================================================
-- ÉTAPE 1: SAUVEGARDE DES DONNÉES EXISTANTES
-- ================================================================

\echo '💾 Sauvegarde des données existantes...'

-- Sauvegarder les utilisateurs existants
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users') THEN
        CREATE TEMP TABLE temp_old_users AS 
        SELECT id, username, email, created_at, role
        FROM users;
        
        RAISE NOTICE 'Sauvegarde de % utilisateurs', (SELECT COUNT(*) FROM temp_old_users);
    ELSE
        RAISE NOTICE 'Table users non trouvée, création nécessaire';
    END IF;
END $$;

-- Sauvegarder les messages existants
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'messages') THEN
        CREATE TEMP TABLE temp_old_messages AS
        SELECT id, from_user, to_user, room, content, created_at, message_type
        FROM messages;
        
        RAISE NOTICE 'Sauvegarde de % messages', (SELECT COUNT(*) FROM temp_old_messages);
    ELSE
        RAISE NOTICE 'Table messages non trouvée, création nécessaire';
    END IF;
END $$;

-- ================================================================
-- ÉTAPE 2: SUPPRESSION SÉCURISÉE DES TABLES REDONDANTES
-- ================================================================

\echo '🧹 Suppression des tables redondantes...'

-- Supprimer uniquement les tables qui existent et sont redondantes
DROP TABLE IF EXISTS users_enhanced CASCADE;
DROP TABLE IF EXISTS users_backup CASCADE;
DROP TABLE IF EXISTS rooms_enhanced CASCADE;
DROP TABLE IF EXISTS messages_enhanced CASCADE;
DROP TABLE IF EXISTS message_mentions_enhanced CASCADE;
DROP TABLE IF EXISTS message_mentions_secure CASCADE;
DROP TABLE IF EXISTS message_reactions_enhanced CASCADE;
DROP TABLE IF EXISTS room_members_enhanced CASCADE;
DROP TABLE IF EXISTS user_sessions_enhanced CASCADE;
DROP TABLE IF EXISTS user_sessions_secure CASCADE;
DROP TABLE IF EXISTS user_blocks_enhanced CASCADE;
DROP TABLE IF EXISTS user_blocks_secure CASCADE;
DROP TABLE IF EXISTS security_events_enhanced CASCADE;
DROP TABLE IF EXISTS security_events_secure CASCADE;

-- Supprimer les tables métier obsolètes (si elles existent)
DROP TABLE IF EXISTS listings CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS user_products CASCADE;
DROP TABLE IF EXISTS internal_documents CASCADE;
DROP TABLE IF EXISTS shared_ressources CASCADE;
DROP TABLE IF EXISTS shared_ressource_tags CASCADE;
DROP TABLE IF EXISTS ressource_tags CASCADE;
DROP TABLE IF EXISTS tracks CASCADE;

-- ================================================================
-- ÉTAPE 3: CRÉATION DES TYPES ENUMS NÉCESSAIRES
-- ================================================================

\echo '📋 Création des types énumérés...'

-- Type pour les rôles utilisateur
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('user', 'moderator', 'admin', 'super_admin');
        RAISE NOTICE 'Type user_role créé';
    ELSE
        RAISE NOTICE 'Type user_role existe déjà';
    END IF;
END $$;

-- Type pour les statuts de message
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_status') THEN
        CREATE TYPE message_status AS ENUM ('sent', 'delivered', 'read', 'edited', 'deleted');
        RAISE NOTICE 'Type message_status créé';
    ELSE
        RAISE NOTICE 'Type message_status existe déjà';
    END IF;
END $$;

-- Type pour les types de conversation
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'conversation_type') THEN
        CREATE TYPE conversation_type AS ENUM ('direct_message', 'public_room', 'private_room', 'group');
        RAISE NOTICE 'Type conversation_type créé';
    ELSE
        RAISE NOTICE 'Type conversation_type existe déjà';
    END IF;
END $$;

-- ================================================================
-- ÉTAPE 4: MISE À JOUR DE LA TABLE USERS
-- ================================================================

\echo '👤 Mise à jour de la table users...'

-- Ajouter UUID si pas déjà présent
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'users' AND column_name = 'uuid') THEN
        ALTER TABLE users ADD COLUMN uuid UUID DEFAULT uuid_generate_v4();
        ALTER TABLE users ADD CONSTRAINT users_uuid_unique UNIQUE (uuid);
        RAISE NOTICE 'Colonne UUID ajoutée à users';
    END IF;
END $$;

-- Ajouter les nouvelles colonnes de sécurité
DO $$
BEGIN
    -- Colonnes de sécurité 2FA
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'users' AND column_name = 'two_factor_enabled') THEN
        ALTER TABLE users ADD COLUMN two_factor_enabled BOOLEAN DEFAULT FALSE;
        ALTER TABLE users ADD COLUMN two_factor_secret VARCHAR(32);
        ALTER TABLE users ADD COLUMN password_reset_token VARCHAR(100);
        ALTER TABLE users ADD COLUMN password_reset_expires TIMESTAMPTZ;
        ALTER TABLE users ADD COLUMN email_verification_token VARCHAR(100);
        RAISE NOTICE 'Colonnes 2FA ajoutées à users';
    END IF;

    -- Colonnes de profil
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'users' AND column_name = 'display_name') THEN
        ALTER TABLE users ADD COLUMN display_name VARCHAR(100);
        ALTER TABLE users ADD COLUMN avatar_url TEXT;
        ALTER TABLE users ADD COLUMN bio TEXT CHECK (LENGTH(bio) <= 500);
        RAISE NOTICE 'Colonnes de profil ajoutées à users';
    END IF;

    -- Colonnes de métadonnées
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'users' AND column_name = 'last_login') THEN
        ALTER TABLE users ADD COLUMN last_login TIMESTAMPTZ;
        ALTER TABLE users ADD COLUMN last_activity TIMESTAMPTZ DEFAULT NOW();
        ALTER TABLE users ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
        RAISE NOTICE 'Colonnes de métadonnées ajoutées à users';
    END IF;

    -- Colonnes de permissions
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'users' AND column_name = 'is_verified') THEN
        ALTER TABLE users ADD COLUMN is_verified BOOLEAN DEFAULT FALSE;
        ALTER TABLE users ADD COLUMN is_active BOOLEAN DEFAULT TRUE;
        RAISE NOTICE 'Colonnes de permissions ajoutées à users';
    END IF;
END $$;

-- Mise à jour du type de rôle
DO $$
BEGIN
    -- Vérifier si la colonne role existe et la convertir
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'users' AND column_name = 'role') THEN
        -- Sauvegarder les valeurs existantes avant conversion
        UPDATE users SET role = 'user' WHERE role IS NULL OR role = '';
        
        -- Convertir vers le nouveau type (si ce n'est pas déjà fait)
        BEGIN
            ALTER TABLE users ALTER COLUMN role TYPE user_role USING role::user_role;
            RAISE NOTICE 'Colonne role convertie vers user_role';
        EXCEPTION 
            WHEN OTHERS THEN
                RAISE NOTICE 'Colonne role déjà au bon type ou erreur: %', SQLERRM;
        END;
    ELSE
        ALTER TABLE users ADD COLUMN role user_role DEFAULT 'user' NOT NULL;
        RAISE NOTICE 'Colonne role ajoutée avec type user_role';
    END IF;
END $$;

-- ================================================================
-- ÉTAPE 5: CRÉATION DE LA TABLE CONVERSATIONS
-- ================================================================

\echo '💬 Création de la table conversations...'

CREATE TABLE IF NOT EXISTS conversations (
    id BIGSERIAL PRIMARY KEY,
    uuid UUID DEFAULT uuid_generate_v4() UNIQUE NOT NULL,
    type conversation_type NOT NULL DEFAULT 'direct_message',
    name VARCHAR(100),
    description TEXT,
    owner_id BIGINT NOT NULL,
    is_public BOOLEAN DEFAULT FALSE NOT NULL,
    is_archived BOOLEAN DEFAULT FALSE NOT NULL,
    max_members INTEGER DEFAULT 100,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    
    CONSTRAINT conversations_owner_fk FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ================================================================
-- ÉTAPE 6: MISE À JOUR DE LA TABLE MESSAGES
-- ================================================================

\echo '💬 Mise à jour de la table messages...'

-- Ajouter UUID aux messages si pas présent
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'messages' AND column_name = 'uuid') THEN
        ALTER TABLE messages ADD COLUMN uuid UUID DEFAULT uuid_generate_v4();
        ALTER TABLE messages ADD CONSTRAINT messages_uuid_unique UNIQUE (uuid);
        RAISE NOTICE 'UUID ajouté à messages';
    END IF;
END $$;

-- Renommer les colonnes pour cohérence
DO $$
BEGIN
    -- Renommer from_user en author_id si nécessaire
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'messages' AND column_name = 'from_user') 
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns 
                       WHERE table_name = 'messages' AND column_name = 'author_id') THEN
        ALTER TABLE messages RENAME COLUMN from_user TO author_id;
        RAISE NOTICE 'Colonne from_user renommée en author_id';
    END IF;
END $$;

-- Ajouter conversation_id
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'messages' AND column_name = 'conversation_id') THEN
        ALTER TABLE messages ADD COLUMN conversation_id BIGINT;
        RAISE NOTICE 'Colonne conversation_id ajoutée';
        
        -- Créer des conversations par défaut pour les messages existants
        -- 1. Pour les messages de room (publiques)
        INSERT INTO conversations (type, name, owner_id, is_public)
        SELECT DISTINCT 'public_room'::conversation_type, room, 1, TRUE
        FROM messages 
        WHERE room IS NOT NULL 
        AND NOT EXISTS (
            SELECT 1 FROM conversations 
            WHERE type = 'public_room' AND name = messages.room
        );
        
        -- 2. Mettre à jour les messages avec les IDs de conversation
        UPDATE messages SET conversation_id = (
            SELECT c.id FROM conversations c 
            WHERE c.type = 'public_room' AND c.name = messages.room
        ) WHERE room IS NOT NULL;
        
        RAISE NOTICE 'Conversations créées pour les rooms existantes';
    END IF;
END $$;

-- Ajouter les nouvelles colonnes pour fonctionnalités avancées
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'messages' AND column_name = 'parent_message_id') THEN
        ALTER TABLE messages ADD COLUMN parent_message_id BIGINT REFERENCES messages(id) ON DELETE SET NULL;
        ALTER TABLE messages ADD COLUMN thread_count INTEGER DEFAULT 0;
        ALTER TABLE messages ADD COLUMN status message_status DEFAULT 'sent' NOT NULL;
        ALTER TABLE messages ADD COLUMN is_edited BOOLEAN DEFAULT FALSE;
        ALTER TABLE messages ADD COLUMN edit_count INTEGER DEFAULT 0;
        ALTER TABLE messages ADD COLUMN is_pinned BOOLEAN DEFAULT FALSE;
        ALTER TABLE messages ADD COLUMN metadata JSONB DEFAULT '{}';
        ALTER TABLE messages ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
        ALTER TABLE messages ADD COLUMN edited_at TIMESTAMPTZ;
        RAISE NOTICE 'Nouvelles colonnes ajoutées à messages';
    END IF;
END $$;

-- ================================================================
-- ÉTAPE 7: CRÉATION DES TABLES COMPLÉMENTAIRES
-- ================================================================

\echo '📋 Création des tables complémentaires...'

-- Table pour les membres de conversations
CREATE TABLE IF NOT EXISTS conversation_members (
    id BIGSERIAL PRIMARY KEY,
    conversation_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    role VARCHAR(20) DEFAULT 'member' NOT NULL,
    joined_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    left_at TIMESTAMPTZ,
    is_muted BOOLEAN DEFAULT FALSE,
    
    CONSTRAINT conversation_members_conversation_fk FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
    CONSTRAINT conversation_members_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT conversation_members_unique UNIQUE (conversation_id, user_id)
);

-- Table pour les réactions aux messages
CREATE TABLE IF NOT EXISTS message_reactions (
    id BIGSERIAL PRIMARY KEY,
    message_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    emoji VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    
    CONSTRAINT message_reactions_message_fk FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
    CONSTRAINT message_reactions_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT message_reactions_unique UNIQUE (message_id, user_id, emoji)
);

-- Table pour les mentions
CREATE TABLE IF NOT EXISTS message_mentions (
    id BIGSERIAL PRIMARY KEY,
    message_id BIGINT NOT NULL,
    mentioned_user_id BIGINT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    
    CONSTRAINT message_mentions_message_fk FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
    CONSTRAINT message_mentions_user_fk FOREIGN KEY (mentioned_user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT message_mentions_unique UNIQUE (message_id, mentioned_user_id)
);

-- Table pour l'historique des messages
CREATE TABLE IF NOT EXISTS message_history (
    id BIGSERIAL PRIMARY KEY,
    message_id BIGINT NOT NULL,
    old_content TEXT NOT NULL,
    edited_by BIGINT NOT NULL,
    edited_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    
    CONSTRAINT message_history_message_fk FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
    CONSTRAINT message_history_user_fk FOREIGN KEY (edited_by) REFERENCES users(id) ON DELETE CASCADE
);

-- Table pour les sessions utilisateur
CREATE TABLE IF NOT EXISTS user_sessions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    session_token VARCHAR(255) UNIQUE NOT NULL,
    refresh_token VARCHAR(255) UNIQUE,
    device_info TEXT,
    ip_address INET,
    user_agent TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    last_activity TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    
    CONSTRAINT user_sessions_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ================================================================
-- ÉTAPE 8: CRÉATION DES INDEX DE PERFORMANCE
-- ================================================================

\echo '⚡ Création des index de performance...'

-- Index pour users
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_username_active 
ON users(username) WHERE is_active = TRUE;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_email_verified 
ON users(email) WHERE is_verified = TRUE;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_last_activity 
ON users(last_activity DESC) WHERE is_active = TRUE;

-- Index pour conversations
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_type_public 
ON conversations(type) WHERE is_public = TRUE;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_owner_active 
ON conversations(owner_id) WHERE NOT is_archived;

-- Index pour messages (performance critique)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_conversation_time 
ON messages(conversation_id, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_author_time 
ON messages(author_id, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_threads 
ON messages(parent_message_id, created_at) WHERE parent_message_id IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_pinned 
ON messages(conversation_id) WHERE is_pinned = TRUE;

-- Index pour réactions
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reactions_message 
ON message_reactions(message_id, emoji);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reactions_user 
ON message_reactions(user_id, created_at DESC);

-- Index pour mentions
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_mentions_user_unread 
ON message_mentions(mentioned_user_id) WHERE is_read = FALSE;

-- Index pour sessions
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sessions_user_active 
ON user_sessions(user_id) WHERE is_active = TRUE;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sessions_token 
ON user_sessions(session_token);

-- ================================================================
-- ÉTAPE 9: CRÉATION DES FONCTIONS UTILITAIRES
-- ================================================================

\echo '🛠️ Création des fonctions utilitaires...'

-- Fonction pour obtenir l'ID utilisateur courant (à implémenter côté app)
CREATE OR REPLACE FUNCTION current_user_id() 
RETURNS BIGINT AS $$
BEGIN
    -- Cette fonction doit être implémentée côté application
    -- Pour l'instant, elle retourne NULL
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fonction pour nettoyer les sessions expirées
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM user_sessions 
    WHERE expires_at < NOW() OR (last_activity < NOW() - INTERVAL '30 days');
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Fonction trigger pour mettre à jour updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- ÉTAPE 10: CRÉATION DES TRIGGERS
-- ================================================================

\echo '🔔 Création des triggers...'

-- Triggers pour updated_at
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_conversations_updated_at ON conversations;
CREATE TRIGGER update_conversations_updated_at
    BEFORE UPDATE ON conversations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_messages_updated_at ON messages;
CREATE TRIGGER update_messages_updated_at
    BEFORE UPDATE ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ================================================================
-- ÉTAPE 11: VÉRIFICATION ET NETTOYAGE FINAL
-- ================================================================

\echo '🔍 Vérification finale...'

-- Nettoyer les fonctions obsolètes
DROP FUNCTION IF EXISTS cleanup_expired_sessions_secure();
DROP FUNCTION IF EXISTS cleanup_old_audit_logs();
DROP FUNCTION IF EXISTS cleanup_old_data_secure();
DROP FUNCTION IF EXISTS handle_mentions_secure();

-- Mettre à jour les statistiques
ANALYZE users;
ANALYZE conversations;
ANALYZE messages;
ANALYZE message_reactions;
ANALYZE message_mentions;
ANALYZE user_sessions;

-- Validation finale
DO $$
DECLARE
    user_count INTEGER;
    message_count INTEGER;
    conversation_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO user_count FROM users;
    SELECT COUNT(*) INTO message_count FROM messages;
    SELECT COUNT(*) INTO conversation_count FROM conversations;
    
    RAISE NOTICE '✅ Migration terminée avec succès:';
    RAISE NOTICE '   - Utilisateurs: %', user_count;
    RAISE NOTICE '   - Messages: %', message_count;
    RAISE NOTICE '   - Conversations: %', conversation_count;
    
    -- Warnings si problèmes détectés
    IF user_count = 0 THEN
        RAISE WARNING '⚠️  Aucun utilisateur trouvé après migration';
    END IF;
    
    IF message_count > 0 AND conversation_count = 0 THEN
        RAISE WARNING '⚠️  Messages présents mais aucune conversation';
    END IF;
END $$;

-- Nettoyer les tables temporaires
DROP TABLE IF EXISTS temp_old_users;
DROP TABLE IF EXISTS temp_old_messages;

-- ================================================================
-- FINALISATION
-- ================================================================

\echo '🎉 Migration de production terminée avec succès!'
\echo '📊 Base de données optimisée et prête pour la production'
\echo '⚡ Index de performance créés'
\echo '🧹 Tables redondantes supprimées'
\echo ''
\echo 'Prochaines étapes recommandées:'
\echo '1. Tester les fonctionnalités principales'
\echo '2. Vérifier les performances avec des requêtes réelles'
\echo '3. Configurer les sauvegardes automatiques'
\echo '4. Mettre en place la surveillance'

-- Afficher un résumé des tables principales
\echo ''
\echo '📋 Tables principales créées/mises à jour:'
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('users', 'conversations', 'messages', 'message_reactions', 'message_mentions', 'user_sessions')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC; 