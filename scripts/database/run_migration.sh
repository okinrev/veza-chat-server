#!/bin/bash

# ================================================================
# SCRIPT DE MIGRATION POUR LA BASE DE DONNÉES VEZA
# ================================================================

set -e  # Arrêter le script en cas d'erreur

# Configuration de la base de données
DB_HOST="10.5.191.47"
DB_USER="veza"
DB_NAME="veza_db"
DB_PASSWORD="N3W3Dm0Ura@#fn5J%4UQKu%vSXWCNbCvj8Ne0FIUs#KG1T&Ouy2lJt$T!#"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}🚀 MIGRATION BASE DE DONNÉES VEZA - Version 0.2.0${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

# Vérifier la disponibilité de psql
if ! command -v psql &> /dev/null; then
    echo -e "${RED}❌ psql n'est pas installé. Veuillez installer PostgreSQL client.${NC}"
    exit 1
fi

# Vérifier la connectivité à la base
echo -e "${YELLOW}🔍 Vérification de la connectivité...${NC}"
export PGPASSWORD="$DB_PASSWORD"

if ! psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" > /dev/null 2>&1; then
    echo -e "${RED}❌ Impossible de se connecter à la base de données.${NC}"
    echo -e "${RED}   Vérifiez les credentials et la connectivité réseau.${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Connexion à la base de données réussie${NC}"
fi

# Demander confirmation avant la migration
echo ""
echo -e "${YELLOW}⚠️  ATTENTION: Cette migration va modifier la structure de votre base de données.${NC}"
echo -e "${YELLOW}   Assurez-vous d'avoir une sauvegarde récente.${NC}"
echo ""
read -p "Voulez-vous continuer? (oui/non): " confirm

if [[ $confirm != "oui" ]]; then
    echo -e "${RED}❌ Migration annulée par l'utilisateur.${NC}"
    exit 0
fi

# Créer une sauvegarde avant migration
echo ""
echo -e "${BLUE}💾 Création d'une sauvegarde de sécurité...${NC}"
BACKUP_FILE="backup_pre_migration_$(date +%Y%m%d_%H%M%S).sql"

if pg_dump -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" > "$BACKUP_FILE" 2>/dev/null; then
    echo -e "${GREEN}✅ Sauvegarde créée: $BACKUP_FILE${NC}"
else
    echo -e "${YELLOW}⚠️  Impossible de créer la sauvegarde automatique.${NC}"
    read -p "Continuer sans sauvegarde? (oui/non): " continue_without_backup
    if [[ $continue_without_backup != "oui" ]]; then
        echo -e "${RED}❌ Migration annulée.${NC}"
        exit 1
    fi
fi

# Exécuter la migration
echo ""
echo -e "${BLUE}🔧 Exécution de la migration...${NC}"
echo ""

if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "migrations/999_cleanup_production_ready_fixed.sql"; then
    echo ""
    echo -e "${GREEN}🎉 Migration terminée avec succès!${NC}"
    echo ""
    echo -e "${BLUE}📊 Résumé des actions effectuées:${NC}"
    echo -e "   • Tables redondantes supprimées"
    echo -e "   • Structure de base modernisée"
    echo -e "   • Index de performance ajoutés"
    echo -e "   • Types énumérés créés"
    echo -e "   • Contraintes de sécurité renforcées"
    echo ""
    echo -e "${BLUE}🔍 Prochaines étapes recommandées:${NC}"
    echo -e "   1. Tester l'application avec la nouvelle structure"
    echo -e "   2. Vérifier les performances"
    echo -e "   3. Configurer la surveillance"
    echo -e "   4. Planifier les sauvegardes régulières"
else
    echo ""
    echo -e "${RED}❌ Erreur lors de la migration!${NC}"
    echo ""
    echo -e "${YELLOW}🔄 Options de récupération:${NC}"
    if [[ -f "$BACKUP_FILE" ]]; then
        echo -e "   • Restaurer la sauvegarde: psql -h $DB_HOST -U $DB_USER -d $DB_NAME < $BACKUP_FILE"
    fi
    echo -e "   • Vérifier les logs d'erreur ci-dessus"
    echo -e "   • Contacter le support si nécessaire"
    exit 1
fi

# Nettoyer la variable d'environnement du mot de passe
unset PGPASSWORD

echo ""
echo -e "${GREEN}✅ Script de migration terminé.${NC}" 