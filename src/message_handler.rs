use std::sync::Arc;
use crate::error::{ChatError, Result};
use crate::hub::common::ChatHub;
use crate::permissions::{Role, Permission, check_permission};
use crate::security::ContentFilter;
use serde_json::json;
use tokio::sync::mpsc::UnboundedSender;
use tokio_tungstenite::tungstenite::Message;

/// Gestionnaire centralisé pour tous les types de messages
pub struct MessageHandler {
    hub: Arc<ChatHub>,
    content_filter: ContentFilter,
}

impl MessageHandler {
    pub fn new(hub: Arc<ChatHub>) -> Result<Self> {
        Ok(Self {
            hub,
            content_filter: ContentFilter::new()?,
        })
    }

    /// Gère les messages de salon avec permissions
    pub async fn handle_room_message(
        &self,
        user_id: i32,
        username: &str,
        user_role: &Role,
        room: &str,
        content: &str,
    ) -> Result<()> {
        // Vérification des permissions
        check_permission(user_role, Permission::SendMessage)?;

        // Validation et sanitisation du contenu
        let clean_room = self.content_filter.validate_room_name(room)?;
        let clean_content = self.content_filter.sanitize_content(content)?;

        // Vérification que l'utilisateur est dans le salon
        if !self.is_user_in_room(user_id, &clean_room).await {
            return Err(ChatError::configuration_error("Vous devez rejoindre le salon avant d'envoyer un message"));
        }

        // Audit log
        tracing::info!(
            user_id = %user_id,
            username = %username,
            room = %clean_room,
            message_length = %clean_content.len(),
            "📝 Message salon autorisé"
        );

        // Délégation à la logique métier
        crate::hub::room::broadcast_to_room(&self.hub, user_id, username, &clean_room, &clean_content).await
    }

    /// Gère les messages directs avec permissions
    pub async fn handle_direct_message(
        &self,
        from_user: i32,
        from_username: &str,
        user_role: &Role,
        to_user: i32,
        content: &str,
    ) -> Result<()> {
        // Vérification des permissions
        check_permission(user_role, Permission::SendDirectMessage)?;

        // Validation et sanitisation
        let clean_content = self.content_filter.sanitize_content(content)?;

        // Vérification anti-spam pour DM
        if !self.hub.check_rate_limit(from_user).await {
            return Err(ChatError::rate_limit_exceeded_simple("rate_limit"));
        }

        // Vérification que l'utilisateur destinataire n'a pas bloqué l'expéditeur
        if self.is_user_blocked(from_user, to_user).await? {
            // Ne pas révéler que l'utilisateur est bloqué pour la confidentialité
            tracing::warn!(from_user = %from_user, to_user = %to_user, "🚫 Message DM bloqué");
            return Ok(());
        }

        // Audit log
        tracing::info!(
            from_user = %from_user,
            from_username = %from_username,
            to_user = %to_user,
            message_length = %clean_content.len(),
            "📝 Message direct autorisé"
        );

        // Délégation à la logique métier
        crate::hub::dm::send_dm(&self.hub, from_user, to_user, from_username, &clean_content).await
    }

    /// Gère la jointure d'un salon avec permissions
    pub async fn handle_join_room(
        &self,
        user_id: i32,
        username: &str,
        user_role: &Role,
        room: &str,
        sender: &UnboundedSender<Message>,
    ) -> Result<()> {
        // Vérification des permissions
        check_permission(user_role, Permission::JoinRoom)?;

        // Validation du nom de salon
        let clean_room = self.content_filter.validate_room_name(room)?;

        // Vérification que le salon existe ou peut être créé
        let room_exists = crate::hub::room::room_exists(&self.hub, &clean_room).await?;
        
        if !room_exists {
            // Seuls les utilisateurs avec permission peuvent créer des salons
            if user_role.has_permission(&Permission::CreateRoom) {
                tracing::info!(user_id = %user_id, room = %clean_room, "🏗️ Création d'un nouveau salon");
                // Ici on pourrait créer le salon en base
            } else {
                return Err(ChatError::configuration_error("Salon inexistant et vous n'avez pas la permission de le créer"));
            }
        }

        // Audit log
        tracing::info!(
            user_id = %user_id,
            username = %username,
            room = %clean_room,
            "👥 Jointure salon autorisée"
        );

        // Délégation à la logique métier
        crate::hub::room::join_room(&self.hub, &clean_room, user_id).await?;

        // Envoi de confirmation
        let ack_msg = json!({
            "type": "join_ack",
            "data": {
                "room": clean_room,
                "status": "success",
                "message": "Salon rejoint avec succès"
            }
        });

        let response = Message::Text(ack_msg.to_string());
        sender.send(response).map_err(|_| ChatError::configuration_error("Impossible d'envoyer la confirmation"))?;

        Ok(())
    }

    /// Gère la récupération d'historique avec permissions
    pub async fn handle_room_history(
        &self,
        user_id: i32,
        user_role: &Role,
        room: &str,
        limit: i64,
        sender: &UnboundedSender<Message>,
    ) -> Result<()> {
        // Vérification des permissions
        check_permission(user_role, Permission::ViewRoomHistory)?;

        // Validation
        let clean_room = self.content_filter.validate_room_name(room)?;

        // Vérification que l'utilisateur a accès au salon
        if !self.is_user_in_room(user_id, &clean_room).await {
            return Err(ChatError::configuration_error("Vous devez être membre du salon pour voir l'historique"));
        }

        // Délégation à la logique métier
        let messages = crate::hub::room::fetch_room_history(&self.hub, &clean_room, limit).await?;

        // Envoi de la réponse
        let history_msg = json!({
            "type": "room_history",
            "data": {
                "room": clean_room,
                "messages": messages,
                "count": messages.len()
            }
        });

        let response = Message::Text(history_msg.to_string());
        sender.send(response).map_err(|_| ChatError::configuration_error("Impossible d'envoyer l'historique"))?;

        tracing::info!(
            user_id = %user_id,
            room = %clean_room,
            message_count = %messages.len(),
            "📜 Historique salon envoyé"
        );

        Ok(())
    }

    /// Gère la récupération d'historique DM avec permissions
    pub async fn handle_dm_history(
        &self,
        user_id: i32,
        user_role: &Role,
        with_user: i32,
        limit: i64,
        sender: &UnboundedSender<Message>,
    ) -> Result<()> {
        // Vérification des permissions
        check_permission(user_role, Permission::ViewDirectMessageHistory)?;

        // Vérification que l'utilisateur ne demande pas l'historique avec lui-même
        if user_id == with_user {
            return Err(ChatError::configuration_error("Impossible de récupérer l'historique avec soi-même"));
        }

        // Délégation à la logique métier
        let messages = crate::hub::dm::fetch_dm_history(&self.hub, user_id, with_user, limit).await?;

        // Envoi de la réponse
        let history_msg = json!({
            "type": "dm_history",
            "data": {
                "with": with_user,
                "messages": messages,
                "count": messages.len()
            }
        });

        let response = Message::Text(history_msg.to_string());
        sender.send(response).map_err(|_| ChatError::configuration_error("Impossible d'envoyer l'historique"))?;

        tracing::info!(
            user_id = %user_id,
            with_user = %with_user,
            message_count = %messages.len(),
            "📜 Historique DM envoyé"
        );

        Ok(())
    }

    /// Vérifie si un utilisateur est dans un salon
    async fn is_user_in_room(&self, user_id: i32, room: &str) -> bool {
        let rooms = self.hub.rooms.read().await;
        rooms.get(room)
            .map(|users| users.contains(&user_id))
            .unwrap_or(false)
    }

    /// Vérifie si un utilisateur en a bloqué un autre
    async fn is_user_blocked(&self, _from_user: i32, _to_user: i32) -> Result<bool> {
        // Ici on pourrait vérifier en base de données une table de blocages
        // Pour l'instant, retourne false
        // TODO: Implémenter la logique de blocage
        Ok(false)
    }
} 