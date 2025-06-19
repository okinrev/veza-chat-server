#!/bin/bash

# ================================================================
# SCRIPT DE VÉRIFICATION POST-MIGRATION
# ================================================================

set -e

# Configuration
DB_HOST="10.5.191.47"
DB_USER="veza"
DB_NAME="veza_db"
DB_PASSWORD="N3W3Dm0Ura@#fn5J%4UQKu%vSXWCNbCvj8Ne0FIUs#KG1T&Ouy2lJt$T!#"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

export PGPASSWORD="$DB_PASSWORD"

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}🔍 VÉRIFICATION POST-MIGRATION - VEZA DB${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

# Fonction pour exécuter une requête et afficher le résultat
run_check() {
    local description="$1"
    local query="$2"
    local expected_min="$3"
    
    echo -e "${YELLOW}🔍 $description${NC}"
    
    result=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c "$query" 2>/dev/null | xargs)
    
    if [[ -n "$result" ]]; then
        echo -e "${GREEN}   ✅ $result${NC}"
        
        # Vérifier un minimum si spécifié
        if [[ -n "$expected_min" ]] && [[ "$result" -lt "$expected_min" ]]; then
            echo -e "${YELLOW}   ⚠️  Valeur inférieure à l'attendu ($expected_min)${NC}"
        fi
    else
        echo -e "${RED}   ❌ Aucun résultat${NC}"
    fi
    echo ""
}

# Vérifications des tables principales
echo -e "${BLUE}📋 VÉRIFICATION DES TABLES PRINCIPALES${NC}"
echo ""

run_check "Nombre d'utilisateurs" "SELECT COUNT(*) FROM users;"
run_check "Nombre de messages" "SELECT COUNT(*) FROM messages;"
run_check "Nombre de conversations" "SELECT COUNT(*) FROM conversations;"

# Vérifications de structure
echo -e "${BLUE}🏗️  VÉRIFICATION DE LA STRUCTURE${NC}"
echo ""

# Vérifier les colonnes importantes dans users
run_check "Colonnes users avec UUID" "SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'uuid';" "1"
run_check "Colonnes users avec 2FA" "SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'two_factor_enabled';" "1"

# Vérifier les colonnes dans messages
run_check "Messages avec conversation_id" "SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'conversation_id';" "1"
run_check "Messages avec status" "SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'status';" "1"

# Vérifier les nouvelles tables
echo -e "${BLUE}🆕 VÉRIFICATION DES NOUVELLES TABLES${NC}"
echo ""

tables_to_check=("conversations" "conversation_members" "message_reactions" "message_mentions" "message_history" "user_sessions")

for table in "${tables_to_check[@]}"; do
    count=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = '$table';" 2>/dev/null | xargs)
    
    if [[ "$count" == "1" ]]; then
        echo -e "${GREEN}   ✅ Table $table existe${NC}"
    else
        echo -e "${RED}   ❌ Table $table manquante${NC}"
    fi
done

echo ""

# Vérifier les types énumérés
echo -e "${BLUE}📝 VÉRIFICATION DES TYPES ÉNUMÉRÉS${NC}"
echo ""

enums_to_check=("user_role" "message_status" "conversation_type")

for enum in "${enums_to_check[@]}"; do
    count=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM pg_type WHERE typname = '$enum';" 2>/dev/null | xargs)
    
    if [[ "$count" == "1" ]]; then
        echo -e "${GREEN}   ✅ Type $enum existe${NC}"
    else
        echo -e "${RED}   ❌ Type $enum manquant${NC}"
    fi
done

echo ""

# Vérifier les index importants
echo -e "${BLUE}⚡ VÉRIFICATION DES INDEX DE PERFORMANCE${NC}"
echo ""

indexes_to_check=(
    "idx_users_username_active"
    "idx_messages_conversation_time"
    "idx_messages_author_time"
    "idx_conversations_type_public"
)

for index in "${indexes_to_check[@]}"; do
    count=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM pg_indexes WHERE indexname = '$index';" 2>/dev/null | xargs)
    
    if [[ "$count" == "1" ]]; then
        echo -e "${GREEN}   ✅ Index $index existe${NC}"
    else
        echo -e "${YELLOW}   ⚠️  Index $index manquant (peut être normal si création en cours)${NC}"
    fi
done

echo ""

# Vérifier les contraintes importantes
echo -e "${BLUE}🔒 VÉRIFICATION DES CONTRAINTES${NC}"
echo ""

run_check "Contraintes foreign key sur messages" "SELECT COUNT(*) FROM information_schema.table_constraints WHERE table_name = 'messages' AND constraint_type = 'FOREIGN KEY';"
run_check "Contraintes unique sur users" "SELECT COUNT(*) FROM information_schema.table_constraints WHERE table_name = 'users' AND constraint_type = 'UNIQUE';"

# Vérification des triggers
echo -e "${BLUE}🔔 VÉRIFICATION DES TRIGGERS${NC}"
echo ""

triggers_to_check=(
    "update_users_updated_at"
    "update_conversations_updated_at"
    "update_messages_updated_at"
)

for trigger in "${triggers_to_check[@]}"; do
    count=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_name = '$trigger';" 2>/dev/null | xargs)
    
    if [[ "$count" == "1" ]]; then
        echo -e "${GREEN}   ✅ Trigger $trigger existe${NC}"
    else
        echo -e "${YELLOW}   ⚠️  Trigger $trigger manquant${NC}"
    fi
done

echo ""

# Test de fonctionnalités de base
echo -e "${BLUE}🧪 TESTS DE FONCTIONNALITÉS${NC}"
echo ""

# Test d'insertion d'un utilisateur test
echo -e "${YELLOW}🔍 Test d'insertion utilisateur...${NC}"
test_result=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c "
INSERT INTO users (username, email, role) 
VALUES ('test_migration_user', 'test@migration.com', 'user') 
ON CONFLICT (username) DO NOTHING
RETURNING id;
" 2>/dev/null | xargs)

if [[ -n "$test_result" ]]; then
    echo -e "${GREEN}   ✅ Insertion utilisateur réussie (ID: $test_result)${NC}"
    
    # Nettoyer l'utilisateur test
    psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "DELETE FROM users WHERE username = 'test_migration_user';" > /dev/null 2>&1
else
    echo -e "${YELLOW}   ⚠️  Utilisateur test existe déjà ou erreur d'insertion${NC}"
fi

echo ""

# Résumé final
echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}📊 RÉSUMÉ DE LA VÉRIFICATION${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

# Obtenir les tailles des tables principales
echo -e "${YELLOW}💾 Tailles des tables principales:${NC}"
psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('users', 'conversations', 'messages', 'message_reactions', 'message_mentions', 'user_sessions')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
"

echo ""
echo -e "${GREEN}✅ Vérification post-migration terminée.${NC}"
echo -e "${BLUE}💡 Si vous voyez des avertissements, vérifiez qu'ils sont attendus.${NC}"
echo -e "${BLUE}🔧 En cas de problème, consultez les logs ou contactez le support.${NC}"

unset PGPASSWORD 