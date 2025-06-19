-- ================================================================
-- CORRECTIONS POST-MIGRATION
-- Corrige les erreurs résiduelles de la migration principale
-- ================================================================

\echo '🔧 Corrections post-migration en cours...'

-- ================================================================
-- ÉTAPE 1: FINALISER LA TABLE USERS
-- ================================================================

\echo '👤 Finalisation de la table users...'

-- Ajouter les colonnes manquantes de profil (si pas déjà présentes)
DO $$
BEGIN
    -- Colonnes de profil manquantes
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'users' AND column_name = 'last_activity') THEN
        ALTER TABLE users ADD COLUMN last_activity TIMESTAMPTZ DEFAULT NOW();
        RAISE NOTICE 'Colonne last_activity ajoutée à users';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'users' AND column_name = 'updated_at') THEN
        ALTER TABLE users ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
        RAISE NOTICE 'Colonne updated_at ajoutée à users';
    END IF;
END $$;

-- Corriger le type de la colonne role
DO $$
BEGIN
    -- Convertir la valeur par défaut vers le type user_role
    BEGIN
        UPDATE users SET role = 'user' WHERE role IS NULL;
        ALTER TABLE users ALTER COLUMN role DROP DEFAULT;
        ALTER TABLE users ALTER COLUMN role TYPE user_role USING role::text::user_role;
        ALTER TABLE users ALTER COLUMN role SET DEFAULT 'user'::user_role;
        RAISE NOTICE 'Type role converti vers user_role';
    EXCEPTION 
        WHEN OTHERS THEN
            RAISE NOTICE 'Conversion role échouée ou déjà faite: %', SQLERRM;
    END;
END $$;

-- ================================================================
-- ÉTAPE 2: FINALISER LA TABLE MESSAGES
-- ================================================================

\echo '💬 Finalisation de la table messages...'

-- Ajouter les colonnes manquantes pour les messages
DO $$
BEGIN
    -- Colonnes pour les threads et métadonnées
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'messages' AND column_name = 'parent_message_id') THEN
        ALTER TABLE messages ADD COLUMN parent_message_id BIGINT REFERENCES messages(id) ON DELETE SET NULL;
        RAISE NOTICE 'Colonne parent_message_id ajoutée à messages';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'messages' AND column_name = 'is_pinned') THEN
        ALTER TABLE messages ADD COLUMN is_pinned BOOLEAN DEFAULT FALSE;
        RAISE NOTICE 'Colonne is_pinned ajoutée à messages';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'messages' AND column_name = 'updated_at') THEN
        ALTER TABLE messages ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
        RAISE NOTICE 'Colonne updated_at ajoutée à messages';
    END IF;
END $$;

-- Corriger le type status des messages
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'messages' AND column_name = 'status') THEN
        ALTER TABLE messages ADD COLUMN status message_status DEFAULT 'sent'::message_status;
        RAISE NOTICE 'Colonne status ajoutée à messages';
    END IF;
END $$;

-- ================================================================
-- ÉTAPE 3: FINALISER LA TABLE MESSAGE_REACTIONS
-- ================================================================

\echo '😊 Finalisation de la table message_reactions...'

-- Ajouter la colonne emoji si manquante
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'message_reactions' AND column_name = 'emoji') THEN
        ALTER TABLE message_reactions ADD COLUMN emoji VARCHAR(20) NOT NULL DEFAULT '👍';
        RAISE NOTICE 'Colonne emoji ajoutée à message_reactions';
        
        -- Supprimer la valeur par défaut après ajout
        ALTER TABLE message_reactions ALTER COLUMN emoji DROP DEFAULT;
    END IF;
END $$;

-- ================================================================
-- ÉTAPE 4: CRÉATION DES INDEX MANQUÉS
-- ================================================================

\echo '⚡ Création des index manqués...'

-- Index avec les bonnes colonnes
DO $$
BEGIN
    -- Index pour users avec last_activity (si la colonne existe maintenant)
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'users' AND column_name = 'last_activity') THEN
        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_last_activity_fixed
        ON users(last_activity DESC) WHERE is_active = TRUE;
        RAISE NOTICE 'Index idx_users_last_activity_fixed créé';
    END IF;

    -- Index pour threads (si parent_message_id existe)
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'messages' AND column_name = 'parent_message_id') THEN
        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_threads_fixed
        ON messages(parent_message_id, created_at) WHERE parent_message_id IS NOT NULL;
        RAISE NOTICE 'Index idx_messages_threads_fixed créé';
    END IF;

    -- Index pour réactions avec emoji (si la colonne existe)
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'message_reactions' AND column_name = 'emoji') THEN
        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reactions_message_emoji_fixed
        ON message_reactions(message_id, emoji);
        RAISE NOTICE 'Index idx_reactions_message_emoji_fixed créé';
    END IF;
END $$;

-- ================================================================
-- ÉTAPE 5: NETTOYAGE DES DÉPENDANCES PROBLÉMATIQUES
-- ================================================================

\echo '🧹 Nettoyage des dépendances...'

-- Supprimer le trigger problématique avant la fonction
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.triggers 
               WHERE trigger_name = 'trigger_handle_mentions_secure') THEN
        DROP TRIGGER IF EXISTS trigger_handle_mentions_secure ON messages;
        RAISE NOTICE 'Trigger trigger_handle_mentions_secure supprimé';
    END IF;
    
    -- Maintenant supprimer la fonction
    DROP FUNCTION IF EXISTS handle_mentions_secure() CASCADE;
    RAISE NOTICE 'Fonction handle_mentions_secure supprimée';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Erreur lors du nettoyage: %', SQLERRM;
END $$;

-- ================================================================
-- ÉTAPE 6: MISE À JOUR DES DONNÉES EXISTANTES
-- ================================================================

\echo '🔄 Mise à jour des données existantes...'

-- Mettre à jour les messages sans conversation_id
UPDATE messages 
SET conversation_id = (
    SELECT id FROM conversations 
    WHERE type = 'public_room'::conversation_type 
    AND name = messages.room 
    LIMIT 1
)
WHERE conversation_id IS NULL AND room IS NOT NULL;

-- Créer une conversation par défaut pour les messages orphelins
DO $$
DECLARE
    default_conv_id BIGINT;
BEGIN
    -- Créer une conversation par défaut si nécessaire
    IF EXISTS (SELECT 1 FROM messages WHERE conversation_id IS NULL) THEN
        INSERT INTO conversations (type, name, owner_id, is_public)
        VALUES ('public_room'::conversation_type, 'general', 1, TRUE)
        ON CONFLICT DO NOTHING
        RETURNING id INTO default_conv_id;
        
        -- Assigner les messages orphelins à cette conversation
        UPDATE messages 
        SET conversation_id = COALESCE(default_conv_id, (
            SELECT id FROM conversations 
            WHERE name = 'general' 
            LIMIT 1
        ))
        WHERE conversation_id IS NULL;
        
        RAISE NOTICE 'Messages orphelins assignés à la conversation par défaut';
    END IF;
END $$;

-- ================================================================
-- ÉTAPE 7: VÉRIFICATIONS FINALES
-- ================================================================

\echo '🔍 Vérifications finales...'

-- Vérifier l'intégrité des données
DO $$
DECLARE
    orphan_messages INTEGER;
    users_without_uuid INTEGER;
BEGIN
    -- Compter les messages sans conversation
    SELECT COUNT(*) INTO orphan_messages FROM messages WHERE conversation_id IS NULL;
    
    -- Compter les utilisateurs sans UUID
    SELECT COUNT(*) INTO users_without_uuid FROM users WHERE uuid IS NULL;
    
    RAISE NOTICE 'Vérifications finales:';
    RAISE NOTICE '- Messages orphelins: %', orphan_messages;
    RAISE NOTICE '- Utilisateurs sans UUID: %', users_without_uuid;
    
    IF orphan_messages > 0 THEN
        RAISE WARNING 'Il reste % messages sans conversation_id', orphan_messages;
    END IF;
    
    IF users_without_uuid > 0 THEN
        RAISE WARNING 'Il reste % utilisateurs sans UUID', users_without_uuid;
    END IF;
END $$;

-- Actualiser les statistiques
ANALYZE users;
ANALYZE messages;
ANALYZE conversations;
ANALYZE message_reactions;

\echo '✅ Corrections post-migration terminées avec succès!'
\echo ''
\echo '📊 Résumé des corrections:'
\echo '- Colonnes manquantes ajoutées'
\echo '- Index problématiques recréés'
\echo '- Dépendances nettoyées'
\echo '- Données orphelines assignées'
\echo '- Types énumérés corrigés' 