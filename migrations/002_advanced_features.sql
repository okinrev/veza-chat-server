-- Migration pour les fonctionnalités avancées du serveur de chat
-- Exécuter après les migrations de base

-- Table des sanctions/modération
CREATE TABLE IF NOT EXISTS sanctions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    moderator_id INTEGER NOT NULL REFERENCES users(id), -- 0 pour système automatique
    sanction_type VARCHAR(50) NOT NULL, -- JSON serialized SanctionType
    reason VARCHAR(100) NOT NULL, -- JSON serialized SanctionReason  
    message TEXT, -- Message optionnel du modérateur
    expires_at TIMESTAMP WITH TIME ZONE, -- Expiration pour sanctions temporaires
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Index pour les sanctions
CREATE INDEX idx_sanctions_user_id ON sanctions(user_id);
CREATE INDEX idx_sanctions_active ON sanctions(user_id, is_active) WHERE is_active = true;

-- Table des réactions aux messages
CREATE TABLE IF NOT EXISTS message_reactions (
    id SERIAL PRIMARY KEY,
    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reaction_type VARCHAR(100) NOT NULL, -- JSON serialized ReactionType
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Un utilisateur ne peut avoir qu'une réaction de chaque type par message
    UNIQUE(message_id, user_id, reaction_type)
);

-- Index pour les réactions
CREATE INDEX idx_message_reactions_message ON message_reactions(message_id);

-- Table des blocages entre utilisateurs
CREATE TABLE IF NOT EXISTS user_blocks (
    id SERIAL PRIMARY KEY,
    blocker_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Un utilisateur ne peut bloquer un autre qu'une seule fois
    UNIQUE(blocker_id, blocked_id),
    
    -- Un utilisateur ne peut pas se bloquer lui-même
    CHECK (blocker_id != blocked_id)
);

-- Index pour les blocages
CREATE INDEX idx_user_blocks_blocker ON user_blocks(blocker_id);
CREATE INDEX idx_user_blocks_blocked ON user_blocks(blocked_id);

-- Table des salons avec métadonnées
CREATE TABLE IF NOT EXISTS rooms (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    display_name VARCHAR(100),
    description TEXT,
    creator_id INTEGER NOT NULL REFERENCES users(id),
    is_private BOOLEAN NOT NULL DEFAULT false,
    max_members INTEGER DEFAULT 100,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Index pour les salons
CREATE INDEX idx_rooms_name ON rooms(name);
CREATE INDEX idx_rooms_creator ON rooms(creator_id);
CREATE INDEX idx_rooms_private ON rooms(is_private);

-- Table des membres de salons avec rôles
CREATE TABLE IF NOT EXISTS room_members (
    id SERIAL PRIMARY KEY,
    room_id INTEGER NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL DEFAULT 'member', -- 'admin', 'moderator', 'member'
    joined_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_read_at TIMESTAMP WITH TIME ZONE,
    
    UNIQUE(room_id, user_id)
);

-- Index pour les membres de salon
CREATE INDEX idx_room_members_room ON room_members(room_id);
CREATE INDEX idx_room_members_user ON room_members(user_id);
CREATE INDEX idx_room_members_role ON room_members(room_id, role);

-- Table des notifications
CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL, -- 'dm', 'mention', 'room_invite', etc.
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    metadata JSONB, -- Données additionnelles spécifiques au type
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    read_at TIMESTAMP WITH TIME ZONE
);

-- Index pour les notifications
CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_unread ON notifications(user_id, is_read) WHERE is_read = false;
CREATE INDEX idx_notifications_type ON notifications(type);

-- Table des sessions utilisateur (pour la gestion des connexions multiples)
CREATE TABLE IF NOT EXISTS user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_token VARCHAR(255) NOT NULL UNIQUE,
    device_info VARCHAR(255), -- User-Agent ou info appareil
    ip_address INET,
    last_activity TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT true
);

-- Index pour les sessions
CREATE INDEX idx_user_sessions_user ON user_sessions(user_id);
CREATE INDEX idx_user_sessions_token ON user_sessions(session_token);
CREATE INDEX idx_user_sessions_active ON user_sessions(user_id, is_active) WHERE is_active = true;
CREATE INDEX idx_user_sessions_expires ON user_sessions(expires_at);

-- Table des logs d'audit pour le monitoring
CREATE TABLE IF NOT EXISTS audit_logs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id), -- NULL pour les actions système
    action VARCHAR(100) NOT NULL, -- 'login', 'message_sent', 'user_banned', etc.
    resource_type VARCHAR(50), -- 'user', 'message', 'room', etc.
    resource_id VARCHAR(100), -- ID de la ressource concernée
    details JSONB, -- Détails spécifiques à l'action
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Index pour les logs d'audit
CREATE INDEX idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_resource ON audit_logs(resource_type, resource_id);
CREATE INDEX idx_audit_logs_created ON audit_logs(created_at);

-- Mise à jour de la table messages pour supporter plus de métadonnées
ALTER TABLE messages 
ADD COLUMN IF NOT EXISTS message_type VARCHAR(20) DEFAULT 'text',
ADD COLUMN IF NOT EXISTS reply_to_id INTEGER REFERENCES messages(id),
ADD COLUMN IF NOT EXISTS is_edited BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS edited_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS metadata JSONB;

-- Index pour les nouvelles colonnes de messages
CREATE INDEX IF NOT EXISTS idx_messages_type ON messages(message_type);
CREATE INDEX IF NOT EXISTS idx_messages_reply ON messages(reply_to_id);
CREATE INDEX IF NOT EXISTS idx_messages_edited ON messages(is_edited) WHERE is_edited = true;

-- Mise à jour de la table users pour supporter les rôles et statuts
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS role VARCHAR(20) DEFAULT 'user',
ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'offline',
ADD COLUMN IF NOT EXISTS last_seen TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN IF NOT EXISTS reputation_score INTEGER DEFAULT 100,
ADD COLUMN IF NOT EXISTS is_banned BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS is_muted BOOLEAN DEFAULT false;

-- Index pour les nouvelles colonnes utilisateurs
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);

-- Vue pour les statistiques en temps réel
CREATE OR REPLACE VIEW server_stats AS
SELECT 
    (SELECT COUNT(*) FROM users WHERE last_seen > CURRENT_TIMESTAMP - INTERVAL '5 minutes') as active_users,
    (SELECT COUNT(*) FROM users) as total_users,
    (SELECT COUNT(*) FROM messages WHERE created_at > CURRENT_DATE) as messages_today,
    (SELECT COUNT(*) FROM messages) as total_messages;

-- Fonction pour nettoyer les sessions expirées
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM user_sessions WHERE expires_at < CURRENT_TIMESTAMP;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Fonction pour nettoyer les anciens logs d'audit (garder 30 jours)
CREATE OR REPLACE FUNCTION cleanup_old_audit_logs()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM audit_logs WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '30 days';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Contraintes de sécurité
ALTER TABLE messages ADD CONSTRAINT chk_message_content_length CHECK (length(content) <= 4000);
ALTER TABLE rooms ADD CONSTRAINT chk_room_name_length CHECK (length(name) <= 50 AND length(name) >= 1);
ALTER TABLE rooms ADD CONSTRAINT chk_room_max_members CHECK (max_members > 0 AND max_members <= 1000);

-- Commentaires pour la documentation
COMMENT ON TABLE sanctions IS 'Table des sanctions de modération (warnings, mutes, bans)';
COMMENT ON TABLE message_reactions IS 'Table des réactions aux messages (like, love, etc.)';
COMMENT ON TABLE user_blocks IS 'Table des blocages entre utilisateurs';
COMMENT ON TABLE rooms IS 'Table des salons de chat avec métadonnées';
COMMENT ON TABLE room_members IS 'Table des membres de salon avec leurs rôles';
COMMENT ON TABLE notifications IS 'Table des notifications push/in-app';
COMMENT ON TABLE user_sessions IS 'Table des sessions utilisateur actives';
COMMENT ON TABLE audit_logs IS 'Table des logs d\'audit pour le monitoring';

COMMENT ON VIEW server_stats IS 'Vue des statistiques serveur en temps réel';

-- Permissions par défaut (ajuster selon vos besoins)
-- GRANT SELECT ON server_stats TO chat_readonly_user;
-- GRANT SELECT, INSERT ON audit_logs TO chat_api_user; 