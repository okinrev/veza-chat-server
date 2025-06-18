//file: backend/modules/chat_server/src/main.rs

mod auth;
mod client;
mod messages;
mod hub {
    pub mod common;
    pub mod room;
    pub mod dm;
}

use std::env;
use std::net::SocketAddr;
use std::sync::Arc;
use serde_json::json;
use serde::Serialize;

use dotenvy::dotenv;
use futures_util::{SinkExt, StreamExt};
use http::{Response, StatusCode};
use sqlx::postgres::PgPoolOptions;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;
use tokio_tungstenite::{
    accept_hdr_async,
    tungstenite::{handshake::server::Request, protocol::Message},
};

use crate::auth::{validate_token, Claims};
use crate::client::Client;
use crate::hub::common::ChatHub;
use crate::hub::room::*;
use crate::hub::dm::*;
use crate::messages::WsInbound;

#[derive(Serialize)]
struct OutgoingMessage<'a, T> {
    r#type: &'a str,
    data: T,
}

fn make_json_message<T: Serialize>(typ: &str, payload: T) -> Message {
    let msg = OutgoingMessage { r#type: typ, data: payload };
    let json_str = serde_json::to_string(&msg).unwrap();
    tracing::debug!(message_type = %typ, payload = %json_str, "📤 Envoi message JSON");
    Message::Text(json_str)
}


#[tokio::main]
async fn main() {
    dotenv().ok();

    tracing_subscriber::fmt()
        .with_env_filter("chat_server=debug,sqlx=info")
        .with_target(true)
        .with_line_number(true)
        .with_file(true)
        .init();

    tracing::info!("🟢 Démarrage du serveur WebSocket...");

    let addr = env::var("WS_BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:9001".to_string());
    let db_url = env::var("DATABASE_URL").expect("DATABASE_URL manquant");

    tracing::info!(bind_addr = %addr, db_url = %db_url, "🔧 Configuration serveur");

    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&db_url)
        .await
        .expect("❌ Connexion DB échouée");

    tracing::info!("✅ Connexion à la base de données établie");

    let hub = ChatHub::new(pool);
    tracing::info!("✅ Hub de chat initialisé");

    tracing::info!("🔌 Serveur WebSocket lancé sur ws://{}", addr);

    let listener = TcpListener::bind(&addr).await.expect("❌ Bind échoué");
    tracing::info!("✅ Listener TCP démarré avec succès");

    let mut connection_counter = 0u64;

    while let Ok((stream, addr)) = listener.accept().await {
        connection_counter += 1;
        let hub = hub.clone();
        tracing::info!(connection_id = %connection_counter, client_addr = %addr, "🔗 Nouvelle connexion TCP acceptée");
        
        tokio::spawn(async move {
            if let Err(e) = handle_connection(stream, addr, hub, connection_counter).await {
                tracing::error!(connection_id = %connection_counter, error = %e, "❌ Erreur de connexion WS");
            } else {
                tracing::info!(connection_id = %connection_counter, "✅ Connexion WS fermée proprement");
            }
        });
    }
}

async fn handle_connection(
    stream: TcpStream,
    addr: SocketAddr,
    hub: Arc<ChatHub>,
    connection_id: u64,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    tracing::info!(connection_id = %connection_id, addr = %addr, "🔌 Connexion TCP entrante");

    let mut extracted_claims: Option<Claims> = None;

    let callback = |req: &Request, response: Response<()>| {
        tracing::debug!(connection_id = %connection_id, uri = %req.uri(), method = %req.method(), "🔍 Handshake WebSocket reçu");
        
        // Log des headers reçus
        for (name, value) in req.headers() {
            tracing::debug!(connection_id = %connection_id, header_name = %name, header_value = ?value, "📋 Header reçu");
        }

        if let Some(header) = req.headers().get("Authorization") {
            tracing::debug!(connection_id = %connection_id, "🔐 Tentative d'auth via header Authorization");
            if let Ok(auth) = header.to_str() {
                let token = auth.strip_prefix("Bearer ").unwrap_or(auth);
                tracing::debug!(connection_id = %connection_id, token_length = %token.len(), "🔑 Token extrait du header");
                
                match validate_token(token) {
                    Ok(token_data) => {
                        tracing::info!(connection_id = %connection_id, user_id = token_data.claims.user_id, username = %token_data.claims.username, "🔐 Authentification réussie via header");
                        extracted_claims = Some(token_data.claims.clone());
                        Ok(response)
                    }
                    Err(e) => {
                        tracing::warn!(connection_id = %connection_id, error = %e, "🔐 JWT invalide dans header");
                        Err(Response::builder()
                            .status(StatusCode::UNAUTHORIZED)
                            .body(Some("JWT invalide".to_string()))
                            .unwrap())
                    }
                }
            } else {
                tracing::warn!(connection_id = %connection_id, "🔐 En-tête Authorization invalide");
                Err(Response::builder()
                    .status(StatusCode::BAD_REQUEST)
                    .body(Some("Authorization mal formé".to_string()))
                    .unwrap())
            }
        } else {
            tracing::debug!(connection_id = %connection_id, "🔍 Pas de header Authorization, tentative via query param");
            
            // 2. Check query param ?token=...
            if let Some(query) = req.uri().query() {
                tracing::debug!(connection_id = %connection_id, query = %query, "🔍 Query string trouvée");
                
                if let Some(token) = query.strip_prefix("token=") {
                    tracing::debug!(connection_id = %connection_id, token_length = %token.len(), "🔑 Token extrait de la query");
                    
                    match validate_token(token) {
                        Ok(token_data) => {
                            extracted_claims = Some(token_data.claims.clone());
                            tracing::info!(connection_id = %connection_id, user_id = token_data.claims.user_id, username = %token_data.claims.username, "🔐 Auth via query OK");
                            return Ok(response);
                        }
                        Err(e) => {
                            tracing::warn!(connection_id = %connection_id, error = %e, "❌ JWT (query) invalide");
                        }
                    }
                } else {
                    tracing::debug!(connection_id = %connection_id, "🔍 Query ne commence pas par 'token='");
                }
            } else {
                tracing::debug!(connection_id = %connection_id, "🔍 Pas de query string dans l'URI");
            }
    
            tracing::warn!(connection_id = %connection_id, "🔐 Auth manquante ou invalide (query + header)");
            Err(Response::builder()
                .status(StatusCode::UNAUTHORIZED)
                .body(Some("Authorization manquante".to_string()))
                .unwrap())
        }
    };

    let ws_stream = accept_hdr_async(stream, callback).await?;
    tracing::info!(connection_id = %connection_id, "✅ Handshake WebSocket réussi");

    let claims = match extracted_claims {
        Some(c) => {
            tracing::debug!(connection_id = %connection_id, user_id = c.user_id, username = %c.username, role = %c.role, "👤 Claims extraites");
            c
        },
        None => {
            tracing::error!(connection_id = %connection_id, "❌ JWT absent après handshake");
            return Err("JWT absent après handshake".into())
        },
    };

    tracing::info!(connection_id = %connection_id, user_id = claims.user_id, username = %claims.username, "✅ Connexion WS autorisée");

    let user_id = claims.user_id;
    let username = claims.username;
    let (ws_write, mut ws_read) = ws_stream.split();

    let (tx, mut rx) = mpsc::unbounded_channel::<Message>();
    let client = Client {
        user_id,
        username: username.clone(),
        sender: tx.clone(),
    };
    
    tracing::debug!(connection_id = %connection_id, user_id = %user_id, "📝 Enregistrement du client dans le hub");
    hub.register(user_id, client).await;

    let write_task = tokio::spawn(async move {
        let mut ws_write = ws_write;
        let mut message_count = 0u64;
        
        while let Some(msg) = rx.recv().await {
            message_count += 1;
            tracing::debug!(connection_id = %connection_id, user_id = %user_id, message_count = %message_count, message_type = ?msg, "📤 Envoi message WebSocket");
            
            if let Err(e) = ws_write.send(msg).await {
                tracing::error!(connection_id = %connection_id, user_id = %user_id, error = %e, "❌ Erreur envoi message WebSocket");
                break;
            } else {
                tracing::debug!(connection_id = %connection_id, user_id = %user_id, message_count = %message_count, "✅ Message WebSocket envoyé");
            }
        }
        tracing::info!(connection_id = %connection_id, user_id = %user_id, total_messages = %message_count, "🔚 Fin de la tâche d'écriture WebSocket");
    });

    let mut received_message_count = 0u64;

    while let Some(result) = ws_read.next().await {
        match result {
            Ok(msg) if msg.is_text() => {
                received_message_count += 1;
                let msg_text = msg.to_text().unwrap();
                tracing::info!(connection_id = %connection_id, user_id = user_id, message_count = %received_message_count, message = %msg_text, "📨 Message reçu du client");
                
                if let Ok(parsed) = serde_json::from_str::<WsInbound>(msg_text) {
                    tracing::info!(connection_id = %connection_id, user_id = user_id, message_type = ?parsed, "🔍 Message parsé avec succès");
                    
                    match parsed {
                        WsInbound::Join { room } => {
                            tracing::info!(connection_id = %connection_id, user_id = user_id, room = %room, "🚪 Tentative de rejoindre salon");
                            
                            if room_exists(&hub, &room).await {
                                tracing::debug!(connection_id = %connection_id, user_id = user_id, room = %room, "✅ Salon existe, procédure de jointure");
                                join_room(&hub, &room, user_id).await;
                                tracing::info!(connection_id = %connection_id, user_id = user_id, room = %room, "✅ Salon rejoint avec succès");
                                
                                let ack_msg = make_json_message("join_ack", json!({
                                    "room": room,
                                    "status": "ok"
                                }));
                                
                                if let Err(e) = tx.send(ack_msg) {
                                    tracing::error!(connection_id = %connection_id, user_id = user_id, error = %e, "❌ Erreur envoi ACK join_room");
                                } else {
                                    tracing::debug!(connection_id = %connection_id, user_id = user_id, room = %room, "✅ ACK join_room envoyé");
                                }
                            } else {
                                tracing::warn!(connection_id = %connection_id, user_id = user_id, room = %room, "❌ Salon inexistant");
                                let error_msg = make_json_message("error", json!({"message": "Room inexistante."}));
                                if let Err(e) = tx.send(error_msg) {
                                    tracing::error!(connection_id = %connection_id, user_id = user_id, error = %e, "❌ Erreur envoi message d'erreur");
                                }
                            }
                        }
                        WsInbound::Message { room, content } => {
                            tracing::info!(connection_id = %connection_id, user_id = user_id, room = %room, content = %content, content_length = %content.len(), "💬 Message salon reçu"); 
                            
                            if room_exists(&hub, &room).await {
                                tracing::debug!(connection_id = %connection_id, user_id = user_id, room = %room, "✅ Salon existe, diffusion du message");
                                broadcast_to_room(&hub, user_id, &username, &room, &content).await;
                                tracing::info!(connection_id = %connection_id, user_id = user_id, room = %room, "✅ Message salon diffusé");
                            } else {
                                tracing::warn!(connection_id = %connection_id, user_id = user_id, room = %room, "❌ Tentative d'envoi dans salon inexistant");
                                let error_msg = make_json_message("error", json!({"message": "Room inexistante."}));
                                if let Err(e) = tx.send(error_msg) {
                                    tracing::error!(connection_id = %connection_id, user_id = user_id, error = %e, "❌ Erreur envoi message d'erreur");
                                }
                            }
                        }
                        WsInbound::DirectMessage { to_user_id, content } => {
                            tracing::info!(connection_id = %connection_id, user_id = user_id, to_user_id = %to_user_id, content = %content, content_length = %content.len(), "💌 Message direct reçu");
                            
                            if user_exists(&hub, to_user_id).await {
                                tracing::debug!(connection_id = %connection_id, user_id = user_id, to_user_id = %to_user_id, "✅ Utilisateur destinataire existe");
                                send_dm(&hub, user_id, to_user_id, &username, &content).await;
                                tracing::info!(connection_id = %connection_id, user_id = user_id, to_user_id = %to_user_id, "✅ Message direct envoyé");
                            } else {
                                tracing::warn!(connection_id = %connection_id, user_id = user_id, to_user_id = %to_user_id, "❌ Utilisateur destinataire inexistant");
                                let error_msg = make_json_message("error", json!({"message": "Utilisateur inexistant."}));
                                if let Err(e) = tx.send(error_msg) {
                                    tracing::error!(connection_id = %connection_id, user_id = user_id, error = %e, "❌ Erreur envoi message d'erreur");
                                }
                            }
                        }
                        WsInbound::RoomHistory { room, limit } => {
                            tracing::info!(connection_id = %connection_id, user_id = user_id, room = %room, limit = %limit, "📜 Demande d'historique salon");
                            
                            if room_exists(&hub, &room).await {
                                let messages = fetch_room_history(&hub, &room, limit).await;
                                tracing::info!(connection_id = %connection_id, user_id = user_id, room = %room, message_count = %messages.len(), "📜 Historique salon récupéré");
                                
                                let history_msg = make_json_message("room_history", json!({
                                    "room": room,
                                    "messages": messages
                                }));
                                
                                if let Err(e) = tx.send(history_msg) {
                                    tracing::error!(connection_id = %connection_id, user_id = user_id, error = %e, "❌ Erreur envoi historique salon");
                                } else {
                                    tracing::debug!(connection_id = %connection_id, user_id = user_id, room = %room, "✅ Historique salon envoyé");
                                }                                
                            } else {
                                tracing::warn!(connection_id = %connection_id, user_id = user_id, room = %room, "❌ Demande d'historique pour salon inexistant");
                                let error_msg = make_json_message("error", json!({"message": "Room inexistante."}));
                                if let Err(e) = tx.send(error_msg) {
                                    tracing::error!(connection_id = %connection_id, user_id = user_id, error = %e, "❌ Erreur envoi message d'erreur");
                                }
                            }
                        }
                        WsInbound::DmHistory { with, limit } => {
                            tracing::info!(connection_id = %connection_id, user_id = user_id, with_user = %with, limit = %limit, "📜 Demande d'historique DM");
                            
                            if user_exists(&hub, with).await {
                                let messages = fetch_dm_history(&hub, user_id, with, limit).await;
                                tracing::info!(connection_id = %connection_id, user_id = user_id, with_user = %with, message_count = %messages.len(), "📜 Historique DM récupéré");
                                
                                let history_msg = make_json_message("dm_history", json!({
                                    "with": with,
                                    "data": messages
                                }));
                                
                                if let Err(e) = tx.send(history_msg) {
                                    tracing::error!(connection_id = %connection_id, user_id = user_id, error = %e, "❌ Erreur envoi historique DM");
                                } else {
                                    tracing::debug!(connection_id = %connection_id, user_id = user_id, with_user = %with, "✅ Historique DM envoyé");
                                }
                            } else {
                                tracing::warn!(connection_id = %connection_id, user_id = user_id, with_user = %with, "❌ Demande d'historique DM avec utilisateur inexistant");
                                let error_msg = make_json_message("error", json!({"message": "Utilisateur inexistant."}));
                                if let Err(e) = tx.send(error_msg) {
                                    tracing::error!(connection_id = %connection_id, user_id = user_id, error = %e, "❌ Erreur envoi message d'erreur");
                                }
                            }
                        }
                    }
                } else {
                    tracing::warn!(connection_id = %connection_id, user_id = user_id, raw_message = %msg_text, "❌ Impossible de parser le message JSON");
                    let error_msg = make_json_message("error", json!({"message": "Format JSON invalide."}));
                    if let Err(e) = tx.send(error_msg) {
                        tracing::error!(connection_id = %connection_id, user_id = user_id, error = %e, "❌ Erreur envoi message d'erreur JSON");
                            }
                        }
                    }
            Ok(msg) if msg.is_close() => {
                tracing::info!(connection_id = %connection_id, user_id = user_id, close_frame = ?msg, "👋 Message de fermeture WebSocket reçu");
                break;
            }
            Ok(msg) if msg.is_ping() => {
                tracing::debug!(connection_id = %connection_id, user_id = user_id, "🏓 Ping reçu");
                // Le pong est envoyé automatiquement par tokio-tungstenite
            }
            Ok(msg) if msg.is_pong() => {
                tracing::debug!(connection_id = %connection_id, user_id = user_id, "🏓 Pong reçu");
            }
            Ok(msg) => {
                tracing::debug!(connection_id = %connection_id, user_id = user_id, message_type = ?msg, "🔍 Message WebSocket non-text reçu");
            }
            Err(e) => {
                tracing::error!(connection_id = %connection_id, user_id = user_id, error = %e, "❌ Erreur lecture WebSocket");
                break;
            }
        }
    }

    tracing::info!(connection_id = %connection_id, user_id = user_id, total_received = %received_message_count, "🔚 Fin de la boucle de lecture WebSocket");

    // Nettoyage
    hub.unregister(user_id).await;
    write_task.abort();
    
    tracing::info!(connection_id = %connection_id, user_id = user_id, "🚪 Déconnexion de l'utilisateur");

    Ok(())
}
