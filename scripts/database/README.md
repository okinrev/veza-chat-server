# Scripts de Base de Données

Scripts pour la gestion des migrations et de la structure de base de données.

## Scripts disponibles

### `run_migration.sh`
Exécute toutes les migrations en séquence.

```bash
./run_migration.sh
```

### `run_dm_migration.sh`
Exécute spécifiquement les migrations pour les messages directs enrichis.

```bash
./run_dm_migration.sh
```

### `run_post_migration_fixes.sh`
Applique les corrections post-migration (index, contraintes, etc.).

```bash
./run_post_migration_fixes.sh
```

### `verify_migration.sh`
Vérifie l'intégrité de la base de données après migration.

```bash
./verify_migration.sh
```

## Ordre d'exécution recommandé

1. `run_migration.sh` - Migrations principales
2. `run_dm_migration.sh` - Migrations DM spécifiques  
3. `run_post_migration_fixes.sh` - Corrections finales
4. `verify_migration.sh` - Vérification

## Variables d'environnement requises

- `DATABASE_URL` - URL de connexion PostgreSQL
- `POSTGRES_DB` - Nom de la base de données
- `POSTGRES_USER` - Utilisateur PostgreSQL
- `POSTGRES_PASSWORD` - Mot de passe PostgreSQL 