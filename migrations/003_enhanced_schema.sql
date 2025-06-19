-- Migration 003: Schéma amélioré avec sécurité renforcée et séparation DM/salons

-- Extension pour UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ================================================
-- UTILISATEURS AVEC SÉCURITÉ RENFORCÉE
-- ================================================

CREATE TABLE IF NOT EXISTS users_enhanced (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    
    -- Rôles et permissions
    role VARCHAR(20) NOT NULL DEFAULT 'user' CHECK (role IN ('admin', 'moderator', 'user', 'guest')),
    
    -- Statut et sécurité
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_banned BOOLEAN NOT NULL DEFAULT false,
    is_verified BOOLEAN NOT NULL DEFAULT false,
    
    -- Statut de présence
    status VARCHAR(20) DEFAULT 'offline' CHECK (status IN ('online', 'away', 'busy', 'invisible', 'offline')),
    status_message VARCHAR(100),
    
    -- Modération
    reputation_score INTEGER DEFAULT 100,
    
    -- Métadonnées
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ================================================
-- SALONS AVEC GESTION AVANCÉE
-- ================================================

CREATE TABLE IF NOT EXISTS rooms_enhanced (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    
    -- Propriétaire
    owner_id INTEGER NOT NULL REFERENCES users_enhanced(id) ON DELETE CASCADE,
    
    -- Configuration
    is_public BOOLEAN NOT NULL DEFAULT true,
    is_archived BOOLEAN DEFAULT false,
    max_members INTEGER DEFAULT 1000,
    
    -- Métadonnées
    member_count INTEGER DEFAULT 0,
    message_count INTEGER DEFAULT 0,
    
    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ================================================
-- MESSAGES UNIFIÉS
-- ================================================

CREATE TABLE IF NOT EXISTS messages_enhanced (
    id BIGSERIAL PRIMARY KEY,
    
    -- Type et contenu
    message_type VARCHAR(20) NOT NULL CHECK (message_type IN ('room_message', 'direct_message', 'system_message')),
    content TEXT NOT NULL CHECK (LENGTH(content) <= 4000),
    
    -- Auteur
    author_id INTEGER NOT NULL REFERENCES users_enhanced(id) ON DELETE CASCADE,
    author_username VARCHAR(50) NOT NULL,
    
    -- Destination (exclusion mutuelle)
    room_id VARCHAR(100) REFERENCES rooms_enhanced(id) ON DELETE CASCADE,
    recipient_id INTEGER REFERENCES users_enhanced(id) ON DELETE CASCADE,
    recipient_username VARCHAR(50),
    
    -- Threading
    parent_message_id BIGINT REFERENCES messages_enhanced(id) ON DELETE SET NULL,
    thread_count INTEGER DEFAULT 0,
    
    -- Statut
    status VARCHAR(20) DEFAULT 'sent' CHECK (status IN ('sent', 'delivered', 'read', 'edited', 'deleted')),
    is_pinned BOOLEAN DEFAULT false,
    is_edited BOOLEAN DEFAULT false,
    original_content TEXT,
    
    -- Modération
    is_flagged BOOLEAN DEFAULT false,
    moderation_notes TEXT,
    
    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    
    -- Contraintes logiques
    CONSTRAINT message_destination_check CHECK (
        (message_type = 'room_message' AND room_id IS NOT NULL AND recipient_id IS NULL) OR
        (message_type = 'direct_message' AND room_id IS NULL AND recipient_id IS NOT NULL) OR
        (message_type = 'system_message')
    )
);

-- ================================================
-- RÉACTIONS AUX MESSAGES
-- ================================================

CREATE TABLE IF NOT EXISTS message_reactions_enhanced (
    id BIGSERIAL PRIMARY KEY,
    message_id BIGINT NOT NULL REFERENCES messages_enhanced(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users_enhanced(id) ON DELETE CASCADE,
    emoji VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    UNIQUE (message_id, user_id, emoji)
);

-- ================================================
-- MENTIONS DANS LES MESSAGES
-- ================================================

CREATE TABLE IF NOT EXISTS message_mentions_enhanced (
    id BIGSERIAL PRIMARY KEY,
    message_id BIGINT NOT NULL REFERENCES messages_enhanced(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users_enhanced(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_read BOOLEAN DEFAULT false,
    
    UNIQUE (message_id, user_id)
);

-- ================================================
-- MEMBRES DES SALONS
-- ================================================

CREATE TABLE IF NOT EXISTS room_members_enhanced (
    room_id VARCHAR(100) NOT NULL REFERENCES rooms_enhanced(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users_enhanced(id) ON DELETE CASCADE,
    
    role VARCHAR(20) DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'moderator', 'member')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_read_message_id BIGINT,
    
    PRIMARY KEY (room_id, user_id)
);

-- ================================================
-- BLOCAGES UTILISATEURS
-- ================================================

CREATE TABLE IF NOT EXISTS user_blocks_enhanced (
    id BIGSERIAL PRIMARY KEY,
    blocker_id INTEGER NOT NULL REFERENCES users_enhanced(id) ON DELETE CASCADE,
    blocked_id INTEGER NOT NULL REFERENCES users_enhanced(id) ON DELETE CASCADE,
    reason VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    UNIQUE (blocker_id, blocked_id),
    CONSTRAINT no_self_block CHECK (blocker_id != blocked_id)
);

-- ================================================
-- SESSIONS SÉCURISÉES
-- ================================================

CREATE TABLE IF NOT EXISTS user_sessions_enhanced (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INTEGER NOT NULL REFERENCES users_enhanced(id) ON DELETE CASCADE,
    
    token_hash VARCHAR(128) NOT NULL UNIQUE,
    ip_address INET,
    user_agent TEXT,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_activity TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    is_active BOOLEAN DEFAULT true
);

-- ================================================
-- LOGS DE SÉCURITÉ
-- ================================================

CREATE TABLE IF NOT EXISTS security_events_enhanced (
    id BIGSERIAL PRIMARY KEY,
    
    event_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) DEFAULT 'info' CHECK (severity IN ('debug', 'info', 'warning', 'error', 'critical')),
    
    user_id INTEGER REFERENCES users_enhanced(id) ON DELETE SET NULL,
    ip_address INET,
    user_agent TEXT,
    
    details JSONB DEFAULT '{}'::jsonb,
    success BOOLEAN,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ================================================
-- INDEX POUR PERFORMANCE
-- ================================================

-- Messages
CREATE INDEX IF NOT EXISTS idx_messages_room_enhanced ON messages_enhanced (room_id, created_at DESC) WHERE message_type = 'room_message' AND status != 'deleted';
CREATE INDEX IF NOT EXISTS idx_messages_dm_enhanced ON messages_enhanced (author_id, recipient_id, created_at DESC) WHERE message_type = 'direct_message' AND status != 'deleted';
CREATE INDEX IF NOT EXISTS idx_messages_dm_reverse_enhanced ON messages_enhanced (recipient_id, author_id, created_at DESC) WHERE message_type = 'direct_message' AND status != 'deleted';

-- Réactions
CREATE INDEX IF NOT EXISTS idx_reactions_message_enhanced ON message_reactions_enhanced (message_id);
CREATE INDEX IF NOT EXISTS idx_reactions_user_enhanced ON message_reactions_enhanced (user_id);

-- Mentions
CREATE INDEX IF NOT EXISTS idx_mentions_user_enhanced ON message_mentions_enhanced (user_id, is_read);

-- Sessions
CREATE INDEX IF NOT EXISTS idx_sessions_user_enhanced ON user_sessions_enhanced (user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_sessions_token_enhanced ON user_sessions_enhanced (token_hash);

-- ================================================
-- TRIGGERS
-- ================================================

-- Fonction pour mettre à jour updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Appliquer aux tables principales
CREATE TRIGGER update_users_enhanced_updated_at 
    BEFORE UPDATE ON users_enhanced 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_rooms_enhanced_updated_at 
    BEFORE UPDATE ON rooms_enhanced 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ================================================
-- FONCTIONS UTILITAIRES
-- ================================================

-- Fonction pour nettoyer les sessions expirées
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS void AS $$
BEGIN
    DELETE FROM user_sessions_enhanced 
    WHERE expires_at < NOW() AND is_active = false;
END;
$$ LANGUAGE plpgsql;

-- ================================================
-- COMMENTAIRES
-- ================================================

COMMENT ON TABLE users_enhanced IS 'Utilisateurs avec sécurité renforcée';
COMMENT ON TABLE messages_enhanced IS 'Messages unifiés avec séparation logique DM/salons';
COMMENT ON TABLE message_reactions_enhanced IS 'Réactions aux messages';
COMMENT ON TABLE message_mentions_enhanced IS 'Mentions d''utilisateurs';
COMMENT ON TABLE user_blocks_enhanced IS 'Blocages entre utilisateurs';
COMMENT ON TABLE user_sessions_enhanced IS 'Sessions sécurisées';
COMMENT ON TABLE security_events_enhanced IS 'Journal de sécurité'; 