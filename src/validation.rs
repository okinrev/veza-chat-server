use crate::error::{ChatError, Result};

pub fn validate_message_content(content: &str, max_size: usize) -> Result<()> {
    if content.is_empty() {
        return Err(ChatError::configuration_error("Le message ne peut pas être vide"));
    }

    if content.len() > max_size {
        return Err(ChatError::message_too_long(content.len(), max_size));
    }

    // Vérifier les caractères de contrôle dangereux
    if content.chars().any(|c| c.is_control() && c != '\n' && c != '\r' && c != '\t') {
        return Err(ChatError::configuration_error("Caractères de contrôle non autorisés"));
    }

    Ok(())
}

pub fn validate_room_name(room: &str) -> Result<()> {
    if room.is_empty() {
        return Err(ChatError::configuration_error("Le nom du salon ne peut pas être vide"));
    }

    if room.len() > 100 {
        return Err(ChatError::configuration_error("Le nom du salon est trop long (max 100 caractères)"));
    }

    // Vérifier que le nom ne contient que des caractères alphanumériques, tirets et underscores
    if !room.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_') {
        return Err(ChatError::configuration_error("Le nom du salon ne peut contenir que des lettres, chiffres, tirets et underscores"));
    }

    Ok(())
}

pub fn validate_user_id(user_id: i32) -> Result<()> {
    if user_id <= 0 {
        return Err(ChatError::configuration_error("L'ID utilisateur doit être positif"));
    }
    Ok(())
}

pub fn validate_limit(limit: i64) -> Result<i64> {
    if limit <= 0 {
        return Err(ChatError::configuration_error("La limite doit être positive"));
    }
    
    if limit > 1000 {
        return Err(ChatError::configuration_error("La limite ne peut pas dépasser 1000"));
    }
    
    Ok(limit)
} 