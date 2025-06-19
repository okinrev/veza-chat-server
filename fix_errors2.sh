#!/bin/bash

echo "🔧 Correction des erreurs de type restantes..."

# Fonction pour corriger les types String vers &str 
fix_string_to_str() {
    local file="$1"
    echo "Correction des types dans $file..."
    
    # Supprimer .to_string() dans les appels configuration_error
    sed -i 's/ChatError::configuration_error(\([^)]*\)\.to_string())/ChatError::configuration_error(\1)/g' "$file"
    
    # Supprimer .to_string() dans les format! pour configuration_error
    sed -i 's/ChatError::configuration_error(format!(\([^)]*\)))/ChatError::configuration_error(\&format!(\1))/g' "$file"
    
    # Corriger les Database restants
    sed -i 's/\.map_err(ChatError::Database)/\.map_err(|e| ChatError::from_sqlx_error("database_operation", e))/g' "$file"
    
    # Corriger les Result types dans config.rs
    sed -i 's/Result<Self, Self::Err>/std::result::Result<Self, Self::Err>/g' "$file"
    
    # Corriger heartbeat_interval
    sed -i 's/self\.config\.heartbeat_interval/self.config.server.heartbeat_interval.as_secs() as u64/g' "$file"
}

# Appliquer aux fichiers avec erreurs
fix_string_to_str "src/hub/dm.rs"
fix_string_to_str "src/message_handler.rs"
fix_string_to_str "src/moderation.rs"
fix_string_to_str "src/reactions.rs"
fix_string_to_str "src/permissions.rs"
fix_string_to_str "src/security_enhanced.rs"
fix_string_to_str "src/validation.rs"
fix_string_to_str "src/config.rs"
fix_string_to_str "src/hub/common.rs"

echo "✅ Corrections de type appliquées !" 