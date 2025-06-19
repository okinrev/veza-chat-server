#!/bin/bash

echo "🔧 Correction automatique des erreurs ChatError..."

# Fonction pour appliquer les corrections dans un fichier
fix_file() {
    local file="$1"
    echo "Correction de $file..."
    
    # ChatError::Configuration(string) -> ChatError::configuration_error(string)
    sed -i 's/ChatError::Configuration(\([^)]*\))/ChatError::configuration_error(\1)/g' "$file"
    
    # ChatError::Database(e) -> ChatError::from_sqlx_error("operation", e)
    sed -i 's/ChatError::Database(\([^)]*\))/ChatError::from_sqlx_error("database_operation", \1)/g' "$file"
    
    # ChatError::Json(e) -> ChatError::from_json_error(e)
    sed -i 's/ChatError::Json(\([^)]*\))/ChatError::from_json_error(\1)/g' "$file"
    
    # ChatError::RateLimitExceeded -> ChatError::rate_limit_exceeded_simple("action")
    sed -i 's/ChatError::RateLimitExceeded/ChatError::rate_limit_exceeded_simple("rate_limit")/g' "$file"
    
    # ChatError::Unauthorized -> ChatError::unauthorized_simple("action")
    sed -i 's/ChatError::Unauthorized[^(]/ChatError::unauthorized_simple("unauthorized_action")/g' "$file"
    
    # ChatError::MessageTooLong(a, b) -> ChatError::message_too_long(a, b)
    sed -i 's/ChatError::MessageTooLong(\([^,]*\), \([^)]*\))/ChatError::message_too_long(\1, \2)/g' "$file"
    
    # ChatError::InappropriateContent -> ChatError::inappropriate_content_simple("reason")
    sed -i 's/ChatError::InappropriateContent[^(]/ChatError::inappropriate_content_simple("inappropriate_content")/g' "$file"
}

# Appliquer les corrections à tous les fichiers .rs dans src/
find src/ -name "*.rs" -type f | while read -r file; do
    fix_file "$file"
done

echo "✅ Corrections appliquées !"
echo "🚀 Test de compilation..."
cargo check --quiet 2>&1 | head -10 