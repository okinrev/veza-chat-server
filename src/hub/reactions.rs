//! Module de gestion des réactions aux messages
//! 
//! Fonctionnalités :
//! - Ajouter/supprimer des réactions emoji
//! - Compter les réactions par type
//! - Historique des réactions
//! - Limitations et validation
//! - Support pour DM et salons

use sqlx::{query, query_as, FromRow, Row};
use serde::{Serialize, Deserialize};
use crate::hub::common::ChatHub;
use crate::validation::validate_user_id;
use crate::error::{ChatError, Result};
use serde_json::json;
use chrono::{DateTime, Utc};

// ================================================================
// STRUCTURES DE DONNÉES
// ================================================================

#[derive(Debug, FromRow, Serialize, Deserialize)]
pub struct MessageReaction {
    pub id: i64,
    pub message_id: i64,
    pub user_id: i64,
    pub emoji: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
pub struct ReactionSummary {
    pub emoji: String,
    pub count: i64,
    pub users: Vec<ReactionUser>,
}

#[derive(Debug, FromRow, Serialize)]
pub struct ReactionUser {
    pub user_id: i64,
    pub username: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
pub struct MessageReactions {
    pub message_id: i64,
    pub total_reactions: i64,
    pub reactions: Vec<ReactionSummary>,
}

// ================================================================
// GESTION DES RÉACTIONS
// ================================================================

/// Ajouter une réaction à un message
pub async fn add_reaction(
    hub: &ChatHub,
    message_id: i64,
    user_id: i64,
    emoji: &str
) -> Result<()> {
    tracing::info!(user_id = %user_id, message_id = %message_id, emoji = %emoji, "😊 Ajout d'une réaction");
    
    validate_user_id(user_id as i32)?;
    validate_emoji(emoji)?;
    
    let mut tx = hub.db.begin().await
        .map_err(|e| ChatError::from_sqlx_error("begin_transaction", e))?;
    
    // Vérifier que le message existe et que l'utilisateur a accès
    let message_access = check_message_access(&mut tx, message_id, user_id).await?;
    if !message_access {
        return Err(ChatError::unauthorized("add_reaction"));
    }
    
    // Vérifier la limite de réactions par utilisateur par message (max 10)
    let user_reaction_count: i64 = query("
        SELECT COUNT(*) 
        FROM message_reactions 
        WHERE message_id = $1 AND user_id = $2
    ")
    .bind(message_id)
    .bind(user_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("count_user_reactions", e))?
    .get(0);
    
    if user_reaction_count >= 10 {
        return Err(ChatError::configuration_error("Limite de réactions par message atteinte"));
    }
    
    // Ajouter la réaction (ou ne rien faire si elle existe déjà)
    let rows_affected = query("
        INSERT INTO message_reactions (message_id, user_id, emoji)
        VALUES ($1, $2, $3)
        ON CONFLICT (message_id, user_id, emoji) DO NOTHING
    ")
    .bind(message_id)
    .bind(user_id)
    .bind(emoji)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("insert_reaction", e))?
    .rows_affected();
    
    if rows_affected == 0 {
        return Err(ChatError::configuration_error("Réaction déjà présente"));
    }
    
    // Log d'audit
    query("
        INSERT INTO audit_logs (action, details, user_id)
        VALUES ('reaction_added', $1, $2)
    ")
    .bind(json!({
        "message_id": message_id,
        "emoji": emoji
    }))
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("audit_log", e))?;
    
    tx.commit().await
        .map_err(|e| ChatError::from_sqlx_error("commit_transaction", e))?;
    
    // Notifier en temps réel
    broadcast_reaction_update(hub, message_id, "added", user_id, emoji).await?;
    
    tracing::info!(user_id = %user_id, message_id = %message_id, emoji = %emoji, "✅ Réaction ajoutée");
    Ok(())
}

/// Supprimer une réaction d'un message
pub async fn remove_reaction(
    hub: &ChatHub,
    message_id: i64,
    user_id: i64,
    emoji: &str
) -> Result<()> {
    tracing::info!(user_id = %user_id, message_id = %message_id, emoji = %emoji, "🗑️ Suppression d'une réaction");
    
    validate_user_id(user_id as i32)?;
    validate_emoji(emoji)?;
    
    let mut tx = hub.db.begin().await
        .map_err(|e| ChatError::from_sqlx_error("begin_transaction", e))?;
    
    // Vérifier l'accès au message
    let message_access = check_message_access(&mut tx, message_id, user_id).await?;
    if !message_access {
        return Err(ChatError::unauthorized("remove_reaction"));
    }
    
    // Supprimer la réaction
    let rows_affected = query("
        DELETE FROM message_reactions 
        WHERE message_id = $1 AND user_id = $2 AND emoji = $3
    ")
    .bind(message_id)
    .bind(user_id)
    .bind(emoji)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("delete_reaction", e))?
    .rows_affected();
    
    if rows_affected == 0 {
        return Err(ChatError::not_found("réaction", &format!("{}:{}", message_id, emoji)));
    }
    
    // Log d'audit
    query("
        INSERT INTO audit_logs (action, details, user_id)
        VALUES ('reaction_removed', $1, $2)
    ")
    .bind(json!({
        "message_id": message_id,
        "emoji": emoji
    }))
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("audit_log", e))?;
    
    tx.commit().await
        .map_err(|e| ChatError::from_sqlx_error("commit_transaction", e))?;
    
    // Notifier en temps réel
    broadcast_reaction_update(hub, message_id, "removed", user_id, emoji).await?;
    
    tracing::info!(user_id = %user_id, message_id = %message_id, emoji = %emoji, "✅ Réaction supprimée");
    Ok(())
}

/// Basculer une réaction (ajouter si absente, supprimer si présente)
pub async fn toggle_reaction(
    hub: &ChatHub,
    message_id: i64,
    user_id: i64,
    emoji: &str
) -> Result<bool> {
    tracing::info!(user_id = %user_id, message_id = %message_id, emoji = %emoji, "🔄 Basculement de réaction");
    
    validate_user_id(user_id as i32)?;
    validate_emoji(emoji)?;
    
    // Vérifier si la réaction existe déjà
    let reaction_exists: bool = query("
        SELECT EXISTS(
            SELECT 1 FROM message_reactions 
            WHERE message_id = $1 AND user_id = $2 AND emoji = $3
        )
    ")
    .bind(message_id)
    .bind(user_id)
    .bind(emoji)
    .fetch_one(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("check_reaction_exists", e))?
    .get(0);
    
    if reaction_exists {
        remove_reaction(hub, message_id, user_id, emoji).await?;
        Ok(false) // Réaction supprimée
    } else {
        add_reaction(hub, message_id, user_id, emoji).await?;
        Ok(true) // Réaction ajoutée
    }
}

// ================================================================
// CONSULTATION DES RÉACTIONS
// ================================================================

/// Obtenir toutes les réactions d'un message
pub async fn get_message_reactions(
    hub: &ChatHub,
    message_id: i64,
    requesting_user_id: i64
) -> Result<MessageReactions> {
    tracing::info!(message_id = %message_id, user_id = %requesting_user_id, "📊 Récupération des réactions du message");
    
    validate_user_id(requesting_user_id as i32)?;
    
    // Vérifier l'accès au message
    let mut tx = hub.db.begin().await
        .map_err(|e| ChatError::from_sqlx_error("begin_transaction", e))?;
    
    let message_access = check_message_access(&mut tx, message_id, requesting_user_id).await?;
    if !message_access {
        return Err(ChatError::unauthorized("get_message_reactions"));
    }
    
    tx.commit().await
        .map_err(|e| ChatError::from_sqlx_error("commit_transaction", e))?;
    
    // Récupérer les réactions groupées par emoji
    let reactions = query_as::<_, (String, i64)>("
        SELECT emoji, COUNT(*) as count
        FROM message_reactions 
        WHERE message_id = $1
        GROUP BY emoji
        ORDER BY count DESC, emoji
    ")
    .bind(message_id)
    .fetch_all(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("get_reaction_counts", e))?;
    
    let total_reactions: i64 = reactions.iter().map(|(_, count)| count).sum();
    
    // Pour chaque emoji, récupérer les détails des utilisateurs
    let mut reaction_summaries = Vec::new();
    
    for (emoji, count) in reactions {
        let users = query_as::<_, ReactionUser>("
            SELECT mr.user_id, u.username, mr.created_at
            FROM message_reactions mr
            JOIN users u ON u.id = mr.user_id
            WHERE mr.message_id = $1 AND mr.emoji = $2
            ORDER BY mr.created_at ASC
        ")
        .bind(message_id)
        .bind(&emoji)
        .fetch_all(&hub.db)
        .await
        .map_err(|e| ChatError::from_sqlx_error("get_reaction_users", e))?;
        
        reaction_summaries.push(ReactionSummary {
            emoji,
            count,
            users,
        });
    }
    
    let message_reactions = MessageReactions {
        message_id,
        total_reactions,
        reactions: reaction_summaries,
    };
    
    tracing::info!(message_id = %message_id, total_reactions = %total_reactions, "✅ Réactions du message récupérées");
    Ok(message_reactions)
}

/// Obtenir les réactions d'un utilisateur
pub async fn get_user_reactions(
    hub: &ChatHub,
    user_id: i64,
    limit: i64
) -> Result<Vec<MessageReaction>> {
    tracing::info!(user_id = %user_id, limit = %limit, "👤 Récupération des réactions de l'utilisateur");
    
    validate_user_id(user_id as i32)?;
    
    let reactions = query_as::<_, MessageReaction>("
        SELECT id, message_id, user_id, emoji, created_at
        FROM message_reactions
        WHERE user_id = $1
        ORDER BY created_at DESC
        LIMIT $2
    ")
    .bind(user_id)
    .bind(limit)
    .fetch_all(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("get_user_reactions", e))?;
    
    tracing::info!(user_id = %user_id, reaction_count = %reactions.len(), "✅ Réactions de l'utilisateur récupérées");
    Ok(reactions)
}

/// Obtenir les emojis les plus utilisés
pub async fn get_popular_emojis(hub: &ChatHub, limit: i64) -> Result<Vec<(String, i64)>> {
    tracing::info!(limit = %limit, "📈 Récupération des emojis populaires");
    
    let popular_emojis = query_as::<_, (String, i64)>("
        SELECT emoji, COUNT(*) as usage_count
        FROM message_reactions
        WHERE created_at > NOW() - INTERVAL '30 days'
        GROUP BY emoji
        ORDER BY usage_count DESC
        LIMIT $1
    ")
    .bind(limit)
    .fetch_all(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("get_popular_emojis", e))?;
    
    tracing::info!(emoji_count = %popular_emojis.len(), "✅ Emojis populaires récupérés");
    Ok(popular_emojis)
}

// ================================================================
// GESTION DES ÉVÉNEMENTS EN TEMPS RÉEL
// ================================================================

/// Diffuser une mise à jour de réaction en temps réel
async fn broadcast_reaction_update(
    hub: &ChatHub,
    message_id: i64,
    action: &str, // "added" ou "removed"
    user_id: i64,
    emoji: &str
) -> Result<()> {
    // Récupérer les utilisateurs qui ont accès au message
    let users_with_access = get_message_access_users(hub, message_id).await?;
    
    let payload = json!({
        "type": "reaction_update",
        "data": {
            "messageId": message_id,
            "action": action,
            "userId": user_id,
            "emoji": emoji,
            "timestamp": Utc::now()
        }
    });
    
    let clients = hub.clients.read().await;
    let mut successful_sends = 0;
    
    for access_user_id in users_with_access {
        if let Some(client) = clients.get(&(access_user_id as i32)) {
            if client.send_text(&payload.to_string()) {
                successful_sends += 1;
            }
        }
    }
    
    tracing::info!(
        message_id = %message_id,
        action = %action,
        successful_sends = %successful_sends,
        "📡 Mise à jour de réaction diffusée"
    );
    
    Ok(())
}

// ================================================================
// FONCTIONS UTILITAIRES
// ================================================================

/// Valider un emoji (caractères autorisés et longueur)
fn validate_emoji(emoji: &str) -> Result<()> {
    if emoji.is_empty() || emoji.len() > 20 {
        return Err(ChatError::configuration_error("Emoji invalide"));
    }
    
    // Vérifier que l'emoji ne contient que des caractères autorisés
    // (émojis Unicode, lettres, chiffres, quelques symboles)
    let allowed = emoji.chars().all(|c| {
        c.is_alphanumeric() || 
        c.is_ascii_punctuation() ||
        (c as u32 >= 0x1F600 && c as u32 <= 0x1F64F) || // Émojis visages
        (c as u32 >= 0x1F300 && c as u32 <= 0x1F5FF) || // Émojis divers
        (c as u32 >= 0x1F680 && c as u32 <= 0x1F6FF) || // Émojis transport
        (c as u32 >= 0x2600 && c as u32 <= 0x26FF) ||   // Émojis divers
        (c as u32 >= 0x2700 && c as u32 <= 0x27BF)      // Dingbats
    });
    
    if !allowed {
        return Err(ChatError::configuration_error("Caractères non autorisés dans l'emoji"));
    }
    
    Ok(())
}

/// Vérifier si un utilisateur a accès à un message
async fn check_message_access(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    message_id: i64,
    user_id: i64
) -> Result<bool> {
    // Vérifier si c'est un message dans une conversation où l'utilisateur est membre
    let has_access: bool = query("
        SELECT EXISTS(
            SELECT 1 FROM messages m
            JOIN conversations c ON c.id = m.conversation_id
            LEFT JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.user_id = $2 AND cm.left_at IS NULL
            WHERE m.id = $1 
            AND (
                c.is_public = TRUE OR
                cm.user_id IS NOT NULL OR
                m.author_id = $2
            )
        )
    ")
    .bind(message_id)
    .bind(user_id)
    .fetch_one(&mut **tx)
    .await
    .map_err(|e| ChatError::from_sqlx_error("check_message_access", e))?
    .get(0);
    
    Ok(has_access)
}

/// Obtenir la liste des utilisateurs qui ont accès à un message
async fn get_message_access_users(hub: &ChatHub, message_id: i64) -> Result<Vec<i64>> {
    let users = query("
        SELECT DISTINCT cm.user_id
        FROM messages m
        JOIN conversations c ON c.id = m.conversation_id
        JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.left_at IS NULL
        WHERE m.id = $1
        
        UNION
        
        SELECT m.author_id
        FROM messages m
        WHERE m.id = $1
    ")
    .bind(message_id)
    .fetch_all(&hub.db)
    .await
    .map_err(|e| ChatError::from_sqlx_error("get_message_access_users", e))?
    .into_iter()
    .map(|row| row.get::<i64, _>("user_id"))
    .collect();
    
    Ok(users)
} 