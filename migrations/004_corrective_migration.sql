-- Migration 004: Correction et compatibilité avec le schéma existant
-- Cette migration corrige les erreurs de la migration précédente

BEGIN;

-- ================================================
-- CORRECTIONS DE LA TABLE ROOMS
-- ================================================

-- Ajouter les colonnes manquantes à la table rooms existante
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS creator_id INTEGER;
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS max_members INTEGER DEFAULT 1000;
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT false;

-- Ajouter les contraintes de clés étrangères
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'rooms_creator_id_fkey'
    ) THEN
        ALTER TABLE rooms ADD CONSTRAINT rooms_creator_id_fkey 
        FOREIGN KEY (creator_id) REFERENCES users(id) ON DELETE SET NULL;
    END IF;
END $$;

-- Créer l'index manquant
CREATE INDEX IF NOT EXISTS idx_rooms_creator ON rooms (creator_id);

-- ================================================
-- CORRECTIONS DE LA TABLE MESSAGES
-- ================================================

-- Renommer la colonne timestamp vers created_at pour cohérence
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'messages' AND column_name = 'timestamp') 
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns 
                      WHERE table_name = 'messages' AND column_name = 'created_at') THEN
        ALTER TABLE messages RENAME COLUMN timestamp TO created_at;
    END IF;
END $$;

-- Ajouter des colonnes manquantes pour les nouvelles fonctionnalités
ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_flagged BOOLEAN DEFAULT false;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS moderation_notes TEXT;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS thread_count INTEGER DEFAULT 0;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS original_content TEXT;

-- Ajouter une colonne status si elle n'existe pas
ALTER TABLE messages ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'sent';

-- Ajouter des index pour les nouvelles colonnes
CREATE INDEX IF NOT EXISTS idx_messages_pinned ON messages (is_pinned) WHERE is_pinned = true;
CREATE INDEX IF NOT EXISTS idx_messages_flagged ON messages (is_flagged) WHERE is_flagged = true;
CREATE INDEX IF NOT EXISTS idx_messages_status ON messages (status);
CREATE INDEX IF NOT EXISTS idx_messages_thread ON messages (thread_count) WHERE thread_count > 0;

-- ================================================
-- AMÉLIORER LA TABLE USERS EXISTANTE
-- ================================================

-- Ajouter des colonnes pour la sécurité et la modération
ALTER TABLE users ADD COLUMN IF NOT EXISTS reputation_score INTEGER DEFAULT 100;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_banned BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS ban_expires_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS ban_reason TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS warning_count INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS mute_expires_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE users ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'offline';
ALTER TABLE users ADD COLUMN IF NOT EXISTS status_message VARCHAR(100);

-- Ajouter des index pour les nouvelles colonnes users
CREATE INDEX IF NOT EXISTS idx_users_reputation ON users (reputation_score);
CREATE INDEX IF NOT EXISTS idx_users_banned ON users (is_banned) WHERE is_banned = true;
CREATE INDEX IF NOT EXISTS idx_users_status ON users (status);
CREATE INDEX IF NOT EXISTS idx_users_last_seen ON users (last_seen);

-- ================================================
-- CRÉER LES TABLES MANQUANTES
-- ================================================

-- Table des mentions (si elle n'existe pas)
CREATE TABLE IF NOT EXISTS message_mentions (
    id BIGSERIAL PRIMARY KEY,
    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_read BOOLEAN DEFAULT false,
    
    UNIQUE (message_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_mentions_user ON message_mentions (user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_mentions_message ON message_mentions (message_id);

-- Table des blocages utilisateurs (si elle n'existe pas)
CREATE TABLE IF NOT EXISTS user_blocks (
    id BIGSERIAL PRIMARY KEY,
    blocker_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    UNIQUE (blocker_id, blocked_id),
    CONSTRAINT no_self_block CHECK (blocker_id != blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_blocks_blocker ON user_blocks (blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocks_blocked ON user_blocks (blocked_id);

-- Table des logs de modération (si elle n'existe pas)
CREATE TABLE IF NOT EXISTS moderation_log (
    id BIGSERIAL PRIMARY KEY,
    
    moderator_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    target_type VARCHAR(20) NOT NULL CHECK (target_type IN ('user', 'message', 'room')),
    target_id TEXT NOT NULL,
    action VARCHAR(50) NOT NULL,
    
    reason TEXT,
    details JSONB DEFAULT '{}'::jsonb,
    duration INTERVAL,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address INET
);

CREATE INDEX IF NOT EXISTS idx_moderation_log_moderator ON moderation_log (moderator_id, created_at);
CREATE INDEX IF NOT EXISTS idx_moderation_log_target ON moderation_log (target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_moderation_log_action ON moderation_log (action, created_at);

-- ================================================
-- VUES CORRIGÉES AVEC LES BONS NOMS DE COLONNES
-- ================================================

-- Vue des statistiques serveur (corrigée)
DROP VIEW IF EXISTS server_stats;
CREATE OR REPLACE VIEW server_stats AS
SELECT 
    'total_users'::text as metric,
    COUNT(*)::bigint as value
FROM users 
WHERE id IS NOT NULL

UNION ALL

SELECT 
    'active_users'::text as metric,
    COUNT(*)::bigint as value
FROM users 
WHERE last_seen > NOW() - INTERVAL '1 hour'

UNION ALL

SELECT 
    'total_rooms'::text as metric,
    COUNT(*)::bigint as value
FROM rooms

UNION ALL

SELECT 
    'total_messages'::text as metric,
    COUNT(*)::bigint as value
FROM messages

UNION ALL

SELECT 
    'messages_today'::text as metric,
    COUNT(*)::bigint as value
FROM messages 
WHERE created_at >= CURRENT_DATE;

-- ================================================
-- FONCTIONS UTILITAIRES CORRIGÉES
-- ================================================

-- Fonction pour calculer la réputation (corrigée)
CREATE OR REPLACE FUNCTION calculate_user_reputation(user_id_param INTEGER) 
RETURNS INTEGER AS $$
DECLARE
    base_score INTEGER := 100;
    warnings INTEGER := 0;
    bans INTEGER := 0;
    recent_messages INTEGER := 0;
BEGIN
    -- Compter les avertissements
    SELECT COALESCE(warning_count, 0) INTO warnings 
    FROM users WHERE id = user_id_param;
    
    -- Compter les messages récents (bonus)
    SELECT COUNT(*) INTO recent_messages
    FROM messages 
    WHERE from_user = user_id_param 
      AND created_at > NOW() - INTERVAL '30 days';
    
    -- Calculer le score final
    RETURN GREATEST(0, base_score - (warnings * 5) + (recent_messages / 10));
END;
$$ LANGUAGE plpgsql;

-- Fonction de nettoyage des données anciennes (corrigée)
CREATE OR REPLACE FUNCTION cleanup_old_data()
RETURNS void AS $$
BEGIN
    -- Supprimer les sessions expirées anciennes
    DELETE FROM user_sessions 
    WHERE created_at < NOW() - INTERVAL '30 days';
    
    -- Marquer les anciens messages comme archivés (soft delete)
    UPDATE messages 
    SET status = 'archived'
    WHERE created_at < NOW() - INTERVAL '1 year' 
      AND status = 'sent';
    
    -- Nettoyer les logs de modération anciens
    DELETE FROM moderation_log 
    WHERE created_at < NOW() - INTERVAL '6 months';
    
    RAISE NOTICE 'Nettoyage des données anciennes terminé';
END;
$$ LANGUAGE plpgsql;

-- ================================================
-- TRIGGERS POUR MAINTENIR LA COHÉRENCE
-- ================================================

-- Trigger pour mettre à jour last_seen automatiquement
CREATE OR REPLACE FUNCTION update_user_last_seen()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE users SET last_seen = NOW() WHERE id = NEW.from_user;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_last_seen ON messages;
CREATE TRIGGER trigger_update_last_seen
    AFTER INSERT ON messages
    FOR EACH ROW EXECUTE FUNCTION update_user_last_seen();

-- Trigger pour compter les threads
CREATE OR REPLACE FUNCTION update_thread_count()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.reply_to_id IS NOT NULL THEN
        UPDATE messages 
        SET thread_count = thread_count + 1 
        WHERE id = NEW.reply_to_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_thread_count ON messages;
CREATE TRIGGER trigger_thread_count
    AFTER INSERT ON messages
    FOR EACH ROW EXECUTE FUNCTION update_thread_count();

-- ================================================
-- CONTRAINTES DE SÉCURITÉ SUPPLÉMENTAIRES
-- ================================================

-- Limiter la longueur des messages épinglés
ALTER TABLE messages ADD CONSTRAINT chk_pinned_content_reasonable 
CHECK (NOT is_pinned OR LENGTH(content) <= 500);

-- Limiter le nombre de réactions par utilisateur et message
ALTER TABLE message_reactions ADD CONSTRAINT chk_emoji_reasonable 
CHECK (LENGTH(emoji) <= 10);

-- Vérifier que les statuts utilisateur sont valides
ALTER TABLE users ADD CONSTRAINT chk_user_status_valid 
CHECK (status IN ('online', 'away', 'busy', 'invisible', 'offline'));

-- ================================================
-- DONNÉES DE TEST ET INITIALISATION
-- ================================================

-- Mettre à jour les données existantes pour la compatibilité
UPDATE messages SET status = 'sent' WHERE status IS NULL;
UPDATE users SET reputation_score = 100 WHERE reputation_score IS NULL;
UPDATE users SET status = 'offline' WHERE status IS NULL;

-- Créer un salon général s'il n'existe pas
INSERT INTO rooms (name, is_private, description, creator_id) 
SELECT 'général', false, 'Salon de discussion générale', 
       (SELECT id FROM users ORDER BY id LIMIT 1)
WHERE NOT EXISTS (SELECT 1 FROM rooms WHERE name = 'général');

-- ================================================
-- COMMENTAIRES POUR DOCUMENTATION
-- ================================================

COMMENT ON TABLE message_mentions IS 'Mentions d''utilisateurs dans les messages';
COMMENT ON TABLE user_blocks IS 'Blocages entre utilisateurs pour empêcher les DM';
COMMENT ON TABLE moderation_log IS 'Journal des actions de modération';
COMMENT ON VIEW server_stats IS 'Statistiques temps réel du serveur';

-- ================================================
-- PERMISSIONS ET SÉCURITÉ
-- ================================================

-- Accorder les permissions nécessaires à l'utilisateur veza
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO veza;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO veza;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO veza;

COMMIT;

-- ================================================
-- VÉRIFICATIONS POST-MIGRATION
-- ================================================

-- Vérifier que les colonnes essentielles existent
DO $$
BEGIN
    -- Vérifier messages.created_at
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'messages' AND column_name = 'created_at') THEN
        RAISE EXCEPTION 'Colonne messages.created_at manquante après migration';
    END IF;
    
    -- Vérifier rooms.creator_id
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'rooms' AND column_name = 'creator_id') THEN
        RAISE EXCEPTION 'Colonne rooms.creator_id manquante après migration';
    END IF;
    
    RAISE NOTICE 'Vérifications post-migration réussies';
END $$; 