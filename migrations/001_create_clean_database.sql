-- Migration: Structure de base de données unifiée et sécurisée pour chat server
-- Création: 2025-01-XX
-- Version: 1.0.0 Production Ready

-- Extensions requises
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gin";

-- ================================================================
-- ÉNUMÉRATIONS ET TYPES PERSONNALISÉS
-- ================================================================

-- Types d'utilisateurs avec permissions graduelles
CREATE TYPE user_role AS ENUM ('banned', 'user', 'moderator', 'admin', 'owner');

-- Types de messages unifiés (DM + Rooms)  
CREATE TYPE message_type AS ENUM ('text', 'image', 'file', 'system', 'reaction_only');

-- Types de conversations
CREATE TYPE conversation_type AS ENUM ('direct_message', 'group_chat', 'public_room', 'private_room');

-- Statut des messages
CREATE TYPE message_status AS ENUM ('sending', 'sent', 'delivered', 'read', 'edited', 'deleted');

-- Niveau de sécurité des événements
CREATE TYPE security_level AS ENUM ('info', 'warning', 'error', 'critical');

-- Types d'actions pour audit
CREATE TYPE audit_action AS ENUM (
    'login', 'logout', 'send_message', 'edit_message', 'delete_message',
    'create_room', 'join_room', 'leave_room', 'ban_user', 'unban_user',
    'upload_file', 'change_settings', 'password_change'
);

-- ================================================================
-- TABLES PRINCIPALES
-- ================================================================

-- Table utilisateurs unifiée et sécurisée
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    uuid UUID UNIQUE NOT NULL DEFAULT uuid_generate_v4(),
    
    -- Authentification
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL, -- bcrypt hash
    
    -- Profil
    display_name VARCHAR(100),
    avatar_url TEXT,
    bio TEXT CHECK (LENGTH(bio) <= 500),
    
    -- Permissions et statut
    role user_role DEFAULT 'user' NOT NULL,
    is_verified BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    
    -- Paramètres de sécurité
    two_factor_enabled BOOLEAN DEFAULT FALSE,
    two_factor_secret VARCHAR(32), -- Encrypted TOTP secret
    password_reset_token VARCHAR(100),
    password_reset_expires TIMESTAMPTZ,
    email_verification_token VARCHAR(100),
    
    -- Métadonnées
    last_login TIMESTAMPTZ,
    last_activity TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    
    -- Contraintes
    CONSTRAINT username_length CHECK (LENGTH(username) BETWEEN 3 AND 50),
    CONSTRAINT username_format CHECK (username ~ '^[a-zA-Z0-9_-]+$'),
    CONSTRAINT email_format CHECK (email ~ '^[^@]+@[^@]+\.[^@]+$')
);

-- Sessions utilisateur sécurisées (remplace toutes les tables session*)
CREATE TABLE user_sessions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Identification session
    session_token VARCHAR(255) UNIQUE NOT NULL, -- JWT ou token sécurisé
    refresh_token VARCHAR(255) UNIQUE,
    
    -- Métadonnées de connexion
    ip_address INET NOT NULL,
    user_agent TEXT,
    device_info JSONB DEFAULT '{}',
    
    -- Gestion temporelle
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    last_used TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    
    -- Sécurité
    is_active BOOLEAN DEFAULT TRUE,
    logout_reason VARCHAR(100) -- 'manual', 'expired', 'forced', 'security'
);

-- Conversations unifiées (remplace rooms + DM)
CREATE TABLE conversations (
    id BIGSERIAL PRIMARY KEY,
    uuid UUID UNIQUE NOT NULL DEFAULT uuid_generate_v4(),
    
    -- Type et métadonnées
    type conversation_type NOT NULL,
    name VARCHAR(100), -- NULL pour DM
    description TEXT CHECK (LENGTH(description) <= 1000),
    avatar_url TEXT,
    
    -- Propriétaire (NULL pour DM système)
    owner_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    
    -- Paramètres
    is_public BOOLEAN DEFAULT FALSE,
    is_archived BOOLEAN DEFAULT FALSE,
    max_members INTEGER DEFAULT 1000 CHECK (max_members > 0),
    
    -- Statistiques (mise à jour par triggers)
    member_count INTEGER DEFAULT 0,
    message_count INTEGER DEFAULT 0,
    last_message_at TIMESTAMPTZ,
    
    -- Métadonnées
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    
    -- Contraintes
    CONSTRAINT conversation_name_required CHECK (
        (type IN ('public_room', 'private_room', 'group_chat') AND name IS NOT NULL) OR
        (type = 'direct_message' AND name IS NULL)
    )
);

-- Membres des conversations avec rôles
CREATE TABLE conversation_members (
    id BIGSERIAL PRIMARY KEY,
    conversation_id BIGINT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Permissions dans la conversation
    role VARCHAR(20) DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'moderator', 'member', 'read_only')),
    
    -- Métadonnées
    joined_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    last_read_message_id BIGINT, -- Pour marquer les messages lus
    
    -- Notifications
    notifications_enabled BOOLEAN DEFAULT TRUE,
    
    -- Contraintes
    UNIQUE(conversation_id, user_id)
);

-- Messages unifiés (DM + Rooms)
CREATE TABLE messages (
    id BIGSERIAL PRIMARY KEY,
    uuid UUID UNIQUE NOT NULL DEFAULT uuid_generate_v4(),
    
    -- Conversation et auteur
    conversation_id BIGINT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    author_id BIGINT NOT NULL REFERENCES users(id) ON DELETE SET NULL,
    
    -- Contenu
    content TEXT NOT NULL CHECK (LENGTH(content) <= 4000),
    content_type message_type DEFAULT 'text' NOT NULL,
    
    -- Hiérarchie (fils de discussion)
    parent_message_id BIGINT REFERENCES messages(id) ON DELETE SET NULL,
    thread_count INTEGER DEFAULT 0,
    
    -- État
    status message_status DEFAULT 'sent' NOT NULL,
    is_pinned BOOLEAN DEFAULT FALSE,
    is_edited BOOLEAN DEFAULT FALSE,
    edit_count INTEGER DEFAULT 0,
    
    -- Métadonnées
    metadata JSONB DEFAULT '{}', -- Pièces jointes, mentions, etc.
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    edited_at TIMESTAMPTZ,
    
    -- Index pour performance
    CONSTRAINT content_not_empty CHECK (LENGTH(TRIM(content)) > 0)
);

-- Réactions aux messages
CREATE TABLE message_reactions (
    id BIGSERIAL PRIMARY KEY,
    message_id BIGINT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Réaction (emoji Unicode ou nom)
    emoji VARCHAR(100) NOT NULL,
    
    -- Métadonnées
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    
    -- Une seule réaction par utilisateur par message par emoji
    UNIQUE(message_id, user_id, emoji)
);

-- Mentions dans les messages
CREATE TABLE message_mentions (
    id BIGSERIAL PRIMARY KEY,
    message_id BIGINT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    mentioned_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Métadonnées
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    
    -- Contraintes
    UNIQUE(message_id, mentioned_user_id)
);

-- Historique des modifications de messages
CREATE TABLE message_history (
    id BIGSERIAL PRIMARY KEY,
    message_id BIGINT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    
    -- Contenu avant modification
    previous_content TEXT NOT NULL,
    edit_reason VARCHAR(255),
    
    -- Métadonnées
    edited_by BIGINT NOT NULL REFERENCES users(id) ON DELETE SET NULL,
    edited_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Fichiers uploadés avec sécurité
CREATE TABLE files (
    id BIGSERIAL PRIMARY KEY,
    uuid UUID UNIQUE NOT NULL DEFAULT uuid_generate_v4(),
    
    -- Propriétaire
    uploaded_by BIGINT NOT NULL REFERENCES users(id) ON DELETE SET NULL,
    
    -- Informations fichier
    filename VARCHAR(255) NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    file_path TEXT NOT NULL,
    file_size BIGINT NOT NULL CHECK (file_size > 0),
    mime_type VARCHAR(100) NOT NULL,
    checksum VARCHAR(64) NOT NULL, -- SHA-256 pour vérification intégrité
    
    -- Sécurité
    is_scanned BOOLEAN DEFAULT FALSE,
    scan_result JSONB, -- Résultat antivirus
    is_safe BOOLEAN DEFAULT NULL,
    
    -- Métadonnées
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    expires_at TIMESTAMPTZ, -- Pour fichiers temporaires
    
    -- Contraintes
    CONSTRAINT valid_file_size CHECK (file_size <= 100 * 1024 * 1024), -- 100MB max
    CONSTRAINT valid_filename CHECK (LENGTH(filename) > 0)
);

-- Blocages entre utilisateurs
CREATE TABLE user_blocks (
    id BIGSERIAL PRIMARY KEY,
    blocker_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Raison
    reason VARCHAR(255),
    
    -- Métadonnées
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    
    -- Contraintes
    UNIQUE(blocker_id, blocked_id),
    CHECK (blocker_id != blocked_id)
);

-- ================================================================
-- TABLES DE SÉCURITÉ ET AUDIT
-- ================================================================

-- Événements de sécurité unifiés
CREATE TABLE security_events (
    id BIGSERIAL PRIMARY KEY,
    
    -- Utilisateur concerné (peut être NULL pour événements système)
    user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    
    -- Détails événement
    event_type VARCHAR(50) NOT NULL,
    severity security_level DEFAULT 'info' NOT NULL,
    description TEXT NOT NULL,
    
    -- Contexte technique
    ip_address INET,
    user_agent TEXT,
    request_data JSONB DEFAULT '{}',
    
    -- Résolution
    resolved_at TIMESTAMPTZ,
    resolved_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    resolution_notes TEXT,
    
    -- Métadonnées
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Audit trail complet
CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    
    -- Acteur
    user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    session_id BIGINT REFERENCES user_sessions(id) ON DELETE SET NULL,
    
    -- Action
    action audit_action NOT NULL,
    resource_type VARCHAR(50),
    resource_id VARCHAR(100),
    
    -- Détails
    details JSONB DEFAULT '{}',
    old_values JSONB,
    new_values JSONB,
    
    -- Contexte
    ip_address INET,
    user_agent TEXT,
    
    -- Métadonnées
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Sanctions de modération
CREATE TABLE moderation_actions (
    id BIGSERIAL PRIMARY KEY,
    
    -- Utilisateur sanctionné
    target_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    moderator_id BIGINT NOT NULL REFERENCES users(id) ON DELETE SET NULL,
    
    -- Type de sanction
    action_type VARCHAR(50) NOT NULL CHECK (action_type IN ('warn', 'mute', 'kick', 'ban', 'unban')),
    
    -- Détails
    reason TEXT NOT NULL,
    public_reason VARCHAR(255), -- Raison affichée publiquement
    internal_notes TEXT, -- Notes internes pour modérateurs
    
    -- Durée (NULL = permanent)
    duration INTERVAL,
    expires_at TIMESTAMPTZ,
    
    -- État
    is_active BOOLEAN DEFAULT TRUE,
    appeal_message TEXT,
    appeal_handled_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    appeal_handled_at TIMESTAMPTZ,
    
    -- Métadonnées
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ================================================================
-- INDEX POUR PERFORMANCE
-- ================================================================

-- Users
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_last_activity ON users(last_activity);

-- Sessions
CREATE INDEX idx_sessions_user_id ON user_sessions(user_id);
CREATE INDEX idx_sessions_token ON user_sessions(session_token);
CREATE INDEX idx_sessions_expires ON user_sessions(expires_at);
CREATE INDEX idx_sessions_ip ON user_sessions(ip_address);

-- Conversations
CREATE INDEX idx_conversations_type ON conversations(type);
CREATE INDEX idx_conversations_owner ON conversations(owner_id);
CREATE INDEX idx_conversations_public ON conversations(is_public) WHERE is_public = TRUE;
CREATE INDEX idx_conversations_updated ON conversations(updated_at);

-- Conversation Members
CREATE INDEX idx_members_conversation ON conversation_members(conversation_id);
CREATE INDEX idx_members_user ON conversation_members(user_id);
CREATE INDEX idx_members_role ON conversation_members(conversation_id, role);

-- Messages
CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at DESC);
CREATE INDEX idx_messages_author ON messages(author_id);
CREATE INDEX idx_messages_parent ON messages(parent_message_id);
CREATE INDEX idx_messages_pinned ON messages(conversation_id, is_pinned) WHERE is_pinned = TRUE;
CREATE INDEX idx_messages_status ON messages(status);
CREATE INDEX idx_messages_content_search ON messages USING gin(to_tsvector('french', content));

-- Reactions & Mentions
CREATE INDEX idx_reactions_message ON message_reactions(message_id);
CREATE INDEX idx_mentions_user ON message_mentions(mentioned_user_id, is_read);

-- Security & Audit
CREATE INDEX idx_security_user ON security_events(user_id, created_at DESC);
CREATE INDEX idx_security_severity ON security_events(severity, created_at DESC);
CREATE INDEX idx_audit_user ON audit_logs(user_id, created_at DESC);
CREATE INDEX idx_audit_action ON audit_logs(action, created_at DESC);

-- ================================================================
-- FONCTIONS ET TRIGGERS
-- ================================================================

-- Fonction de mise à jour automatique updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers pour updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_conversations_updated_at BEFORE UPDATE ON conversations FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_messages_updated_at BEFORE UPDATE ON messages FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Fonction de gestion des mentions automatiques
CREATE OR REPLACE FUNCTION handle_message_mentions()
RETURNS TRIGGER AS $$
BEGIN
    -- Extraire et insérer les mentions @username
    INSERT INTO message_mentions (message_id, mentioned_user_id)
    SELECT NEW.id, u.id
    FROM users u
    WHERE NEW.content ~* ('@' || u.username || '\M')
      AND u.id != NEW.author_id
      AND u.is_active = TRUE
    ON CONFLICT (message_id, mentioned_user_id) DO NOTHING;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger pour mentions
CREATE TRIGGER trigger_handle_mentions AFTER INSERT ON messages FOR EACH ROW EXECUTE FUNCTION handle_message_mentions();

-- Fonction de mise à jour des statistiques de conversation
CREATE OR REPLACE FUNCTION update_conversation_stats()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Nouveau message
        UPDATE conversations 
        SET message_count = message_count + 1,
            last_message_at = NEW.created_at
        WHERE id = NEW.conversation_id;
        
    ELSIF TG_OP = 'DELETE' THEN
        -- Message supprimé
        UPDATE conversations 
        SET message_count = GREATEST(message_count - 1, 0)
        WHERE id = OLD.conversation_id;
    END IF;
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Trigger pour statistiques
CREATE TRIGGER trigger_update_conversation_stats 
    AFTER INSERT OR DELETE ON messages 
    FOR EACH ROW EXECUTE FUNCTION update_conversation_stats();

-- Fonction de nettoyage automatique des sessions expirées
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM user_sessions 
    WHERE expires_at < NOW() 
       OR (last_used < NOW() - INTERVAL '30 days' AND is_active = FALSE);
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    INSERT INTO audit_logs (action, details, created_at)
    VALUES ('system_cleanup', jsonb_build_object('cleaned_sessions', deleted_count), NOW());
    
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Fonction de nettoyage des anciens événements de sécurité
CREATE OR REPLACE FUNCTION cleanup_old_security_events()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM security_events 
    WHERE created_at < NOW() - INTERVAL '6 months' 
      AND severity IN ('info', 'warning');
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- SÉCURITÉ RLS (ROW LEVEL SECURITY)
-- ================================================================

-- Activer RLS sur les tables sensibles
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_mentions ENABLE ROW LEVEL SECURITY;

-- Politique : Les utilisateurs ne voient que leurs propres sessions
CREATE POLICY user_sessions_policy ON user_sessions
    FOR ALL TO PUBLIC
    USING (user_id = current_user_id());

-- Fonction helper pour obtenir l'ID utilisateur actuel (à implémenter côté app)
CREATE OR REPLACE FUNCTION current_user_id()
RETURNS BIGINT AS $$
BEGIN
    -- Cette fonction doit être implémentée côté application
    -- Elle retourne l'ID de l'utilisateur connecté basé sur le contexte JWT
    RETURN COALESCE(current_setting('app.current_user_id', true)::BIGINT, 0);
END;
$$ LANGUAGE plpgsql STABLE;

-- ================================================================
-- DONNÉES DE TEST (À SUPPRIMER EN PRODUCTION)
-- ================================================================

-- Utilisateur admin par défaut
INSERT INTO users (username, email, password_hash, role, is_verified) 
VALUES ('admin', 'admin@veza-chat.com', '$2b$12$example_hash_here', 'owner', TRUE);

-- Salon général public
INSERT INTO conversations (type, name, description, is_public, owner_id)
VALUES ('public_room', 'Général', 'Salon de discussion générale', TRUE, 1);

-- ================================================================
-- COMMENTAIRES ET DOCUMENTATION
-- ================================================================

COMMENT ON TABLE users IS 'Utilisateurs du système avec authentification sécurisée';
COMMENT ON TABLE conversations IS 'Conversations unifiées (DM, salons publics/privés, groupes)';
COMMENT ON TABLE messages IS 'Messages unifiés avec support threads et épinglage';
COMMENT ON TABLE message_reactions IS 'Réactions emoji sur les messages';
COMMENT ON TABLE message_mentions IS 'Mentions @utilisateur dans les messages';
COMMENT ON TABLE files IS 'Fichiers uploadés avec vérification de sécurité';
COMMENT ON TABLE security_events IS 'Journal des événements de sécurité';
COMMENT ON TABLE audit_logs IS 'Audit trail complet de toutes les actions';

-- Fin de migration 