# 🐹 Intégration Go - Guide Complet

**Version :** 0.2.0  
**Dernière mise à jour :** $(date +"%Y-%m-%d")

## 📋 Vue d'Ensemble

Ce guide vous accompagne pour intégrer le serveur de chat Veza dans vos applications Go. Il couvre tous les aspects : WebSocket, REST API, authentification, gestion d'erreurs, et patterns avancés.

## 🛠️ Installation et Configuration

### **Dépendances Requises**

```go
// go.mod
module your-app

go 1.21

require (
    github.com/gorilla/websocket v1.5.0
    github.com/golang-jwt/jwt/v5 v5.0.0
    github.com/go-resty/resty/v2 v2.10.0
    github.com/redis/go-redis/v9 v9.3.0
    github.com/sirupsen/logrus v1.9.3
    golang.org/x/time v0.5.0
)
```

### **Configuration Initiale**

```go
package chatclient

import (
    "time"
    "github.com/gorilla/websocket"
    "github.com/go-resty/resty/v2"
)

type Config struct {
    // Serveur
    ServerURL     string
    WSEndpoint    string
    APIEndpoint   string
    
    // Authentification
    APIKey        string
    JWTSecret     string
    TokenDuration time.Duration
    
    // Connexion
    ConnectTimeout time.Duration
    ReadTimeout    time.Duration
    WriteTimeout   time.Duration
    
    // Retry et Reconnexion
    MaxRetries     int
    RetryDelay     time.Duration
    
    // Rate Limiting
    RateLimit      int // messages par minute
    
    // Logging
    LogLevel       string
    EnableMetrics  bool
}

func DefaultConfig() *Config {
    return &Config{
        ServerURL:      "http://localhost:8080",
        WSEndpoint:     "ws://localhost:8080/ws",
        APIEndpoint:    "http://localhost:8080/api/v1",
        TokenDuration:  15 * time.Minute,
        ConnectTimeout: 30 * time.Second,
        ReadTimeout:    60 * time.Second,
        WriteTimeout:   30 * time.Second,
        MaxRetries:     3,
        RetryDelay:     5 * time.Second,
        RateLimit:      60,
        LogLevel:       "info",
        EnableMetrics:  true,
    }
}
```

## 🔐 Authentification JWT

### **Client d'Authentification**

```go
package auth

import (
    "context"
    "encoding/json"
    "fmt"
    "time"
    
    "github.com/golang-jwt/jwt/v5"
    "github.com/go-resty/resty/v2"
)

type AuthClient struct {
    config     *Config
    httpClient *resty.Client
    token      string
    refreshToken string
    expiresAt    time.Time
}

type LoginRequest struct {
    Username string `json:"username"`
    Password string `json:"password"`
}

type LoginResponse struct {
    AccessToken  string    `json:"access_token"`
    RefreshToken string    `json:"refresh_token"`
    ExpiresIn    int       `json:"expires_in"`
    User         UserInfo  `json:"user"`
}

type UserInfo struct {
    ID       int    `json:"id"`
    Username string `json:"username"`
    Role     string `json:"role"`
    Email    string `json:"email"`
}

func NewAuthClient(config *Config) *AuthClient {
    return &AuthClient{
        config: config,
        httpClient: resty.New().
            SetTimeout(config.ConnectTimeout).
            SetBaseURL(config.APIEndpoint),
    }
}

func (a *AuthClient) Login(ctx context.Context, username, password string) error {
    loginReq := LoginRequest{
        Username: username,
        Password: password,
    }
    
    var loginResp LoginResponse
    
    resp, err := a.httpClient.R().
        SetContext(ctx).
        SetBody(loginReq).
        SetResult(&loginResp).
        Post("/auth/login")
    
    if err != nil {
        return fmt.Errorf("login request failed: %w", err)
    }
    
    if resp.StatusCode() != 200 {
        return fmt.Errorf("login failed: status %d", resp.StatusCode())
    }
    
    a.token = loginResp.AccessToken
    a.refreshToken = loginResp.RefreshToken
    a.expiresAt = time.Now().Add(time.Duration(loginResp.ExpiresIn) * time.Second)
    
    return nil
}

func (a *AuthClient) GetValidToken(ctx context.Context) (string, error) {
    if time.Now().Before(a.expiresAt.Add(-30 * time.Second)) {
        return a.token, nil
    }
    
    return a.refreshAccessToken(ctx)
}

func (a *AuthClient) refreshAccessToken(ctx context.Context) (string, error) {
    type RefreshRequest struct {
        RefreshToken string `json:"refresh_token"`
    }
    
    var loginResp LoginResponse
    
    resp, err := a.httpClient.R().
        SetContext(ctx).
        SetBody(RefreshRequest{RefreshToken: a.refreshToken}).
        SetResult(&loginResp).
        Post("/auth/refresh")
    
    if err != nil {
        return "", fmt.Errorf("token refresh failed: %w", err)
    }
    
    if resp.StatusCode() != 200 {
        return "", fmt.Errorf("token refresh failed: status %d", resp.StatusCode())
    }
    
    a.token = loginResp.AccessToken
    a.expiresAt = time.Now().Add(time.Duration(loginResp.ExpiresIn) * time.Second)
    
    return a.token, nil
}

func (a *AuthClient) ValidateToken(tokenString string) (*jwt.Token, error) {
    token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
        if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
            return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
        }
        return []byte(a.config.JWTSecret), nil
    })
    
    return token, err
}
```

## 🌐 Client WebSocket Avancé

### **Structure du Client WebSocket**

```go
package websocket

import (
    "context"
    "encoding/json"
    "fmt"
    "sync"
    "time"
    
    "github.com/gorilla/websocket"
    "github.com/sirupsen/logrus"
)

type WSClient struct {
    config       *Config
    authClient   *AuthClient
    conn         *websocket.Conn
    
    // Channels
    incomingMsg  chan []byte
    outgoingMsg  chan []byte
    done         chan struct{}
    reconnect    chan struct{}
    
    // État
    isConnected  bool
    mu           sync.RWMutex
    
    // Callbacks
    onMessage    func(MessageType, []byte)
    onConnect    func()
    onDisconnect func(error)
    onError      func(error)
    
    // Métriques
    metrics      *WSMetrics
    logger       *logrus.Logger
}

type WSMetrics struct {
    ConnectionAttempts   int64
    MessagesReceived     int64
    MessagesSent         int64
    ReconnectionCount    int64
    LastConnectedAt      time.Time
    TotalDowntime        time.Duration
}

type MessageType string

const (
    // Messages de base
    AuthenticateMsg    MessageType = "authenticate"
    JoinRoomMsg        MessageType = "join_room"
    LeaveRoomMsg       MessageType = "leave_room"
    SendMessageMsg     MessageType = "send_message"
    
    // Messages directs
    CreateDMMsg        MessageType = "create_dm"
    SendDMMsg          MessageType = "send_dm"
    BlockDMMsg         MessageType = "block_dm"
    
    // Réactions et interactions
    AddReactionMsg     MessageType = "add_reaction"
    RemoveReactionMsg  MessageType = "remove_reaction"
    PinMessageMsg      MessageType = "pin_message"
    
    // Événements serveur
    MessageReceivedMsg MessageType = "room_message"
    DMReceivedMsg      MessageType = "dm_message"
    UserPresenceMsg    MessageType = "user_presence"
    ErrorMsg           MessageType = "error"
)

type WSMessage struct {
    Type MessageType    `json:"type"`
    Data json.RawMessage `json:"data"`
}

func NewWSClient(config *Config, authClient *AuthClient) *WSClient {
    return &WSClient{
        config:      config,
        authClient:  authClient,
        incomingMsg: make(chan []byte, 100),
        outgoingMsg: make(chan []byte, 100),
        done:        make(chan struct{}),
        reconnect:   make(chan struct{}, 1),
        metrics:     &WSMetrics{},
        logger:      logrus.New(),
    }
}

func (ws *WSClient) Connect(ctx context.Context) error {
    ws.mu.Lock()
    defer ws.mu.Unlock()
    
    ws.metrics.ConnectionAttempts++
    
    dialer := websocket.Dialer{
        HandshakeTimeout: ws.config.ConnectTimeout,
    }
    
    conn, _, err := dialer.DialContext(ctx, ws.config.WSEndpoint, nil)
    if err != nil {
        return fmt.Errorf("websocket connection failed: %w", err)
    }
    
    ws.conn = conn
    ws.isConnected = true
    ws.metrics.LastConnectedAt = time.Now()
    
    // Authentification immédiate
    token, err := ws.authClient.GetValidToken(ctx)
    if err != nil {
        return fmt.Errorf("failed to get auth token: %w", err)
    }
    
    authMsg := WSMessage{
        Type: AuthenticateMsg,
        Data: json.RawMessage(fmt.Sprintf(`{"token": "%s"}`, token)),
    }
    
    if err := ws.sendMessage(authMsg); err != nil {
        return fmt.Errorf("authentication failed: %w", err)
    }
    
    // Démarrer les goroutines
    go ws.readLoop()
    go ws.writeLoop()
    go ws.pingLoop()
    
    if ws.onConnect != nil {
        ws.onConnect()
    }
    
    ws.logger.Info("WebSocket connected successfully")
    return nil
}

func (ws *WSClient) readLoop() {
    defer func() {
        ws.mu.Lock()
        ws.isConnected = false
        ws.mu.Unlock()
        
        if ws.onDisconnect != nil {
            ws.onDisconnect(nil)
        }
        
        select {
        case ws.reconnect <- struct{}{}:
        default:
        }
    }()
    
    for {
        select {
        case <-ws.done:
            return
        default:
            if ws.conn == nil {
                return
            }
            
            ws.conn.SetReadDeadline(time.Now().Add(ws.config.ReadTimeout))
            _, message, err := ws.conn.ReadMessage()
            
            if err != nil {
                if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
                    ws.logger.Errorf("WebSocket read error: %v", err)
                    if ws.onError != nil {
                        ws.onError(err)
                    }
                }
                return
            }
            
            ws.metrics.MessagesReceived++
            
            select {
            case ws.incomingMsg <- message:
            case <-ws.done:
                return
            }
        }
    }
}

func (ws *WSClient) writeLoop() {
    ticker := time.NewTicker(54 * time.Second) // Ping interval
    defer ticker.Stop()
    
    for {
        select {
        case <-ws.done:
            return
        case message := <-ws.outgoingMsg:
            if ws.conn == nil {
                continue
            }
            
            ws.conn.SetWriteDeadline(time.Now().Add(ws.config.WriteTimeout))
            if err := ws.conn.WriteMessage(websocket.TextMessage, message); err != nil {
                ws.logger.Errorf("WebSocket write error: %v", err)
                if ws.onError != nil {
                    ws.onError(err)
                }
                return
            }
            
            ws.metrics.MessagesSent++
        }
    }
}

func (ws *WSClient) pingLoop() {
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()
    
    for {
        select {
        case <-ws.done:
            return
        case <-ticker.C:
            if ws.conn == nil {
                continue
            }
            
            ws.conn.SetWriteDeadline(time.Now().Add(ws.config.WriteTimeout))
            if err := ws.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
                ws.logger.Errorf("Failed to send ping: %v", err)
                return
            }
        }
    }
}

func (ws *WSClient) StartMessageProcessing() {
    go func() {
        for {
            select {
            case <-ws.done:
                return
            case messageBytes := <-ws.incomingMsg:
                ws.processIncomingMessage(messageBytes)
            }
        }
    }()
}

func (ws *WSClient) processIncomingMessage(messageBytes []byte) {
    var msg WSMessage
    if err := json.Unmarshal(messageBytes, &msg); err != nil {
        ws.logger.Errorf("Failed to unmarshal message: %v", err)
        return
    }
    
    if ws.onMessage != nil {
        ws.onMessage(msg.Type, msg.Data)
    }
}

// Méthodes d'envoi spécialisées
func (ws *WSClient) JoinRoom(roomID int) error {
    msg := WSMessage{
        Type: JoinRoomMsg,
        Data: json.RawMessage(fmt.Sprintf(`{"room_id": %d}`, roomID)),
    }
    return ws.sendMessage(msg)
}

func (ws *WSClient) SendRoomMessage(roomID int, content string, parentID *int) error {
    data := map[string]interface{}{
        "room_id": roomID,
        "content": content,
    }
    
    if parentID != nil {
        data["parent_id"] = *parentID
    }
    
    dataBytes, _ := json.Marshal(data)
    
    msg := WSMessage{
        Type: SendMessageMsg,
        Data: dataBytes,
    }
    
    return ws.sendMessage(msg)
}

func (ws *WSClient) CreateDM(user1ID, user2ID int) error {
    msg := WSMessage{
        Type: CreateDMMsg,
        Data: json.RawMessage(fmt.Sprintf(`{"user1_id": %d, "user2_id": %d}`, user1ID, user2ID)),
    }
    return ws.sendMessage(msg)
}

func (ws *WSClient) SendDM(conversationID int, content string, parentID *int) error {
    data := map[string]interface{}{
        "conversation_id": conversationID,
        "content":         content,
    }
    
    if parentID != nil {
        data["parent_id"] = *parentID
    }
    
    dataBytes, _ := json.Marshal(data)
    
    msg := WSMessage{
        Type: SendDMMsg,
        Data: dataBytes,
    }
    
    return ws.sendMessage(msg)
}

func (ws *WSClient) AddReaction(messageID int, emoji string) error {
    msg := WSMessage{
        Type: AddReactionMsg,
        Data: json.RawMessage(fmt.Sprintf(`{"message_id": %d, "emoji": "%s"}`, messageID, emoji)),
    }
    return ws.sendMessage(msg)
}

func (ws *WSClient) sendMessage(msg WSMessage) error {
    ws.mu.RLock()
    connected := ws.isConnected
    ws.mu.RUnlock()
    
    if !connected {
        return fmt.Errorf("not connected to WebSocket")
    }
    
    messageBytes, err := json.Marshal(msg)
    if err != nil {
        return fmt.Errorf("failed to marshal message: %w", err)
    }
    
    select {
    case ws.outgoingMsg <- messageBytes:
        return nil
    case <-time.After(5 * time.Second):
        return fmt.Errorf("send timeout")
    }
}

// Callbacks
func (ws *WSClient) OnMessage(callback func(MessageType, []byte)) {
    ws.onMessage = callback
}

func (ws *WSClient) OnConnect(callback func()) {
    ws.onConnect = callback
}

func (ws *WSClient) OnDisconnect(callback func(error)) {
    ws.onDisconnect = callback
}

func (ws *WSClient) OnError(callback func(error)) {
    ws.onError = callback
}

func (ws *WSClient) Close() error {
    close(ws.done)
    
    ws.mu.Lock()
    defer ws.mu.Unlock()
    
    if ws.conn != nil {
        return ws.conn.Close()
    }
    
    return nil
}

func (ws *WSClient) GetMetrics() WSMetrics {
    ws.mu.RLock()
    defer ws.mu.RUnlock()
    return *ws.metrics
}
```

## 🔄 Reconnexion Automatique

### **Gestionnaire de Reconnexion**

```go
package websocket

import (
    "context"
    "time"
)

type ReconnectionManager struct {
    client       *WSClient
    config       *Config
    isReconnecting bool
    maxRetries     int
    currentRetry   int
    backoffDelay   time.Duration
}

func NewReconnectionManager(client *WSClient, config *Config) *ReconnectionManager {
    return &ReconnectionManager{
        client:       client,
        config:       config,
        maxRetries:   config.MaxRetries,
        backoffDelay: config.RetryDelay,
    }
}

func (r *ReconnectionManager) Start(ctx context.Context) {
    go func() {
        for {
            select {
            case <-ctx.Done():
                return
            case <-r.client.reconnect:
                r.handleReconnection(ctx)
            }
        }
    }()
}

func (r *ReconnectionManager) handleReconnection(ctx context.Context) {
    if r.isReconnecting {
        return
    }
    
    r.isReconnecting = true
    defer func() { r.isReconnecting = false }()
    
    r.client.logger.Info("Starting reconnection process...")
    
    for r.currentRetry < r.maxRetries {
        select {
        case <-ctx.Done():
            return
        case <-time.After(r.calculateBackoff()):
            r.currentRetry++
            
            r.client.logger.Infof("Reconnection attempt %d/%d", r.currentRetry, r.maxRetries)
            
            if err := r.client.Connect(ctx); err != nil {
                r.client.logger.Errorf("Reconnection attempt %d failed: %v", r.currentRetry, err)
                continue
            }
            
            r.client.logger.Info("Successfully reconnected!")
            r.client.metrics.ReconnectionCount++
            r.currentRetry = 0
            return
        }
    }
    
    r.client.logger.Error("Failed to reconnect after maximum retries")
}

func (r *ReconnectionManager) calculateBackoff() time.Duration {
    // Exponential backoff with jitter
    base := float64(r.backoffDelay)
    backoff := base * float64(1<<uint(r.currentRetry))
    
    if backoff > float64(5*time.Minute) {
        backoff = float64(5 * time.Minute)
    }
    
    return time.Duration(backoff)
}
```

## 📡 API REST Client

### **Client HTTP Avancé**

```go
package restapi

import (
    "context"
    "encoding/json"
    "fmt"
    "io"
    "mime/multipart"
    "time"
    
    "github.com/go-resty/resty/v2"
)

type RESTClient struct {
    config     *Config
    authClient *AuthClient
    httpClient *resty.Client
}

type APIResponse struct {
    Success bool            `json:"success"`
    Data    json.RawMessage `json:"data"`
    Error   *APIError       `json:"error,omitempty"`
}

type APIError struct {
    Code    string `json:"code"`
    Message string `json:"message"`
    Details any    `json:"details,omitempty"`
}

type Room struct {
    ID          int       `json:"id"`
    UUID        string    `json:"uuid"`
    Name        string    `json:"name"`
    Description string    `json:"description"`
    IsPublic    bool      `json:"is_public"`
    OwnerID     int       `json:"owner_id"`
    CreatedAt   time.Time `json:"created_at"`
    UpdatedAt   time.Time `json:"updated_at"`
}

type Message struct {
    ID            int                    `json:"id"`
    UUID          string                 `json:"uuid"`
    AuthorID      int                    `json:"author_id"`
    Username      string                 `json:"username"`
    Content       string                 `json:"content"`
    ParentID      *int                   `json:"parent_id"`
    ThreadCount   int                    `json:"thread_count"`
    IsPinned      bool                   `json:"is_pinned"`
    IsEdited      bool                   `json:"is_edited"`
    Reactions     map[string][]UserInfo  `json:"reactions"`
    Metadata      map[string]interface{} `json:"metadata"`
    CreatedAt     time.Time              `json:"created_at"`
    UpdatedAt     time.Time              `json:"updated_at"`
}

func NewRESTClient(config *Config, authClient *AuthClient) *RESTClient {
    httpClient := resty.New().
        SetTimeout(config.ConnectTimeout).
        SetBaseURL(config.APIEndpoint).
        OnBeforeRequest(func(c *resty.Client, req *resty.Request) error {
            token, err := authClient.GetValidToken(context.Background())
            if err != nil {
                return err
            }
            req.SetAuthToken(token)
            return nil
        })
    
    return &RESTClient{
        config:     config,
        authClient: authClient,
        httpClient: httpClient,
    }
}

// Gestion des salons
func (r *RESTClient) CreateRoom(ctx context.Context, name, description string, isPublic bool) (*Room, error) {
    req := map[string]interface{}{
        "name":        name,
        "description": description,
        "is_public":   isPublic,
    }
    
    var response APIResponse
    resp, err := r.httpClient.R().
        SetContext(ctx).
        SetBody(req).
        SetResult(&response).
        Post("/rooms")
    
    if err != nil {
        return nil, fmt.Errorf("create room request failed: %w", err)
    }
    
    if !response.Success {
        return nil, fmt.Errorf("create room failed: %s", response.Error.Message)
    }
    
    var room Room
    if err := json.Unmarshal(response.Data, &room); err != nil {
        return nil, fmt.Errorf("failed to parse room data: %w", err)
    }
    
    return &room, nil
}

func (r *RESTClient) GetRoom(ctx context.Context, roomID int) (*Room, error) {
    var response APIResponse
    resp, err := r.httpClient.R().
        SetContext(ctx).
        SetResult(&response).
        Get(fmt.Sprintf("/rooms/%d", roomID))
    
    if err != nil {
        return nil, fmt.Errorf("get room request failed: %w", err)
    }
    
    if resp.StatusCode() == 404 {
        return nil, fmt.Errorf("room not found")
    }
    
    if !response.Success {
        return nil, fmt.Errorf("get room failed: %s", response.Error.Message)
    }
    
    var room Room
    if err := json.Unmarshal(response.Data, &room); err != nil {
        return nil, fmt.Errorf("failed to parse room data: %w", err)
    }
    
    return &room, nil
}

func (r *RESTClient) ListRooms(ctx context.Context, limit, offset int) ([]Room, error) {
    var response APIResponse
    resp, err := r.httpClient.R().
        SetContext(ctx).
        SetQueryParams(map[string]string{
            "limit":  fmt.Sprintf("%d", limit),
            "offset": fmt.Sprintf("%d", offset),
        }).
        SetResult(&response).
        Get("/rooms")
    
    if err != nil {
        return nil, fmt.Errorf("list rooms request failed: %w", err)
    }
    
    if !response.Success {
        return nil, fmt.Errorf("list rooms failed: %s", response.Error.Message)
    }
    
    var rooms []Room
    if err := json.Unmarshal(response.Data, &rooms); err != nil {
        return nil, fmt.Errorf("failed to parse rooms data: %w", err)
    }
    
    return rooms, nil
}

// Gestion des messages
func (r *RESTClient) SendMessage(ctx context.Context, roomID int, content string, parentID *int) (*Message, error) {
    req := map[string]interface{}{
        "content": content,
    }
    
    if parentID != nil {
        req["parent_id"] = *parentID
    }
    
    var response APIResponse
    resp, err := r.httpClient.R().
        SetContext(ctx).
        SetBody(req).
        SetResult(&response).
        Post(fmt.Sprintf("/rooms/%d/messages", roomID))
    
    if err != nil {
        return nil, fmt.Errorf("send message request failed: %w", err)
    }
    
    if !response.Success {
        return nil, fmt.Errorf("send message failed: %s", response.Error.Message)
    }
    
    var message Message
    if err := json.Unmarshal(response.Data, &message); err != nil {
        return nil, fmt.Errorf("failed to parse message data: %w", err)
    }
    
    return &message, nil
}

func (r *RESTClient) GetMessages(ctx context.Context, roomID int, limit int, beforeID *int) ([]Message, error) {
    params := map[string]string{
        "limit": fmt.Sprintf("%d", limit),
    }
    
    if beforeID != nil {
        params["before_id"] = fmt.Sprintf("%d", *beforeID)
    }
    
    var response APIResponse
    resp, err := r.httpClient.R().
        SetContext(ctx).
        SetQueryParams(params).
        SetResult(&response).
        Get(fmt.Sprintf("/rooms/%d/messages", roomID))
    
    if err != nil {
        return nil, fmt.Errorf("get messages request failed: %w", err)
    }
    
    if !response.Success {
        return nil, fmt.Errorf("get messages failed: %s", response.Error.Message)
    }
    
    var messages []Message
    if err := json.Unmarshal(response.Data, &messages); err != nil {
        return nil, fmt.Errorf("failed to parse messages data: %w", err)
    }
    
    return messages, nil
}

// Upload de fichiers
func (r *RESTClient) UploadFile(ctx context.Context, roomID int, filename string, fileReader io.Reader) (*FileUploadResponse, error) {
    var response APIResponse
    
    resp, err := r.httpClient.R().
        SetContext(ctx).
        SetFileReader("file", filename, fileReader).
        SetFormData(map[string]string{
            "room_id": fmt.Sprintf("%d", roomID),
        }).
        SetResult(&response).
        Post("/files/upload")
    
    if err != nil {
        return nil, fmt.Errorf("file upload request failed: %w", err)
    }
    
    if !response.Success {
        return nil, fmt.Errorf("file upload failed: %s", response.Error.Message)
    }
    
    var uploadResp FileUploadResponse
    if err := json.Unmarshal(response.Data, &uploadResp); err != nil {
        return nil, fmt.Errorf("failed to parse upload response: %w", err)
    }
    
    return &uploadResp, nil
}

type FileUploadResponse struct {
    FileID   int    `json:"file_id"`
    Filename string `json:"filename"`
    URL      string `json:"url"`
    Size     int64  `json:"size"`
}
```

## 🚀 Exemple d'Application Complète

### **Chat Bot Simple**

```go
package main

import (
    "context"
    "fmt"
    "log"
    "os"
    "os/signal"
    "strings"
    "syscall"
    "time"
)

type ChatBot struct {
    config     *Config
    authClient *AuthClient
    wsClient   *WSClient
    restClient *RESTClient
    roomID     int
    botUserID  int
}

func main() {
    config := DefaultConfig()
    config.ServerURL = os.Getenv("CHAT_SERVER_URL")
    if config.ServerURL == "" {
        config.ServerURL = "http://localhost:8080"
    }
    
    bot := &ChatBot{
        config: config,
        roomID: 1, // Salon général
    }
    
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()
    
    // Initialisation des clients
    if err := bot.initialize(ctx); err != nil {
        log.Fatalf("Failed to initialize bot: %v", err)
    }
    
    // Gestion des signaux
    sigChan := make(chan os.Signal, 1)
    signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
    
    go func() {
        <-sigChan
        log.Println("Shutting down bot...")
        cancel()
    }()
    
    // Démarrage du bot
    if err := bot.start(ctx); err != nil {
        log.Fatalf("Bot failed: %v", err)
    }
}

func (b *ChatBot) initialize(ctx context.Context) error {
    // Client d'authentification
    b.authClient = NewAuthClient(b.config)
    
    username := os.Getenv("BOT_USERNAME")
    password := os.Getenv("BOT_PASSWORD")
    
    if err := b.authClient.Login(ctx, username, password); err != nil {
        return fmt.Errorf("authentication failed: %w", err)
    }
    
    // Client WebSocket
    b.wsClient = NewWSClient(b.config, b.authClient)
    b.wsClient.OnMessage(b.handleMessage)
    b.wsClient.OnConnect(func() {
        log.Println("Bot connected to WebSocket")
        b.wsClient.JoinRoom(b.roomID)
    })
    b.wsClient.OnDisconnect(func(err error) {
        log.Printf("Bot disconnected: %v", err)
    })
    
    // Client REST
    b.restClient = NewRESTClient(b.config, b.authClient)
    
    return nil
}

func (b *ChatBot) start(ctx context.Context) error {
    // Connexion WebSocket
    if err := b.wsClient.Connect(ctx); err != nil {
        return fmt.Errorf("WebSocket connection failed: %w", err)
    }
    
    // Démarrage du processeur de messages
    b.wsClient.StartMessageProcessing()
    
    // Gestionnaire de reconnexion
    reconnMgr := NewReconnectionManager(b.wsClient, b.config)
    reconnMgr.Start(ctx)
    
    log.Println("Chat bot started successfully")
    
    // Attendre l'arrêt
    <-ctx.Done()
    
    // Nettoyage
    return b.wsClient.Close()
}

func (b *ChatBot) handleMessage(msgType MessageType, data []byte) {
    switch msgType {
    case MessageReceivedMsg:
        b.handleRoomMessage(data)
    case DMReceivedMsg:
        b.handleDirectMessage(data)
    case ErrorMsg:
        log.Printf("Received error: %s", string(data))
    }
}

func (b *ChatBot) handleRoomMessage(data []byte) {
    var msg struct {
        ID        int    `json:"id"`
        AuthorID  int    `json:"author_id"`
        Username  string `json:"username"`
        Content   string `json:"content"`
        RoomID    int    `json:"room_id"`
    }
    
    if err := json.Unmarshal(data, &msg); err != nil {
        log.Printf("Failed to parse room message: %v", err)
        return
    }
    
    // Ignorer ses propres messages
    if msg.AuthorID == b.botUserID {
        return
    }
    
    log.Printf("Room message from %s: %s", msg.Username, msg.Content)
    
    // Traitement des commandes
    if strings.HasPrefix(msg.Content, "!bot ") {
        b.handleCommand(msg.Content[5:], msg.RoomID, msg.AuthorID)
    }
}

func (b *ChatBot) handleCommand(command string, roomID, userID int) {
    parts := strings.Fields(command)
    if len(parts) == 0 {
        return
    }
    
    switch parts[0] {
    case "help":
        response := "Commandes disponibles: !bot help, !bot ping, !bot time, !bot stats"
        b.wsClient.SendRoomMessage(roomID, response, nil)
        
    case "ping":
        b.wsClient.SendRoomMessage(roomID, "🏓 Pong!", nil)
        
    case "time":
        now := time.Now().Format("15:04:05")
        response := fmt.Sprintf("🕐 Il est actuellement %s", now)
        b.wsClient.SendRoomMessage(roomID, response, nil)
        
    case "stats":
        metrics := b.wsClient.GetMetrics()
        response := fmt.Sprintf("📊 Stats: %d messages reçus, %d envoyés, %d reconnexions", 
            metrics.MessagesReceived, metrics.MessagesSent, metrics.ReconnectionCount)
        b.wsClient.SendRoomMessage(roomID, response, nil)
        
    default:
        response := "Commande inconnue. Tapez `!bot help` pour voir les commandes disponibles."
        b.wsClient.SendRoomMessage(roomID, response, nil)
    }
}

func (b *ChatBot) handleDirectMessage(data []byte) {
    var dm struct {
        ID             int    `json:"id"`
        AuthorID       int    `json:"author_id"`
        Username       string `json:"username"`
        Content        string `json:"content"`
        ConversationID int    `json:"conversation_id"`
    }
    
    if err := json.Unmarshal(data, &dm); err != nil {
        log.Printf("Failed to parse DM: %v", err)
        return
    }
    
    log.Printf("DM from %s: %s", dm.Username, dm.Content)
    
    // Réponse automatique aux DM
    response := fmt.Sprintf("Salut %s! J'ai reçu ton message: \"%s\". Je suis un bot automatique.", 
        dm.Username, dm.Content)
    b.wsClient.SendDM(dm.ConversationID, response, nil)
}
```

## 🔧 Tests et Debugging

### **Tests Unitaires**

```go
package chatclient_test

import (
    "context"
    "testing"
    "time"
    
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
)

func TestAuthClient(t *testing.T) {
    config := DefaultConfig()
    authClient := NewAuthClient(config)
    
    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()
    
    // Test de login
    err := authClient.Login(ctx, "testuser", "testpass")
    require.NoError(t, err)
    
    // Test de récupération de token
    token, err := authClient.GetValidToken(ctx)
    require.NoError(t, err)
    assert.NotEmpty(t, token)
}

func TestWebSocketConnection(t *testing.T) {
    config := DefaultConfig()
    authClient := NewAuthClient(config)
    wsClient := NewWSClient(config, authClient)
    
    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()
    
    // Login
    err := authClient.Login(ctx, "testuser", "testpass")
    require.NoError(t, err)
    
    // Connexion WebSocket
    err = wsClient.Connect(ctx)
    require.NoError(t, err)
    
    defer wsClient.Close()
    
    // Test d'envoi de message
    err = wsClient.JoinRoom(1)
    assert.NoError(t, err)
    
    err = wsClient.SendRoomMessage(1, "Test message", nil)
    assert.NoError(t, err)
}

func TestRESTAPI(t *testing.T) {
    config := DefaultConfig()
    authClient := NewAuthClient(config)
    restClient := NewRESTClient(config, authClient)
    
    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()
    
    // Login
    err := authClient.Login(ctx, "testuser", "testpass")
    require.NoError(t, err)
    
    // Test de création de salon
    room, err := restClient.CreateRoom(ctx, "Test Room", "Room for testing", true)
    require.NoError(t, err)
    assert.Equal(t, "Test Room", room.Name)
    
    // Test d'envoi de message
    message, err := restClient.SendMessage(ctx, room.ID, "Hello, world!", nil)
    require.NoError(t, err)
    assert.Equal(t, "Hello, world!", message.Content)
    
    // Test de récupération de messages
    messages, err := restClient.GetMessages(ctx, room.ID, 10, nil)
    require.NoError(t, err)
    assert.Len(t, messages, 1)
}
```

## 📊 Monitoring et Métriques

### **Collecteur de Métriques Prometheus**

```go
package metrics

import (
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promauto"
)

type ChatMetrics struct {
    ConnectionsTotal    prometheus.Counter
    ConnectionsActive   prometheus.Gauge
    MessagesTotal       *prometheus.CounterVec
    MessageDuration     *prometheus.HistogramVec
    ErrorsTotal         *prometheus.CounterVec
    ReconnectionsTotal  prometheus.Counter
}

func NewChatMetrics() *ChatMetrics {
    return &ChatMetrics{
        ConnectionsTotal: promauto.NewCounter(prometheus.CounterOpts{
            Name: "chat_client_connections_total",
            Help: "Total number of connection attempts",
        }),
        ConnectionsActive: promauto.NewGauge(prometheus.GaugeOpts{
            Name: "chat_client_connections_active",
            Help: "Number of active connections",
        }),
        MessagesTotal: promauto.NewCounterVec(
            prometheus.CounterOpts{
                Name: "chat_client_messages_total",
                Help: "Total number of messages sent/received",
            },
            []string{"direction", "type"},
        ),
        MessageDuration: promauto.NewHistogramVec(
            prometheus.HistogramOpts{
                Name: "chat_client_message_duration_seconds",
                Help: "Time taken to process messages",
            },
            []string{"operation"},
        ),
        ErrorsTotal: promauto.NewCounterVec(
            prometheus.CounterOpts{
                Name: "chat_client_errors_total",
                Help: "Total number of errors",
            },
            []string{"type"},
        ),
        ReconnectionsTotal: promauto.NewCounter(prometheus.CounterOpts{
            Name: "chat_client_reconnections_total",
            Help: "Total number of reconnection attempts",
        }),
    }
}

func (m *ChatMetrics) RecordConnection() {
    m.ConnectionsTotal.Inc()
    m.ConnectionsActive.Inc()
}

func (m *ChatMetrics) RecordDisconnection() {
    m.ConnectionsActive.Dec()
}

func (m *ChatMetrics) RecordMessage(direction, msgType string) {
    m.MessagesTotal.WithLabelValues(direction, msgType).Inc()
}

func (m *ChatMetrics) RecordError(errorType string) {
    m.ErrorsTotal.WithLabelValues(errorType).Inc()
}

func (m *ChatMetrics) RecordReconnection() {
    m.ReconnectionsTotal.Inc()
}
```

## 📖 Bonnes Pratiques

### **1. Gestion des Erreurs**
- Toujours vérifier les erreurs de connexion
- Implémenter une retry logic appropriée
- Logger les erreurs avec suffisamment de contexte

### **2. Performance**
- Utiliser des pools de connexions
- Implémenter du batching pour les messages fréquents
- Monitorer les métriques en continu

### **3. Sécurité**
- Valider tous les tokens avant utilisation
- Ne jamais logger les tokens ou mots de passe
- Implémenter des timeouts appropriés

### **4. Monitoring**
- Exposer des métriques Prometheus
- Logger les événements importants
- Alerter sur les dysfonctionnements

---

Ce guide vous donne tous les outils nécessaires pour intégrer efficacement le serveur de chat Veza dans vos applications Go. Pour des questions spécifiques, consultez les [exemples avancés](./examples/go/) ou contactez le support technique. 