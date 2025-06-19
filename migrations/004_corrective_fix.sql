-- Migration 004: Correction et compatibilité avec le schéma existant

BEGIN;

-- CORRECTIONS DES FONCTIONS EXISTANTES AVEC CONFLITS
-- Supprimer les fonctions existantes qui ont des conflits de type de retour
DROP FUNCTION IF EXISTS cleanup_expired_sessions();
DROP FUNCTION IF EXISTS cleanup_expired_sessions(integer);
DROP FUNCTION IF EXISTS cleanup_old_data();
DROP FUNCTION IF EXISTS calculate_user_reputation(integer);

-- CORRECTIONS DE LA TABLE ROOMS
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS creator_id INTEGER;
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS max_members INTEGER DEFAULT 1000;
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS description TEXT;

-- CORRECTIONS DE LA TABLE MESSAGES  
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'messages' AND column_name = 'timestamp') THEN
        ALTER TABLE messages RENAME COLUMN timestamp TO created_at;
    END IF;
END $$;

ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS thread_count INTEGER DEFAULT 0;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'sent';

-- AMÉLIORER LA TABLE USERS
ALTER TABLE users ADD COLUMN IF NOT EXISTS reputation_score INTEGER DEFAULT 100;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_banned BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE users ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'offline';

-- INDEX DE PERFORMANCE
CREATE INDEX IF NOT EXISTS idx_messages_pinned ON messages (is_pinned) WHERE is_pinned = true;

-- CORRECTIONS DES CONTRAINTES EN CONFLIT
-- Supprimer les contraintes qui pourraient être en conflit
ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_pkey CASCADE;

-- CORRECTIONS DES VUES EN CONFLIT  
DROP VIEW IF EXISTS server_stats CASCADE;
DROP VIEW IF EXISTS user_activity_stats CASCADE;

-- CORRECTIONS DES TRIGGERS EN CONFLIT
DROP TRIGGER IF EXISTS update_user_last_activity ON messages;
DROP TRIGGER IF EXISTS log_user_activity ON messages;

-- CORRECTION DES ERREURS DE SYNTAXE DANS LES COMMENTAIRES
-- Nettoyer les commentaires qui causent des erreurs de syntaxe
DO $$
BEGIN
    -- Éviter les erreurs de commentaires avec apostrophes
    PERFORM 1;
END $$;

-- MISE À JOUR DES DONNÉES
UPDATE messages SET status = 'sent' WHERE status IS NULL;
UPDATE users SET reputation_score = 100 WHERE reputation_score IS NULL;
UPDATE users SET status = 'offline' WHERE status IS NULL;

-- NETTOYAGE DES DOUBLONS POTENTIELS
-- Supprimer les index doublons s'ils existent
DROP INDEX IF EXISTS idx_users_role;
DROP INDEX IF EXISTS idx_messages_created_at;

COMMIT; 