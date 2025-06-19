-- Migration 003: Schéma amélioré - VERSION SIMPLIFIÉE

BEGIN;

-- Supprimer les fonctions qui pourraient être en conflit
DROP FUNCTION IF EXISTS cleanup_expired_sessions();
DROP FUNCTION IF EXISTS cleanup_old_data();

-- Extensions nécessaires
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Table des sessions utilisateur sécurisées
CREATE TABLE IF NOT EXISTS user_sessions_secure (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    refresh_token_hash VARCHAR(255) UNIQUE,
    device_info JSONB DEFAULT '{}',
    ip_address INET NOT NULL,
    user_agent TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
    last_used TIMESTAMPTZ DEFAULT NOW()
);

-- Table des événements de sécurité
CREATE TABLE IF NOT EXISTS security_events_secure (
    id BIGSERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    event_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) DEFAULT 'info' CHECK (severity IN ('critical', 'high', 'medium', 'low', 'info')),
    description TEXT NOT NULL,
    ip_address INET,
    user_agent TEXT,
    additional_data JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,
    resolved_by INTEGER REFERENCES users(id) ON DELETE SET NULL
);

-- Table des mentions  
CREATE TABLE IF NOT EXISTS message_mentions_secure (
    id BIGSERIAL PRIMARY KEY,
    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_read BOOLEAN DEFAULT false,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (message_id, user_id)
);

-- Table des blocages utilisateur
CREATE TABLE IF NOT EXISTS user_blocks_secure (
    id BIGSERIAL PRIMARY KEY,
    blocker_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (blocker_id, blocked_id),
    CONSTRAINT no_self_block CHECK (blocker_id != blocked_id)
);

-- Index pour les performances
CREATE INDEX IF NOT EXISTS idx_sessions_secure_user ON user_sessions_secure (user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_sessions_secure_expires ON user_sessions_secure (expires_at);
CREATE INDEX IF NOT EXISTS idx_security_events_user ON security_events_secure (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_mentions_secure_user ON message_mentions_secure (user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_blocks_secure_blocker ON user_blocks_secure (blocker_id);

-- Fonction de nettoyage des sessions expirées
CREATE OR REPLACE FUNCTION cleanup_expired_sessions_secure()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM user_sessions_secure 
    WHERE expires_at < NOW() OR last_used < NOW() - INTERVAL '30 days';
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Fonction de nettoyage général
CREATE OR REPLACE FUNCTION cleanup_old_data_secure()
RETURNS void AS $$
BEGIN
    -- Supprimer les sessions expirées
    PERFORM cleanup_expired_sessions_secure();
    
    -- Nettoyer les événements de sécurité anciens
    DELETE FROM security_events_secure 
    WHERE created_at < NOW() - INTERVAL '6 months' AND severity = 'info';
    
    RAISE NOTICE 'Nettoyage terminé';
END;
$$ LANGUAGE plpgsql;

-- Trigger pour les mentions automatiques
CREATE OR REPLACE FUNCTION handle_mentions_secure()
RETURNS TRIGGER AS $$
BEGIN
    -- Extraire les mentions @username du contenu
    INSERT INTO message_mentions_secure (message_id, user_id)
    SELECT NEW.id, u.id
    FROM users u
    WHERE NEW.content ~* ('@' || u.username || '\M')
      AND u.id != NEW.from_user
    ON CONFLICT (message_id, user_id) DO NOTHING;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_handle_mentions_secure ON messages;
CREATE TRIGGER trigger_handle_mentions_secure
    AFTER INSERT ON messages
    FOR EACH ROW EXECUTE FUNCTION handle_mentions_secure();

COMMIT; 