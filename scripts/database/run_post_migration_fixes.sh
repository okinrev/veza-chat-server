#!/bin/bash

# ================================================================
# SCRIPT DE CORRECTIONS POST-MIGRATION
# ================================================================

set -e

# Configuration
DB_HOST="10.5.191.47"
DB_USER="veza"
DB_NAME="veza_db"
DB_PASSWORD='N3W3Dm0Ura@#fn5J%4UQKu%vSXWCNbCvj8Ne0FIUs#KG1T&Ouy2lJt$T!#'

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔧 Corrections post-migration...${NC}"
echo ""

export PGPASSWORD="$DB_PASSWORD"

# Exécuter les corrections
if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "migrations/post_migration_fixes.sql"; then
    echo ""
    echo -e "${GREEN}✅ Corrections terminées avec succès!${NC}"
else
    echo -e "${YELLOW}⚠️ Quelques erreurs lors des corrections (peut être normal)${NC}"
fi

# Nettoyer
unset PGPASSWORD

echo -e "${BLUE}🔍 Lancement de la vérification...${NC}"
./scripts/verify_migration.sh 