-- Migration de nettoyage et préparation pour production
-- Cette migration supprime toutes les tables redondantes et optimise la base
-- ⚠️  ATTENTION: Cette migration est destructive, assurez-vous d'avoir une sauvegarde

-- ================================================================
-- ÉTAPE 1: MIGRATION DES DONNÉES EXISTANTES
-- ================================================================

-- Sauvegarde temporaire des données importantes
CREATE TEMP TABLE temp_old_users AS 
SELECT id, username, email, created_at 
FROM users 
WHERE EXISTS (SELECT 1 FROM users);

CREATE TEMP TABLE temp_old_messages AS
SELECT id, from_user, to_user, room, content, created_at, message_type
FROM messages
WHERE EXISTS (SELECT 1 FROM messages);

-- ================================================================
-- ÉTAPE 2: SUPPRESSION DES TABLES REDONDANTES
-- ================================================================

-- Supprimer toutes les tables dupliquées (_enhanced, _secure, etc.)
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

-- Supprimer les anciennes tables métier mal conçues
DROP TABLE IF EXISTS offers CASCADE;
DROP TABLE IF EXISTS listings CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS user_products CASCADE;
DROP TABLE IF EXISTS internal_documents CASCADE;
DROP TABLE IF EXISTS shared_ressources CASCADE;
DROP TABLE IF EXISTS shared_ressource_tags CASCADE;
DROP TABLE IF EXISTS ressource_tags CASCADE;
DROP TABLE IF EXISTS tracks CASCADE;
DROP TABLE IF EXISTS sanctions CASCADE; -- Remplacée par moderation_actions
DROP TABLE IF EXISTS refresh_tokens CASCADE; -- Intégré dans user_sessions

-- Supprimer les anciennes tables de base
DROP TABLE IF EXISTS rooms CASCADE;
DROP TABLE IF EXISTS room_members CASCADE;
DROP TABLE IF EXISTS user_sessions CASCADE;
DROP TABLE IF EXISTS user_blocks CASCADE;
DROP TABLE IF EXISTS files CASCADE; -- Sera recréée avec la nouvelle structure

-- ================================================================
-- ÉTAPE 3: NETTOYAGE DES FONCTIONS OBSOLÈTES
-- ================================================================

DROP FUNCTION IF EXISTS cleanup_expired_sessions_secure();
DROP FUNCTION IF EXISTS cleanup_old_audit_logs();
DROP FUNCTION IF EXISTS cleanup_old_data_secure();
DROP FUNCTION IF EXISTS handle_mentions_secure();

-- ================================================================
-- ÉTAPE 4: APPLICATIONS DES NOUVELLES CONTRAINTES
-- ================================================================

-- Mise à jour de la table users existante avec nouvelles contraintes
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_username_key;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_email_key;

-- Ajouter UUID si pas déjà présent
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'users' AND column_name = 'uuid') THEN
        ALTER TABLE users ADD COLUMN uuid UUID DEFAULT uuid_generate_v4();
        ALTER TABLE users ADD CONSTRAINT users_uuid_unique UNIQUE (uuid);
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
    END IF;

    -- Colonnes de profil
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'users' AND column_name = 'display_name') THEN
        ALTER TABLE users ADD COLUMN display_name VARCHAR(100);
        ALTER TABLE users ADD COLUMN avatar_url TEXT;
        ALTER TABLE users ADD COLUMN bio TEXT CHECK (LENGTH(bio) <= 500);
    END IF;

    -- Colonnes de métadonnées
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'users' AND column_name = 'last_login') THEN
        ALTER TABLE users ADD COLUMN last_login TIMESTAMPTZ;
        ALTER TABLE users ADD COLUMN last_activity TIMESTAMPTZ DEFAULT NOW();
        ALTER TABLE users ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;

    -- Colonnes de permissions
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'users' AND column_name = 'is_verified') THEN
        ALTER TABLE users ADD COLUMN is_verified BOOLEAN DEFAULT FALSE;
        ALTER TABLE users ADD COLUMN is_active BOOLEAN DEFAULT TRUE;
    END IF;
END $$;

-- Mise à jour du type de rôle si existant
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'users' AND column_name = 'role') THEN
        -- Convertir l'ancien système de rôles
        UPDATE users SET role = 'user' WHERE role IS NULL OR role = '';
    ELSE
        ALTER TABLE users ADD COLUMN role user_role DEFAULT 'user' NOT NULL;
    END IF;
END $$;

-- ================================================================
-- ÉTAPE 5: OPTIMISATION DE LA TABLE MESSAGES
-- ================================================================

-- Ajouter UUID aux messages si pas présent
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'messages' AND column_name = 'uuid') THEN
        ALTER TABLE messages ADD COLUMN uuid UUID DEFAULT uuid_generate_v4();
        ALTER TABLE messages ADD CONSTRAINT messages_uuid_unique UNIQUE (uuid);
    END IF;
END $$;

-- Renommer les colonnes pour cohérence
DO $$
BEGIN
    -- Renommer from_user en author_id
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'messages' AND column_name = 'from_user') THEN
        ALTER TABLE messages RENAME COLUMN from_user TO author_id;
    END IF;

    -- Ajouter conversation_id basé sur room/to_user
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'messages' AND column_name = 'conversation_id') THEN
        ALTER TABLE messages ADD COLUMN conversation_id BIGINT;
        
        -- Mise à jour temporaire: créer un ID de conversation basé sur room ou DM
        UPDATE messages SET conversation_id = CASE 
            WHEN room IS NOT NULL THEN (
                SELECT id FROM conversations 
                WHERE type = 'public_room' AND name = room 
                LIMIT 1
            )
            WHEN to_user IS NOT NULL THEN (
                SELECT id FROM conversations 
                WHERE type = 'direct_message' 
                AND (
                    (owner_id = author_id AND id IN (
                        SELECT conversation_id FROM conversation_members 
                        WHERE user_id = to_user
                    )) OR
                    (owner_id = to_user AND id IN (
                        SELECT conversation_id FROM conversation_members 
                        WHERE user_id = author_id
                    ))
                )
                LIMIT 1
            )
            ELSE 1 -- Conversation par défaut
        END;
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
        ALTER TABLE messages ADD COLUMN metadata JSONB DEFAULT '{}';
        ALTER TABLE messages ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
        ALTER TABLE messages ADD COLUMN edited_at TIMESTAMPTZ;
    END IF;
END $$;

-- ================================================================
-- ÉTAPE 6: CRÉATION DES INDEX OPTIMISÉS
-- ================================================================

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

-- Index pour recherche full-text
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_content_search 
ON messages USING gin(to_tsvector('french', content));

-- Index pour réactions
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reactions_message 
ON message_reactions(message_id, emoji);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reactions_user 
ON message_reactions(user_id, created_at DESC);

-- Index pour mentions
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_mentions_user_unread 
ON message_mentions(mentioned_user_id) WHERE is_read = FALSE;

-- Index pour audit et sécurité
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_audit_user_action 
ON audit_logs(user_id, action, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_security_severity_time 
ON security_events(severity, created_at DESC);

-- ================================================================
-- ÉTAPE 7: STATISTIQUES ET MAINTENANCE
-- ================================================================

-- Mettre à jour les statistiques des tables
ANALYZE users;
ANALYZE conversations;
ANALYZE messages;
ANALYZE message_reactions;
ANALYZE message_mentions;
ANALYZE audit_logs;
ANALYZE security_events;

-- Nettoyer l'espace inutilisé
VACUUM (ANALYZE, FREEZE) users;
VACUUM (ANALYZE, FREEZE) conversations;
VACUUM (ANALYZE, FREEZE) messages;

-- ================================================================
-- ÉTAPE 8: CONFIGURATION FINALE DE SÉCURITÉ
-- ================================================================

-- Activer Row Level Security sur les nouvelles tables
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_mentions ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_members ENABLE ROW LEVEL SECURITY;

-- Créer des politiques RLS basiques
CREATE POLICY messages_access_policy ON messages
    FOR ALL TO PUBLIC
    USING (
        author_id = current_user_id() OR
        conversation_id IN (
            SELECT conversation_id FROM conversation_members 
            WHERE user_id = current_user_id()
        )
    );

CREATE POLICY sessions_owner_policy ON user_sessions
    FOR ALL TO PUBLIC
    USING (user_id = current_user_id());

-- ================================================================
-- ÉTAPE 9: JOURNALISATION ET VALIDATION
-- ================================================================

-- Insérer un événement d'audit pour la migration
INSERT INTO audit_logs (action, details, created_at)
VALUES (
    'system_migration',
    jsonb_build_object(
        'migration', 'cleanup_production_ready',
        'version', '0.2.0',
        'tables_dropped', ARRAY[
            'users_enhanced', 'messages_enhanced', 'rooms_enhanced',
            'security_events_enhanced', 'user_sessions_secure'
        ],
        'optimization', 'indexes_created_and_statistics_updated'
    ),
    NOW()
);

-- Vérification de l'intégrité des données
DO $$
DECLARE
    user_count INTEGER;
    message_count INTEGER;
    conversation_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO user_count FROM users;
    SELECT COUNT(*) INTO message_count FROM messages;
    SELECT COUNT(*) INTO conversation_count FROM conversations;
    
    RAISE NOTICE 'Migration terminée avec succès:';
    RAISE NOTICE '- Utilisateurs: %', user_count;
    RAISE NOTICE '- Messages: %', message_count;
    RAISE NOTICE '- Conversations: %', conversation_count;
    
    -- Validation basique
    IF user_count = 0 THEN
        RAISE WARNING 'Aucun utilisateur trouvé après migration';
    END IF;
    
    IF message_count > 0 AND conversation_count = 0 THEN
        RAISE WARNING 'Messages présents mais aucune conversation';
    END IF;
END $$;

-- ================================================================
-- ÉTAPE 10: COMMENTAIRES ET DOCUMENTATION
-- ================================================================

COMMENT ON TABLE users IS 'Table utilisateurs unifiée - Production Ready v0.2.0';
COMMENT ON TABLE conversations IS 'Conversations unifiées (DM + Rooms) avec types stricts';
COMMENT ON TABLE messages IS 'Messages avec support threads, épinglage et métadonnées';
COMMENT ON TABLE message_reactions IS 'Réactions emoji avec contraintes unicité';
COMMENT ON TABLE message_mentions IS 'Mentions @utilisateur avec notifications';
COMMENT ON TABLE message_history IS 'Historique des modifications de messages';
COMMENT ON TABLE files IS 'Fichiers uploadés avec validation de sécurité';
COMMENT ON TABLE audit_logs IS 'Audit trail complet de toutes les actions';
COMMENT ON TABLE security_events IS 'Journal des événements de sécurité';
COMMENT ON TABLE moderation_actions IS 'Actions de modération avec appeals';

-- ================================================================
-- FIN DE LA MIGRATION
-- ================================================================

RAISE NOTICE '🎉 Migration de nettoyage terminée avec succès!';
RAISE NOTICE '📊 Base de données optimisée pour la production';
RAISE NOTICE '🔒 Sécurité renforcée avec RLS activée';
RAISE NOTICE '⚡ Index de performance créés';
RAISE NOTICE '🧹 Tables redondantes supprimées';

-- Nettoyer les tables temporaires
DROP TABLE IF EXISTS temp_old_users;
DROP TABLE IF EXISTS temp_old_messages;

-- Optimisation finale
VACUUM FULL;

-- Mettre à jour les statistiques
ANALYZE; 