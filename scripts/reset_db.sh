#!/bin/bash

# Script de réinitialisation de la base de données Veza Chat Server
# ⚠️  ATTENTION: Ce script supprime toutes les données existantes !

set -e

# Configuration par défaut
DB_NAME="${CHAT_SERVER__DATABASE__NAME:-veza_chat}"
DB_USER="${CHAT_SERVER__DATABASE__USER:-postgres}"
DB_HOST="${CHAT_SERVER__DATABASE__HOST:-10.5.191.47}"
DB_PORT="${CHAT_SERVER__DATABASE__PORT:-5432}"

echo "🔄 Réinitialisation de la base de données '$DB_NAME'..."

# Fonction pour exécuter des commandes SQL
run_sql() {
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$1" -c "$2"
}

# Fonction pour exécuter un fichier SQL
run_sql_file() {
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$1" -f "$2"
}

echo "📋 Vérification de la connexion à PostgreSQL..."
if ! PGPASSWORD="$POSTGRES_PASSWORD" pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER"; then
    echo "❌ Impossible de se connecter à PostgreSQL"
    echo "Vérifiez que PostgreSQL est démarré et que les variables d'environnement sont correctes:"
    echo "  POSTGRES_PASSWORD (requis)"
    echo "  CHAT_SERVER__DATABASE__HOST (défaut: 10.5.191.47)"
    echo "  CHAT_SERVER__DATABASE__PORT (défaut: 5432)"
    echo "  CHAT_SERVER__DATABASE__USER (défaut: postgres)"
    exit 1
fi

echo "✅ Connexion PostgreSQL OK"

# Arrêter toutes les connexions actives à la base
echo "🔌 Fermeture des connexions actives..."
run_sql "postgres" "
    SELECT pg_terminate_backend(pg_stat_activity.pid)
    FROM pg_stat_activity
    WHERE pg_stat_activity.datname = '$DB_NAME'
      AND pid <> pg_backend_pid();
" 2>/dev/null || true

# Supprimer et recréer la base de données
echo "🗑️  Suppression de la base de données existante..."
run_sql "postgres" "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null || true

echo "🆕 Création de la nouvelle base de données..."
run_sql "postgres" "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

# Activer les extensions nécessaires
echo "🔧 Activation des extensions PostgreSQL..."
run_sql "$DB_NAME" "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"
run_sql "$DB_NAME" "CREATE EXTENSION IF NOT EXISTS \"pgcrypto\";"

# Appliquer la migration de base propre
echo "📊 Application de la structure de base de données propre..."
if [ -f "migrations/001_create_clean_database.sql" ]; then
    run_sql_file "$DB_NAME" "migrations/001_create_clean_database.sql"
    echo "✅ Structure de base appliquée"
else
    echo "❌ Fichier de migration 001_create_clean_database.sql introuvable"
    exit 1
fi

# Vérifier la structure créée
echo "🔍 Vérification de la structure..."
TABLES=$(run_sql "$DB_NAME" "
    SELECT COUNT(*) 
    FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_type = 'BASE TABLE';
" -t | xargs)

echo "📋 Tables créées: $TABLES"

if [ "$TABLES" -gt 0 ]; then
    echo "✅ Base de données réinitialisée avec succès !"
    echo ""
    echo "📊 Résumé de la structure créée:"
    run_sql "$DB_NAME" "
        SELECT 
            schemaname,
            tablename,
            tableowner
        FROM pg_tables 
        WHERE schemaname = 'public'
        ORDER BY tablename;
    "
    
    echo ""
    echo "🎯 Étapes suivantes:"
    echo "  1. Configurer vos variables d'environnement (.env)"
    echo "  2. Lancer le serveur: cargo run"
    echo "  3. Tester avec les utilisateurs par défaut:"
    echo "     - admin:admin123"
    echo "     - testuser:test123"
else
    echo "❌ Erreur lors de la création de la structure"
    exit 1
fi 