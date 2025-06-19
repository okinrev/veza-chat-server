#!/bin/bash

# Script de migration pour les DM enrichis - Veza Chat Server
# Ajoute la table dm_conversations et migre les données existantes

set -e

echo "🚀 Migration DM Enrichis - Veza Chat Server"
echo "==========================================="

# Configuration
DB_HOST="10.5.191.47"
DB_USER="veza"
DB_NAME="veza_db"
export PGPASSWORD="N3W3Dm0Ura@#fn5J%4UQKu%vSXWCNbCvj8Ne0FIUs#KG1T&Ouy2lJt$T!#"

# Fonction d'aide pour les requêtes SQL
run_sql() {
    psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "$1" -t -A
}

# Vérifier la connexion
echo "🔗 Vérification de la connexion à la base de données..."
if ! run_sql "SELECT 1" > /dev/null 2>&1; then
    echo "❌ Impossible de se connecter à la base de données"
    exit 1
fi
echo "✅ Connexion à la base de données OK"

# Vérifier si la migration est nécessaire
echo "🔍 Vérification de l'état actuel..."
TABLE_EXISTS=$(run_sql "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'dm_conversations')")

if [ "$TABLE_EXISTS" = "t" ]; then
    echo "⚠️  La table dm_conversations existe déjà"
    read -p "Voulez-vous continuer quand même? (o/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
        echo "Migration annulée"
        exit 0
    fi
fi

# Statistiques avant migration
echo "📊 Statistiques avant migration:"
DM_MESSAGES_COUNT=$(run_sql "SELECT COUNT(*) FROM messages WHERE from_user IS NOT NULL AND to_user IS NOT NULL AND room IS NULL")
echo "  Messages DM existants: $DM_MESSAGES_COUNT"

# Sauvegarde préventive
echo "💾 Création d'une sauvegarde préventive..."
BACKUP_FILE="backup_before_dm_migration_$(date +%Y%m%d_%H%M%S).sql"
pg_dump -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" --no-password > "$BACKUP_FILE" 2>/dev/null || {
    echo "⚠️  Impossible de créer une sauvegarde complète, mais on continue..."
}

if [ -f "$BACKUP_FILE" ]; then
    echo "✅ Sauvegarde créée: $BACKUP_FILE"
else
    echo "⚠️  Pas de sauvegarde, mais on continue..."
fi

# Exécuter la migration
echo "🔄 Exécution de la migration DM enrichis..."
if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "migrations/1000_dm_enriched.sql" --no-password; then
    echo "✅ Migration exécutée avec succès"
else
    echo "❌ Erreur lors de la migration"
    exit 1
fi

# Vérifications post-migration
echo "🔍 Vérifications post-migration..."

# Vérifier la création de la table
TABLE_EXISTS_AFTER=$(run_sql "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'dm_conversations')")
if [ "$TABLE_EXISTS_AFTER" = "t" ]; then
    echo "✅ Table dm_conversations créée"
else
    echo "❌ Table dm_conversations non créée"
    exit 1
fi

# Compter les conversations créées
CONVERSATIONS_COUNT=$(run_sql "SELECT COUNT(*) FROM dm_conversations")
echo "✅ Conversations DM créées: $CONVERSATIONS_COUNT"

# Compter les messages migrés
MIGRATED_MESSAGES=$(run_sql "SELECT COUNT(*) FROM messages WHERE conversation_id IN (SELECT id FROM dm_conversations)")
echo "✅ Messages DM migrés: $MIGRATED_MESSAGES"

# Vérifier les index
INDEXES_COUNT=$(run_sql "SELECT COUNT(*) FROM pg_indexes WHERE tablename = 'dm_conversations'")
echo "✅ Index créés: $INDEXES_COUNT"

# Vérifier les triggers
TRIGGERS_COUNT=$(run_sql "SELECT COUNT(*) FROM pg_trigger WHERE tgrelid = 'dm_conversations'::regclass")
echo "✅ Triggers créés: $TRIGGERS_COUNT"

# Statistiques détaillées
echo ""
echo "📈 Statistiques détaillées:"

# Top 5 des conversations par nombre de messages
echo "🔝 Top 5 conversations par nombre de messages:"
run_sql "
SELECT 
    dc.id,
    u1.username || ' <-> ' || u2.username as conversation,
    COUNT(m.id) as message_count
FROM dm_conversations dc
JOIN users u1 ON u1.id = dc.user1_id
JOIN users u2 ON u2.id = dc.user2_id
LEFT JOIN messages m ON m.conversation_id = dc.id
GROUP BY dc.id, u1.username, u2.username
ORDER BY message_count DESC
LIMIT 5;
" | while IFS='|' read -r id conversation count; do
    echo "  📝 $conversation: $count messages"
done

# Vérifier l'intégrité des données
echo ""
echo "🔒 Vérification de l'intégrité des données..."

# Messages orphelins
ORPHAN_MESSAGES=$(run_sql "SELECT COUNT(*) FROM messages WHERE from_user IS NOT NULL AND to_user IS NOT NULL AND room IS NULL AND conversation_id IS NULL")
if [ "$ORPHAN_MESSAGES" -gt 0 ]; then
    echo "⚠️  Messages DM orphelins trouvés: $ORPHAN_MESSAGES"
else
    echo "✅ Aucun message DM orphelin"
fi

# Conversations sans messages
EMPTY_CONVERSATIONS=$(run_sql "SELECT COUNT(*) FROM dm_conversations dc LEFT JOIN messages m ON m.conversation_id = dc.id WHERE m.id IS NULL")
if [ "$EMPTY_CONVERSATIONS" -gt 0 ]; then
    echo "ℹ️  Conversations vides: $EMPTY_CONVERSATIONS (normal si créées récemment)"
else
    echo "✅ Toutes les conversations ont des messages"
fi

# Test de performance
echo ""
echo "⚡ Test de performance..."
start_time=$(date +%s%N)

run_sql "
SELECT COUNT(*)
FROM dm_conversations dc
JOIN messages m ON m.conversation_id = dc.id
WHERE dc.created_at > NOW() - INTERVAL '30 days';
" > /dev/null

end_time=$(date +%s%N)
duration=$(( (end_time - start_time) / 1000000 ))
echo "✅ Requête complexe exécutée en ${duration}ms"

# Résumé final
echo ""
echo "🎉 Migration DM enrichis terminée avec succès!"
echo ""
echo "📊 Résumé:"
echo "  📝 Messages DM avant: $DM_MESSAGES_COUNT"
echo "  💬 Conversations créées: $CONVERSATIONS_COUNT"
echo "  📝 Messages migrés: $MIGRATED_MESSAGES"
echo "  🗂️  Index créés: $INDEXES_COUNT"
echo "  ⚙️  Triggers créés: $TRIGGERS_COUNT"
echo ""

if [ "$MIGRATED_MESSAGES" -eq "$DM_MESSAGES_COUNT" ]; then
    echo "✅ Tous les messages DM ont été migrés avec succès!"
else
    echo "⚠️  Différence dans le nombre de messages migrés"
    echo "    Cela peut être normal si certains messages n'étaient pas des DM valides"
fi

echo ""
echo "🎯 Prochaines étapes:"
echo "  1. Tester les nouvelles fonctionnalités DM enrichies"
echo "  2. Utiliser le nouveau module dm_enhanced dans votre code"
echo "  3. Vérifier que l'application fonctionne correctement"
echo ""
echo "📚 Documentation: Voir GUIDE_SALONS_ENRICHIS.md (s'applique aussi aux DM)"

# Nettoyage optionnel
if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
    echo ""
    read -p "🧹 Voulez-vous conserver le fichier de sauvegarde $BACKUP_FILE? (O/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        rm "$BACKUP_FILE"
        echo "🗑️  Sauvegarde supprimée"
    else
        echo "💾 Sauvegarde conservée: $BACKUP_FILE"
    fi
fi 