//file: backend/modules/chat_server/src/auth.rs

use jsonwebtoken::{decode, DecodingKey, Validation, Algorithm, TokenData, errors::Error};
use serde::{Deserialize, Serialize};
use std::env;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    pub user_id: i32,
    pub username: String,
    pub role: String,
    pub exp: usize,
    pub iat: usize,
}

pub fn validate_token(token: &str) -> Result<TokenData<Claims>, Error> {
    tracing::debug!(token_length = %token.len(), token_preview = %&token[..std::cmp::min(20, token.len())], "🔧 Début validation token");
    
    let secret = match env::var("JWT_SECRET") {
        Ok(s) => {
            tracing::debug!(secret_length = %s.len(), "✅ JWT_SECRET trouvé");
            s
        }
        Err(e) => {
            tracing::error!(error = %e, "❌ JWT_SECRET manquant dans les variables d'environnement");
            return Err(Error::from(jsonwebtoken::errors::ErrorKind::InvalidToken));
        }
    };
    
    let validation = Validation::new(Algorithm::HS256);
    tracing::debug!(algorithm = ?validation.algorithms, "🔧 Configuration de validation JWT");
    
    match decode::<Claims>(token, &DecodingKey::from_secret(secret.as_bytes()), &validation) {
        Ok(token_data) => {
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
            Err(e)
        }
    }
}
