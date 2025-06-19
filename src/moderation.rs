use std::collections::HashMap;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use serde::{Serialize, Deserialize};
use crate::error::{ChatError, Result};
use crate::hub::common::ChatHub;
use crate::permissions::Role;
use sqlx::Row;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum SanctionType {
    Warning,
    Mute,
    Kick,
    TempBan,
    PermaBan,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum SanctionReason {
    Spam,
    Harassment,
    Inappropriate,
    Toxicity,
    RuleViolation,
    Abuse,
    Other(String),
}

#[derive(Debug, Clone, Serialize)]
pub struct Sanction {
    pub id: i32,
    pub user_id: i32,
    pub moderator_id: i32,
    pub sanction_type: SanctionType,
    pub reason: SanctionReason,
    pub message: Option<String>,
    pub duration: Option<Duration>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub expires_at: Option<chrono::DateTime<chrono::Utc>>,
    pub is_active: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct UserModerationRecord {
    pub user_id: i32,
    pub username: String,
    pub sanctions: Vec<Sanction>,
    pub total_warnings: u32,
    pub total_mutes: u32,
    pub total_bans: u32,
    pub reputation_score: i32,
    pub is_currently_banned: bool,
    pub is_currently_muted: bool,
}

/// Système de modération automatique et manuelle
pub struct ModerationSystem {
    hub: std::sync::Arc<ChatHub>,
    auto_sanctions: AutoSanctionRules,
}

#[derive(Debug, Clone)]
pub struct AutoSanctionRules {
    // Seuils pour la modération automatique
    pub max_messages_per_minute: u32,
    pub spam_detection_threshold: f32,
    pub toxicity_threshold: f32,
    pub warning_escalation_count: u32,
    pub auto_mute_duration: Duration,
    pub auto_ban_duration: Duration,
}

impl Default for AutoSanctionRules {
    fn default() -> Self {
        Self {
            max_messages_per_minute: 20,
            spam_detection_threshold: 0.8,
            toxicity_threshold: 0.7,
            warning_escalation_count: 3,
            auto_mute_duration: Duration::from_secs(3600), // 1 heure
            auto_ban_duration: Duration::from_secs(86400), // 24 heures
        }
    }
}

impl ModerationSystem {
    pub fn new(hub: std::sync::Arc<ChatHub>) -> Self {
        Self {
            hub,
            auto_sanctions: AutoSanctionRules::default(),
        }
    }

    /// Applique une sanction manuelle par un modérateur
    pub async fn apply_sanction(
        &self,
        moderator_id: i32,
        moderator_role: &Role,
        target_user_id: i32,
        sanction_type: SanctionType,
        reason: SanctionReason,
        message: Option<String>,
        duration: Option<Duration>,
    ) -> Result<()> {
        // Vérifier les permissions du modérateur
        self.check_moderator_permissions(moderator_role, &sanction_type)?;

        // Vérifier que l'utilisateur cible existe
        if !self.user_exists(target_user_id).await? {
            return Err(ChatError::configuration_error("Utilisateur cible introuvable"));
        }

        // Calculer l'expiration si durée spécifiée
        let expires_at = duration.map(|d| {
            chrono::Utc::now() + chrono::Duration::from_std(d).unwrap_or(chrono::Duration::zero())
        });

        // Insérer la sanction en base
        let sanction_id = self.insert_sanction(
            target_user_id,
            moderator_id,
            &sanction_type,
            &reason,
            message.as_deref(),
            expires_at,
        ).await?;

        // Appliquer les effets de la sanction
        self.enforce_sanction(target_user_id, &sanction_type, duration).await?;

        // Notifier l'utilisateur sanctionné
        self.notify_user_sanctioned(target_user_id, &sanction_type, &reason, message.as_deref()).await?;

        // Audit log
        tracing::warn!(
            sanction_id = %sanction_id,
            moderator_id = %moderator_id,
            target_user_id = %target_user_id,
            sanction_type = ?sanction_type,
            reason = ?reason,
            duration = ?duration,
            "⚖️ Sanction appliquée"
        );

        Ok(())
    }

    /// Vérification automatique d'un message pour détecter les violations
    pub async fn check_message_auto_moderation(
        &self,
        user_id: i32,
        content: &str,
    ) -> Result<Option<SanctionType>> {
        // Détection de spam basique
        if self.detect_spam(user_id, content).await? {
            let user_record = self.get_user_moderation_record(user_id).await?;
            let sanction_type = self.determine_auto_sanction(&user_record).await?;
            
            if let Some(sanction) = &sanction_type {
                self.apply_sanction(
                    0, // ID système
                    &Role::Admin,
                    user_id,
                    sanction.clone(),
                    SanctionReason::Spam,
                    Some("Sanction automatique - spam détecté".to_string()),
                    Some(Duration::from_secs(3600)), // 1 heure
                ).await?;
            }

            return Ok(sanction_type);
        }

        Ok(None)
    }

    /// Lève une sanction (unban, unmute, etc.)
    pub async fn lift_sanction(
        &self,
        moderator_id: i32,
        moderator_role: &Role,
        target_user_id: i32,
        sanction_type: SanctionType,
    ) -> Result<()> {
        // Vérifier les permissions
        self.check_moderator_permissions(moderator_role, &sanction_type)?;

        // Désactiver la sanction en base
        sqlx::query(
            "UPDATE sanctions SET is_active = false WHERE user_id = $1 AND sanction_type = $2 AND is_active = true"
        )
        .bind(target_user_id)
        .bind(serde_json::to_string(&sanction_type).map_err(|e| ChatError::from_json_error(e))?)
        .execute(&self.hub.db)
        .await
        .map_err(|e| ChatError::from_sqlx_error("database_operation", e))?;

        // Retirer les effets de la sanction
        self.remove_sanction_effects(target_user_id, &sanction_type).await?;

        tracing::info!(
            moderator_id = %moderator_id,
            target_user_id = %target_user_id,
            sanction_type = ?sanction_type,
            "✅ Sanction levée"
        );

        Ok(())
    }

    /// Obtient l'historique de modération d'un utilisateur
    pub async fn get_user_moderation_record(&self, user_id: i32) -> Result<UserModerationRecord> {
        let rows = sqlx::query(
            r#"
            SELECT s.*, u.username
            FROM sanctions s
            JOIN users u ON u.id = s.moderator_id
            WHERE s.user_id = $1
            ORDER BY s.created_at DESC
            "#
        )
        .bind(user_id)
        .fetch_all(&self.hub.db)
        .await
        .map_err(|e| ChatError::from_sqlx_error("database_operation", e))?;

        let mut sanctions = Vec::new();
        let mut warning_count = 0;
        let mut mute_count = 0;
        let mut ban_count = 0;
        let mut is_currently_banned = false;
        let mut is_currently_muted = false;

        for row in rows {
            let sanction_type_str: String = row.get("sanction_type");
            let sanction_type: SanctionType = serde_json::from_str(&sanction_type_str)
                .map_err(|e| ChatError::from_json_error(e))?;

            let reason_str: String = row.get("reason");
            let reason: SanctionReason = serde_json::from_str(&reason_str)
                .map_err(|e| ChatError::from_json_error(e))?;

            let is_active: bool = row.get("is_active");
            
            // Compter les types de sanctions
            match sanction_type {
                SanctionType::Warning => warning_count += 1,
                SanctionType::Mute => {
                    mute_count += 1;
                    if is_active {
                        is_currently_muted = true;
                    }
                },
                SanctionType::TempBan | SanctionType::PermaBan => {
                    ban_count += 1;
                    if is_active {
                        is_currently_banned = true;
                    }
                },
                _ => {}
            }

            sanctions.push(Sanction {
                id: row.get("id"),
                user_id: row.get("user_id"),
                moderator_id: row.get("moderator_id"),
                sanction_type,
                reason,
                message: row.get("message"),
                duration: None, // Simplifié pour cet exemple
                created_at: row.get("created_at"),
                expires_at: row.get("expires_at"),
                is_active,
            });
        }

        // Calculer un score de réputation basique
        let reputation_score = 100 - (warning_count as i32 * 5) - (mute_count as i32 * 15) - (ban_count as i32 * 50);

        // Obtenir le nom d'utilisateur
        let username = self.get_username(user_id).await?;

        Ok(UserModerationRecord {
            user_id,
            username,
            sanctions,
            total_warnings: warning_count,
            total_mutes: mute_count,
            total_bans: ban_count,
            reputation_score,
            is_currently_banned,
            is_currently_muted,
        })
    }

    /// Détection de spam basique
    async fn detect_spam(&self, user_id: i32, content: &str) -> Result<bool> {
        // Vérifier les messages répétitifs
        let recent_messages = sqlx::query(
            "SELECT content FROM messages WHERE user_id = $1 AND created_at > NOW() - INTERVAL '5 minutes' ORDER BY created_at DESC LIMIT 5"
        )
        .bind(user_id)
        .fetch_all(&self.hub.db)
        .await
        .map_err(|e| ChatError::from_sqlx_error("database_operation", e))?;

        let similar_count = recent_messages.iter()
            .filter(|row| {
                let msg_content: String = row.get("content");
                self.calculate_similarity(content, &msg_content) > 0.8
            })
            .count();

        Ok(similar_count >= 3)
    }

    /// Détection de contenu inapproprié
    async fn detect_inappropriate_content(&self, content: &str) -> Result<bool> {
        // Liste de mots interdits basique
        let forbidden_words = ["inappropriate", "badword1", "badword2"]; // Remplacer par vraie liste
        let content_lower = content.to_lowercase();
        
        Ok(forbidden_words.iter().any(|word| content_lower.contains(word)))
    }

    /// Détection de toxicité (simplifiée)
    async fn detect_toxicity(&self, content: &str) -> Result<bool> {
        // Ici on pourrait intégrer une API de détection de toxicité comme Perspective API
        // Pour l'exemple, détection basique
        let toxic_patterns = ["idiot", "stupid", "hate you"];
        let content_lower = content.to_lowercase();
        
        Ok(toxic_patterns.iter().any(|pattern| content_lower.contains(pattern)))
    }

    /// Calcule la similarité entre deux strings (simplifiée)
    fn calculate_similarity(&self, a: &str, b: &str) -> f32 {
        if a == b {
            return 1.0;
        }
        
        let a_len = a.len() as f32;
        let b_len = b.len() as f32;
        let max_len = a_len.max(b_len);
        
        if max_len == 0.0 {
            return 1.0;
        }
        
        // Distance de Levenshtein simplifiée
        let common_chars = a.chars().filter(|c| b.contains(*c)).count() as f32;
        common_chars / max_len
    }

    /// Détermine la sanction automatique appropriée
    async fn determine_auto_sanction(&self, user_record: &UserModerationRecord) -> Result<Option<SanctionType>> {
        match user_record.total_warnings {
            0 => Ok(Some(SanctionType::Warning)),
            1..=2 => Ok(Some(SanctionType::Mute)),
            _ => Ok(Some(SanctionType::TempBan)),
        }
    }

    /// Implémentations helpers simplifiées
    fn check_moderator_permissions(&self, role: &Role, sanction: &SanctionType) -> Result<()> {
        match sanction {
            SanctionType::Warning | SanctionType::Mute => {
                if matches!(role, Role::Admin | Role::Moderator) {
                    Ok(())
                } else {
                    Err(ChatError::unauthorized_simple("unauthorized_action"))
                }
            },
            SanctionType::Kick | SanctionType::TempBan => {
                if matches!(role, Role::Admin | Role::Moderator) {
                    Ok(())
                } else {
                    Err(ChatError::unauthorized_simple("unauthorized_action"))
                }
            },
            SanctionType::PermaBan => {
                if matches!(role, Role::Admin) {
                    Ok(())
                } else {
                    Err(ChatError::unauthorized_simple("unauthorized_action"))
                }
            },
        }
    }

    async fn user_exists(&self, user_id: i32) -> Result<bool> {
        let row = sqlx::query("SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)")
            .bind(user_id)
            .fetch_one(&self.hub.db)
            .await
            .map_err(|e| ChatError::from_sqlx_error("database_operation", e))?;
        Ok(row.get(0))
    }

    async fn get_username(&self, user_id: i32) -> Result<String> {
        let row = sqlx::query("SELECT username FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_one(&self.hub.db)
            .await
            .map_err(|e| ChatError::from_sqlx_error("database_operation", e))?;
        Ok(row.get(0))
    }

    async fn insert_sanction(
        &self,
        user_id: i32,
        moderator_id: i32,
        sanction_type: &SanctionType,
        reason: &SanctionReason,
        message: Option<&str>,
        expires_at: Option<chrono::DateTime<chrono::Utc>>,
    ) -> Result<i32> {
        let row = sqlx::query(
            "INSERT INTO sanctions (user_id, moderator_id, sanction_type, reason, message, expires_at) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id"
        )
        .bind(user_id)
        .bind(moderator_id)
        .bind(serde_json::to_string(sanction_type).map_err(|e| ChatError::from_json_error(e))?)
        .bind(serde_json::to_string(reason).map_err(|e| ChatError::from_json_error(e))?)
        .bind(message)
        .bind(expires_at)
        .fetch_one(&self.hub.db)
        .await
        .map_err(|e| ChatError::from_sqlx_error("database_operation", e))?;
        
        Ok(row.get(0))
    }

    async fn enforce_sanction(&self, user_id: i32, sanction_type: &SanctionType, _duration: Option<Duration>) -> Result<()> {
        // Ici on appliquerait les effets réels (déconnecter, bloquer messages, etc.)
        tracing::info!(user_id = %user_id, sanction_type = ?sanction_type, "⚖️ Sanction appliquée");
        Ok(())
    }

    async fn remove_sanction_effects(&self, user_id: i32, sanction_type: &SanctionType) -> Result<()> {
        // Ici on retirerait les effets (débloquer, etc.)
        tracing::info!(user_id = %user_id, sanction_type = ?sanction_type, "✅ Effets de sanction retirés");
        Ok(())
    }

    async fn notify_user_sanctioned(&self, user_id: i32, sanction_type: &SanctionType, _reason: &SanctionReason, _message: Option<&str>) -> Result<()> {
        // Ici on notifierait l'utilisateur
        tracing::info!(user_id = %user_id, sanction_type = ?sanction_type, "📢 Utilisateur notifié de la sanction");
        Ok(())
    }

    fn get_auto_sanction_duration(&self, sanction_type: &SanctionType) -> Option<Duration> {
        match sanction_type {
            SanctionType::Mute => Some(self.auto_sanctions.auto_mute_duration),
            SanctionType::TempBan => Some(self.auto_sanctions.auto_ban_duration),
            _ => None,
        }
    }
} 