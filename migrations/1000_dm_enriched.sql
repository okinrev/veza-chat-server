-- Migration pour les DM enrichis - Veza Chat Server
-- Ajoute la table dm_conversations pour séparer les DM des salons

BEGIN;

-- Table pour les conversations DM enrichies
CREATE TABLE IF NOT EXISTS dm_conversations (
    id BIGSERIAL PRIMARY KEY,
    uuid UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
    user1_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user2_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_blocked BOOLEAN NOT NULL DEFAULT FALSE,
    blocked_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    
    -- Contraintes
    CONSTRAINT dm_conversations_different_users CHECK (user1_id != user2_id),
    CONSTRAINT dm_conversations_ordered_users CHECK (user1_id < user2_id),
    CONSTRAINT dm_conversations_unique_pair UNIQUE (user1_id, user2_id)
);

-- Index pour les performances
CREATE INDEX IF NOT EXISTS idx_dm_conversations_user1 ON dm_conversations(user1_id);
CREATE INDEX IF NOT EXISTS idx_dm_conversations_user2 ON dm_conversations(user2_id);
CREATE INDEX IF NOT EXISTS idx_dm_conversations_updated_at ON dm_conversations(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_dm_conversations_uuid ON dm_conversations(uuid);

-- Trigger pour mettre à jour updated_at automatiquement
CREATE OR REPLACE FUNCTION update_dm_conversations_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_dm_conversations_updated_at
    BEFORE UPDATE ON dm_conversations
    FOR EACH ROW
    EXECUTE FUNCTION update_dm_conversations_updated_at();

-- Migrer les messages DM existants vers le nouveau système
-- Créer des conversations DM pour tous les messages DM existants
INSERT INTO dm_conversations (user1_id, user2_id, created_at, updated_at)
SELECT DISTINCT 
    LEAST(from_user, to_user) as user1_id,
    GREATEST(from_user, to_user) as user2_id,
    MIN(timestamp) as created_at,
    MAX(timestamp) as updated_at
FROM messages 
WHERE from_user IS NOT NULL 
  AND to_user IS NOT NULL 
  AND room IS NULL
GROUP BY LEAST(from_user, to_user), GREATEST(from_user, to_user)
ON CONFLICT (user1_id, user2_id) DO NOTHING;

-- Mettre à jour les messages DM existants avec les conversation_id
UPDATE messages 
SET conversation_id = dc.id
FROM dm_conversations dc
WHERE messages.from_user IS NOT NULL 
  AND messages.to_user IS NOT NULL 
  AND messages.room IS NULL
  AND dc.user1_id = LEAST(messages.from_user, messages.to_user)
  AND dc.user2_id = GREATEST(messages.from_user, messages.to_user)
  AND messages.conversation_id IS NULL;

-- Log de la migration
INSERT INTO audit_logs (action, details) 
VALUES ('dm_enriched_migration', json_build_object(
    'migrated_conversations', (SELECT COUNT(*) FROM dm_conversations),
    'migrated_messages', (SELECT COUNT(*) FROM messages WHERE conversation_id IN (SELECT id FROM dm_conversations)),
    'timestamp', NOW()
));

COMMIT;

-- Vérifications post-migration
DO $$
DECLARE
    dm_conversations_count INTEGER;
    migrated_messages_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO dm_conversations_count FROM dm_conversations;
    SELECT COUNT(*) INTO migrated_messages_count FROM messages WHERE conversation_id IN (SELECT id FROM dm_conversations);
    
    RAISE NOTICE 'Migration DM enrichis terminée:';
    RAISE NOTICE '  - % conversations DM créées', dm_conversations_count;
    RAISE NOTICE '  - % messages DM migrés', migrated_messages_count;
    
    IF dm_conversations_count = 0 THEN
        RAISE NOTICE '  ⚠️  Aucune conversation DM trouvée (normal si pas de DM existants)';
    ELSE
        RAISE NOTICE '  ✅ Migration réussie';
    END IF;
END $$; 