# Scripts Veza Chat Server

Ce répertoire contient tous les scripts d'administration et de maintenance du serveur de chat.

## Structure

- **`database/`** - Scripts de gestion de la base de données
  - Migrations
  - Vérifications
  - Mises à jour de schéma

- **`maintenance/`** - Scripts de maintenance système
  - Nettoyage de base de données
  - Réinitialisation
  - Sauvegarde/restauration

- **`testing/`** - Scripts de test
  - Tests d'intégration
  - Tests de fonctionnalités enrichies
  - Validation de déploiement

- **`deploy.sh`** - Script principal de déploiement

## Usage

Chaque sous-répertoire contient ses propres instructions d'usage.
Consultez les README spécifiques pour plus de détails.

## Prérequis

- PostgreSQL 14+
- Rust 1.70+
- Variables d'environnement configurées dans `.env` 