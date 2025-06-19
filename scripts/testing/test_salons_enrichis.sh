#!/bin/bash

# Script de test des salons enrichis - Veza Chat Server
# Teste toutes les nouvelles fonctionnalités des salons

set -e

echo "🧪 Tests des Salons Enrichis - Veza Chat Server"
echo "=============================================="

# Configuration
DB_HOST="10.5.191.47"
DB_USER="veza"
DB_NAME="veza_db"
export PGPASSWORD="N3W3Dm0Ura@#fn5J%4UQKu%vSXWCNbCvj8Ne0FIUs#KG1T&Ouy2lJt$T!#"

# Fonction d'aide pour les requêtes SQL
run_sql() {
    psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "$1" -t -A
}

# Fonction pour créer des données de test
create_test_data() {
    echo "📊 Création des données de test..."
    
    # Créer des utilisateurs de test
    run_sql "
    INSERT INTO users (username, email, password_hash, role) 
    VALUES 
        ('alice_test', 'alice@test.com', 'hash1', 'member'),
        ('bob_test', 'bob@test.com', 'hash2', 'member'),
        ('carol_test', 'carol@test.com', 'hash3', 'moderator')
    ON CONFLICT (username) DO NOTHING;
    "
    
    # Récupérer les IDs
    ALICE_ID=$(run_sql "SELECT id FROM users WHERE username = 'alice_test'")
    BOB_ID=$(run_sql "SELECT id FROM users WHERE username = 'bob_test'")
    CAROL_ID=$(run_sql "SELECT id FROM users WHERE username = 'carol_test'")
    
    echo "✅ Utilisateurs de test créés: Alice($ALICE_ID), Bob($BOB_ID), Carol($CAROL_ID)"
    
    # Créer un salon de test
    ROOM_UUID=$(uuidgen)
    run_sql "
    INSERT INTO conversations (uuid, type, name, description, owner_id, is_public, max_members)
    VALUES ('$ROOM_UUID', 'public_room', 'Salon Test Enrichi', 'Salon pour tester les fonctionnalités', $ALICE_ID, true, 10);
    "
    
    ROOM_ID=$(run_sql "SELECT id FROM conversations WHERE uuid = '$ROOM_UUID'")
    echo "✅ Salon de test créé: ID $ROOM_ID"
    
    # Ajouter les membres
    run_sql "
    INSERT INTO conversation_members (conversation_id, user_id, role)
    VALUES 
        ($ROOM_ID, $ALICE_ID, 'owner'),
        ($ROOM_ID, $BOB_ID, 'member'),
        ($ROOM_ID, $CAROL_ID, 'moderator');
    "
    echo "✅ Membres ajoutés au salon"
    
    # Exporter les variables pour les autres fonctions
    export ALICE_ID BOB_ID CAROL_ID ROOM_ID
}

# Test 1: Messages avec métadonnées
test_messages_enrichis() {
    echo "📝 Test 1: Messages enrichis..."
    
    # Créer des messages avec différents types
    MSG_UUID1=$(uuidgen)
    MSG_UUID2=$(uuidgen)
    MSG_UUID3=$(uuidgen)
    
    run_sql "
    INSERT INTO messages (uuid, author_id, conversation_id, content, metadata, status)
    VALUES 
        ('$MSG_UUID1', $ALICE_ID, $ROOM_ID, 'Message principal', '{\"type\": \"announcement\"}', 'sent'),
        ('$MSG_UUID2', $BOB_ID, $ROOM_ID, 'Réponse au message', '{\"type\": \"reply\"}', 'sent'),
        ('$MSG_UUID3', $CAROL_ID, $ROOM_ID, 'Message important', '{\"priority\": \"high\"}', 'sent');
    "
    
    # Créer un thread (réponse)
    MSG1_ID=$(run_sql "SELECT id FROM messages WHERE uuid = '$MSG_UUID1'")
    MSG_THREAD_UUID=$(uuidgen)
    
    run_sql "
    INSERT INTO messages (uuid, author_id, conversation_id, content, parent_message_id, metadata, status)
    VALUES ('$MSG_THREAD_UUID', $BOB_ID, $ROOM_ID, 'Réponse dans le thread', $MSG1_ID, '{\"is_thread\": true}', 'sent');
    "
    
    # Mettre à jour le compteur de thread
    run_sql "UPDATE messages SET thread_count = thread_count + 1 WHERE id = $MSG1_ID"
    
    # Vérifier les messages
    MESSAGE_COUNT=$(run_sql "SELECT COUNT(*) FROM messages WHERE conversation_id = $ROOM_ID")
    THREAD_COUNT=$(run_sql "SELECT thread_count FROM messages WHERE id = $MSG1_ID")
    
    echo "✅ Messages créés: $MESSAGE_COUNT total, $THREAD_COUNT réponses dans le thread"
    
    export MSG1_ID MSG_UUID2 MSG_UUID3
}

# Test 2: Système de réactions
test_reactions() {
    echo "😊 Test 2: Système de réactions..."
    
    MSG2_ID=$(run_sql "SELECT id FROM messages WHERE uuid = '$MSG_UUID2'")
    MSG3_ID=$(run_sql "SELECT id FROM messages WHERE uuid = '$MSG_UUID3'")
    
    # Ajouter différentes réactions
    run_sql "
    INSERT INTO message_reactions (message_id, user_id, emoji)
    VALUES 
        ($MSG2_ID, $ALICE_ID, '👍'),
        ($MSG2_ID, $BOB_ID, '👍'),
        ($MSG2_ID, $CAROL_ID, '❤️'),
        ($MSG3_ID, $ALICE_ID, '🔥'),
        ($MSG3_ID, $BOB_ID, '🔥'),
        ($MSG3_ID, $CAROL_ID, '💯');
    "
    
    # Vérifier les réactions
    REACTION_COUNT=$(run_sql "SELECT COUNT(*) FROM message_reactions")
    THUMBS_UP_COUNT=$(run_sql "SELECT COUNT(*) FROM message_reactions WHERE emoji = '👍'")
    
    echo "✅ Réactions créées: $REACTION_COUNT total, $THUMBS_UP_COUNT 👍"
    
    # Test des agrégations
    echo "📊 Réactions par message:"
    run_sql "
    SELECT 
        m.content, 
        mr.emoji, 
        COUNT(*) as count
    FROM messages m
    JOIN message_reactions mr ON mr.message_id = m.id
    WHERE m.conversation_id = $ROOM_ID
    GROUP BY m.id, m.content, mr.emoji
    ORDER BY m.id, mr.emoji;
    " | while IFS='|' read -r content emoji count; do
        echo "  📝 \"$content\" - $emoji x$count"
    done
}

# Test 3: Messages épinglés
test_pinned_messages() {
    echo "📌 Test 3: Messages épinglés..."
    
    MSG1_ID=$(run_sql "SELECT id FROM messages WHERE uuid = '$MSG_UUID2'")
    MSG2_ID=$(run_sql "SELECT id FROM messages WHERE uuid = '$MSG_UUID3'")
    
    # Épingler quelques messages
    run_sql "
    UPDATE messages 
    SET is_pinned = true, updated_at = NOW() 
    WHERE id IN ($MSG1_ID, $MSG2_ID);
    "
    
    # Vérifier les messages épinglés
    PINNED_COUNT=$(run_sql "SELECT COUNT(*) FROM messages WHERE conversation_id = $ROOM_ID AND is_pinned = true")
    
    echo "✅ Messages épinglés: $PINNED_COUNT"
    
    # Lister les messages épinglés
    echo "📋 Messages épinglés:"
    run_sql "
    SELECT content 
    FROM messages 
    WHERE conversation_id = $ROOM_ID AND is_pinned = true
    ORDER BY created_at;
    " | while read -r content; do
        echo "  📌 $content"
    done
}

# Test 4: Système de mentions
test_mentions() {
    echo "🔔 Test 4: Système de mentions..."
    
    # Créer un message avec mentions
    MSG_MENTION_UUID=$(uuidgen)
    run_sql "
    INSERT INTO messages (uuid, author_id, conversation_id, content, metadata, status)
    VALUES ('$MSG_MENTION_UUID', $ALICE_ID, $ROOM_ID, 'Salut @bob_test et @carol_test!', '{\"has_mentions\": true}', 'sent');
    "
    
    MSG_MENTION_ID=$(run_sql "SELECT id FROM messages WHERE uuid = '$MSG_MENTION_UUID'")
    
    # Ajouter les mentions
    run_sql "
    INSERT INTO message_mentions (message_id, mentioned_user_id)
    VALUES 
        ($MSG_MENTION_ID, $BOB_ID),
        ($MSG_MENTION_ID, $CAROL_ID);
    "
    
    # Vérifier les mentions
    MENTION_COUNT=$(run_sql "SELECT COUNT(*) FROM message_mentions WHERE message_id = $MSG_MENTION_ID")
    
    echo "✅ Mentions créées: $MENTION_COUNT"
    
    # Lister les mentions
    echo "📋 Utilisateurs mentionnés:"
    run_sql "
    SELECT u.username 
    FROM message_mentions mm
    JOIN users u ON u.id = mm.mentioned_user_id
    WHERE mm.message_id = $MSG_MENTION_ID;
    " | while read -r username; do
        echo "  @$username"
    done
}

# Test 5: Logs d'audit
test_audit_logs() {
    echo "📊 Test 5: Logs d'audit..."
    
    # Créer des logs d'audit de test
    run_sql "
    INSERT INTO audit_logs (action, details, user_id)
    VALUES 
        ('room_created', '{\"room_id\": $ROOM_ID, \"room_name\": \"Salon Test Enrichi\"}', $ALICE_ID),
        ('member_joined', '{\"room_id\": $ROOM_ID, \"target_user_id\": $BOB_ID}', $BOB_ID),
        ('member_joined', '{\"room_id\": $ROOM_ID, \"target_user_id\": $CAROL_ID}', $CAROL_ID),
        ('message_sent', '{\"room_id\": $ROOM_ID, \"message_id\": $MSG1_ID}', $ALICE_ID),
        ('message_pinned', '{\"room_id\": $ROOM_ID, \"message_id\": $MSG1_ID}', $CAROL_ID);
    "
    
    # Vérifier les logs
    AUDIT_COUNT=$(run_sql "SELECT COUNT(*) FROM audit_logs WHERE (details->>'room_id')::bigint = $ROOM_ID")
    
    echo "✅ Logs d'audit créés: $AUDIT_COUNT"
    
    # Afficher les logs récents
    echo "📋 Logs d'audit récents:"
    run_sql "
    SELECT action, created_at::timestamp(0), (details->>'room_id') as room_id
    FROM audit_logs 
    WHERE (details->>'room_id')::bigint = $ROOM_ID
    ORDER BY created_at DESC
    LIMIT 5;
    " | while IFS='|' read -r action timestamp room_id; do
        echo "  📝 $timestamp - $action (salon: $room_id)"
    done
}

# Test 6: Événements de sécurité
test_security_events() {
    echo "🚨 Test 6: Événements de sécurité..."
    
    # Créer des événements de sécurité
    run_sql "
    INSERT INTO security_events (event_type, severity, description, user_id, metadata)
    VALUES 
        ('suspicious_activity', 'medium', 'Activité suspecte détectée', $BOB_ID, '{\"room_id\": $ROOM_ID, \"action_count\": 25}'),
        ('rate_limit_exceeded', 'low', 'Limite de taux dépassée', $CAROL_ID, '{\"room_id\": $ROOM_ID, \"endpoint\": \"send_message\"}'),
        ('moderation_action', 'high', 'Action de modération', $ALICE_ID, '{\"room_id\": $ROOM_ID, \"action\": \"warn\", \"target_user\": $BOB_ID}');
    "
    
    # Vérifier les événements
    SECURITY_COUNT=$(run_sql "SELECT COUNT(*) FROM security_events WHERE (metadata->>'room_id')::bigint = $ROOM_ID")
    
    echo "✅ Événements de sécurité créés: $SECURITY_COUNT"
    
    # Afficher les événements par sévérité
    echo "📋 Événements de sécurité:"
    run_sql "
    SELECT severity, COUNT(*) as count
    FROM security_events 
    WHERE (metadata->>'room_id')::bigint = $ROOM_ID
    GROUP BY severity
    ORDER BY 
        CASE severity 
            WHEN 'high' THEN 1 
            WHEN 'medium' THEN 2 
            WHEN 'low' THEN 3 
        END;
    " | while IFS='|' read -r severity count; do
        echo "  🚨 $severity: $count événements"
    done
}

# Test 7: Statistiques du salon
test_room_statistics() {
    echo "📈 Test 7: Statistiques du salon..."
    
    # Calculer les statistiques
    echo "📊 Statistiques du salon:"
    
    # Messages
    TOTAL_MESSAGES=$(run_sql "SELECT COUNT(*) FROM messages WHERE conversation_id = $ROOM_ID")
    PINNED_MESSAGES=$(run_sql "SELECT COUNT(*) FROM messages WHERE conversation_id = $ROOM_ID AND is_pinned = true")
    THREAD_MESSAGES=$(run_sql "SELECT COUNT(*) FROM messages WHERE conversation_id = $ROOM_ID AND parent_message_id IS NOT NULL")
    
    echo "  📝 Messages totaux: $TOTAL_MESSAGES"
    echo "  📌 Messages épinglés: $PINNED_MESSAGES"
    echo "  🧵 Messages en thread: $THREAD_MESSAGES"
    
    # Membres
    TOTAL_MEMBERS=$(run_sql "SELECT COUNT(*) FROM conversation_members WHERE conversation_id = $ROOM_ID AND left_at IS NULL")
    
    echo "  👥 Membres actifs: $TOTAL_MEMBERS"
    
    # Réactions
    TOTAL_REACTIONS=$(run_sql "SELECT COUNT(*) FROM message_reactions mr JOIN messages m ON m.id = mr.message_id WHERE m.conversation_id = $ROOM_ID")
    
    echo "  😊 Réactions totales: $TOTAL_REACTIONS"
    
    # Activité récente
    RECENT_ACTIVITY=$(run_sql "SELECT COUNT(*) FROM audit_logs WHERE (details->>'room_id')::bigint = $ROOM_ID AND created_at > NOW() - INTERVAL '1 hour'")
    
    echo "  🔥 Activité récente (1h): $RECENT_ACTIVITY actions"
}

# Test 8: Performances et requêtes complexes
test_complex_queries() {
    echo "⚡ Test 8: Requêtes complexes..."
    
    # Requête complexe: messages avec réactions et mentions
    echo "🔍 Messages avec réactions et mentions:"
    run_sql "
    SELECT 
        m.content,
        COUNT(DISTINCT mr.id) as reaction_count,
        COUNT(DISTINCT mm.id) as mention_count,
        m.thread_count,
        m.is_pinned
    FROM messages m
    LEFT JOIN message_reactions mr ON mr.message_id = m.id
    LEFT JOIN message_mentions mm ON mm.message_id = m.id
    WHERE m.conversation_id = $ROOM_ID
    GROUP BY m.id, m.content, m.thread_count, m.is_pinned
    ORDER BY m.created_at;
    " | while IFS='|' read -r content reactions mentions threads pinned; do
        echo "  📝 \"$content\" - 😊x$reactions 🔔x$mentions 🧵x$threads 📌$pinned"
    done
    
    # Test de performance
    echo "⏱️  Test de performance - requête complexe..."
    start_time=$(date +%s%N)
    
    run_sql "
    SELECT 
        c.name,
        COUNT(DISTINCT m.id) as messages,
        COUNT(DISTINCT cm.user_id) as members,
        COUNT(DISTINCT mr.id) as reactions,
        MAX(m.created_at) as last_activity
    FROM conversations c
    LEFT JOIN messages m ON m.conversation_id = c.id
    LEFT JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.left_at IS NULL
    LEFT JOIN message_reactions mr ON mr.message_id = m.id
    WHERE c.id = $ROOM_ID
    GROUP BY c.id, c.name;
    " > /dev/null
    
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))
    
    echo "✅ Requête complexe exécutée en ${duration}ms"
}

# Nettoyage des données de test
cleanup_test_data() {
    echo "🧹 Nettoyage des données de test..."
    
    # Supprimer dans l'ordre inverse des dépendances
    run_sql "DELETE FROM message_reactions WHERE message_id IN (SELECT id FROM messages WHERE conversation_id = $ROOM_ID)"
    run_sql "DELETE FROM message_mentions WHERE message_id IN (SELECT id FROM messages WHERE conversation_id = $ROOM_ID)"
    run_sql "DELETE FROM messages WHERE conversation_id = $ROOM_ID"
    run_sql "DELETE FROM conversation_members WHERE conversation_id = $ROOM_ID"
    run_sql "DELETE FROM conversations WHERE id = $ROOM_ID"
    run_sql "DELETE FROM audit_logs WHERE (details->>'room_id')::bigint = $ROOM_ID"
    run_sql "DELETE FROM security_events WHERE (metadata->>'room_id')::bigint = $ROOM_ID"
    run_sql "DELETE FROM users WHERE username IN ('alice_test', 'bob_test', 'carol_test')"
    
    echo "✅ Données de test supprimées"
}

# Fonction principale
main() {
    echo "🚀 Démarrage des tests..."
    
    # Vérifier la connexion à la base
    if ! run_sql "SELECT 1" > /dev/null 2>&1; then
        echo "❌ Impossible de se connecter à la base de données"
        exit 1
    fi
    echo "✅ Connexion à la base de données OK"
    
    # Exécuter les tests
    create_test_data
    test_messages_enrichis
    test_reactions
    test_pinned_messages
    test_mentions
    test_audit_logs
    test_security_events
    test_room_statistics
    test_complex_queries
    
    echo ""
    echo "🎉 Tous les tests sont passés avec succès!"
    echo ""
    echo "📊 Résumé des fonctionnalités testées:"
    echo "  ✅ Messages enrichis avec métadonnées et threads"
    echo "  ✅ Système de réactions emoji"
    echo "  ✅ Messages épinglés"
    echo "  ✅ Système de mentions @username"
    echo "  ✅ Logs d'audit complets"
    echo "  ✅ Événements de sécurité"
    echo "  ✅ Statistiques avancées"
    echo "  ✅ Requêtes complexes performantes"
    echo ""
    
    # Demander si on doit nettoyer
    read -p "🧹 Voulez-vous nettoyer les données de test? (o/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[OoYy]$ ]]; then
        cleanup_test_data
    else
        echo "📝 Données de test conservées pour inspection manuelle"
        echo "   Salon ID: $ROOM_ID"
        echo "   Utilisateurs: Alice($ALICE_ID), Bob($BOB_ID), Carol($CAROL_ID)"
    fi
}

# Gestion des erreurs
trap 'echo "❌ Erreur détectée, nettoyage..."; cleanup_test_data 2>/dev/null || true; exit 1' ERR

# Exécution
main "$@" 