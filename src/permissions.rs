use crate::error::{ChatError, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Role {
    Admin,
    Moderator,
    User,
    Guest,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Permission {
    // Gestion des salons
    CreateRoom,
    DeleteRoom,
    ModerateRoom,
    JoinRoom,
    LeaveRoom,
    ViewRoomHistory,
    
    // Messages
    SendMessage,
    EditMessage,
    DeleteMessage,
    DeleteAnyMessage,
    
    // Messages directs
    SendDirectMessage,
    ViewDirectMessageHistory,
    
    // Modération
    BanUser,
    MuteUser,
    KickUser,
    ViewLogs,
    
    // Administration
    ManageUsers,
    ViewStats,
    ConfigureServer,
}

impl Role {
    pub fn get_permissions(&self) -> Vec<Permission> {
        match self {
            Role::Admin => vec![
                Permission::CreateRoom,
                Permission::DeleteRoom,
                Permission::ModerateRoom,
                Permission::JoinRoom,
                Permission::LeaveRoom,
                Permission::ViewRoomHistory,
                Permission::SendMessage,
                Permission::EditMessage,
                Permission::DeleteMessage,
                Permission::DeleteAnyMessage,
                Permission::SendDirectMessage,
                Permission::ViewDirectMessageHistory,
                Permission::BanUser,
                Permission::MuteUser,
                Permission::KickUser,
                Permission::ViewLogs,
                Permission::ManageUsers,
                Permission::ViewStats,
                Permission::ConfigureServer,
            ],
            Role::Moderator => vec![
                Permission::CreateRoom,
                Permission::ModerateRoom,
                Permission::JoinRoom,
                Permission::LeaveRoom,
                Permission::ViewRoomHistory,
                Permission::SendMessage,
                Permission::EditMessage,
                Permission::DeleteMessage,
                Permission::DeleteAnyMessage,
                Permission::SendDirectMessage,
                Permission::ViewDirectMessageHistory,
                Permission::MuteUser,
                Permission::KickUser,
                Permission::ViewLogs,
            ],
            Role::User => vec![
                Permission::JoinRoom,
                Permission::LeaveRoom,
                Permission::ViewRoomHistory,
                Permission::SendMessage,
                Permission::EditMessage,
                Permission::DeleteMessage,
                Permission::SendDirectMessage,
                Permission::ViewDirectMessageHistory,
            ],
            Role::Guest => vec![
                Permission::JoinRoom,
                Permission::ViewRoomHistory,
                Permission::SendMessage,
            ],
        }
    }

    pub fn has_permission(&self, permission: &Permission) -> bool {
        self.get_permissions().contains(permission)
    }

    pub fn from_string(role_str: &str) -> Result<Self> {
        match role_str.to_lowercase().as_str() {
            "admin" => Ok(Role::Admin),
            "moderator" | "mod" => Ok(Role::Moderator),
            "user" => Ok(Role::User),
            "guest" => Ok(Role::Guest),
            _ => Err(ChatError::configuration_error(&format!("Rôle invalide: {}", role_str))),
        }
    }
}

pub fn check_permission(user_role: &Role, required_permission: Permission) -> Result<()> {
    if user_role.has_permission(&required_permission) {
        Ok(())
    } else {
        Err(ChatError::unauthorized_simple("unauthorized_action"))
    }
} 