//file: backend/modules/chat_server/src/auth.rs

use jsonwebtoken::{decode, DecodingKey, Validation, Algorithm, TokenData};
use serde::{Deserialize, Serialize};
use crate::error::{ChatError, Result};
use crate::config::ServerConfig;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    pub user_id: i32,
    pub username: String,
    pub role: String,
    pub exp: usize,
    pub iat: usize,
}

pub fn validate_token(token: &str, config: &ServerConfig) -> Result<TokenData<Claims>> {
    tracing::debug!(token_length = %token.len(), token_preview = %&token[..std::cmp::min(20, token.len())], "🔧 Début validation token");
    
    if token.is_empty() {
        tracing::warn!("🔐 Token vide fourni");
        return Err(ChatError::unauthorized("empty token"));
    }

    if token.len() > 2048 {
        tracing::warn!(token_length = %token.len(), "🔐 Token trop long");
        return Err(ChatError::unauthorized("token too long"));
    }
    
    tracing::debug!(secret_length = %config.security.jwt_secret.len(), "✅ JWT_SECRET configuré");
    
    let validation = Validation::new(Algorithm::HS256);
    tracing::debug!(algorithm = ?validation.algorithms, "🔧 Configuration de validation JWT");
    
    match decode::<Claims>(token, &DecodingKey::from_secret(config.security.jwt_secret.as_bytes()), &validation) {
        Ok(token_data) => {
            // Vérification de l'expiration
            let now = chrono::Utc::now().timestamp() as usize;
            if token_data.claims.exp < now {
                tracing::warn!(exp = %token_data.claims.exp, now = %now, "🔐 Token expiré");
                return Err(ChatError::unauthorized("token expired"));
            }

            tracing::debug!(
                user_id = %token_data.claims.user_id, 
                username = %token_data.claims.username,
                role = %token_data.claims.role,
                exp = %token_data.claims.exp,
                iat = %token_data.claims.iat,
                "✅ Token JWT validé avec succès"
            );
            Ok(token_data)
        }
        Err(e) => {
            tracing::warn!(error = %e, token_preview = %&token[..std::cmp::min(20, token.len())], "❌ Échec validation token JWT");
            Err(ChatError::unauthorized("invalid jwt token"))
        }
    }
}
