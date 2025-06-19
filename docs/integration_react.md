# ⚛️ Intégration React - Guide Complet

**Version :** 0.2.0  
**Dernière mise à jour :** $(date +"%Y-%m-%d")

## 📋 Vue d'Ensemble

Ce guide vous accompagne pour intégrer le serveur de chat Veza dans vos applications React. Il couvre l'utilisation des hooks, la gestion d'état, les composants réutilisables, et les patterns modernes React.

## 🛠️ Installation et Configuration

### **Dépendances Requises**

```json
{
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "typescript": "^5.0.0",
    "@types/react": "^18.2.0",
    "@types/react-dom": "^18.2.0",
    "zustand": "^4.4.0",
    "react-query": "^3.39.0",
    "socket.io-client": "^4.7.0",
    "axios": "^1.5.0",
    "date-fns": "^2.30.0",
    "react-hook-form": "^7.45.0",
    "react-hot-toast": "^2.4.0",
    "@heroicons/react": "^2.0.0",
    "tailwindcss": "^3.3.0"
  },
  "devDependencies": {
    "@testing-library/react": "^13.4.0",
    "@testing-library/jest-dom": "^5.16.0",
    "@testing-library/user-event": "^14.4.0",
    "jest": "^27.5.0",
    "msw": "^1.2.0"
  }
}
```

### **Configuration TypeScript**

```typescript
// types/chat.ts
export interface User {
  id: number;
  username: string;
  email: string;
  role: 'user' | 'moderator' | 'admin';
  isOnline: boolean;
  lastSeen?: Date;
  avatar?: string;
}

export interface Room {
  id: number;
  uuid: string;
  name: string;
  description?: string;
  isPublic: boolean;
  ownerId: number;
  memberCount: number;
  unreadCount: number;
  lastActivity?: Date;
  createdAt: Date;
  updatedAt: Date;
}

export interface Message {
  id: number;
  uuid: string;
  authorId: number;
  username: string;
  content: string;
  roomId?: number;
  conversationId?: number;
  parentMessageId?: number;
  threadCount: number;
  isPinned: boolean;
  isEdited: boolean;
  editCount: number;
  reactions: Record<string, ReactionInfo>;
  mentions: number[];
  metadata: Record<string, any>;
  createdAt: Date;
  updatedAt: Date;
  editedAt?: Date;
}

export interface ReactionInfo {
  count: number;
  users: Array<{
    userId: number;
    username: string;
  }>;
  hasUserReacted: boolean;
}

export interface Conversation {
  id: number;
  uuid: string;
  otherUser: User;
  lastMessage?: Message;
  unreadCount: number;
  isBlocked: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface ChatConfig {
  serverUrl: string;
  wsEndpoint: string;
  apiEndpoint: string;
  enableReconnect: boolean;
  reconnectDelay: number;
  maxReconnectAttempts: number;
  messageRetention: number;
  enableNotifications: boolean;
  enableTypingIndicators: boolean;
}

export interface WSMessage {
  type: string;
  data: any;
}

export interface ChatState {
  // Connexion
  isConnected: boolean;
  isConnecting: boolean;
  connectionError: string | null;
  
  // Utilisateur
  currentUser: User | null;
  
  // Salons
  rooms: Room[];
  activeRoomId: number | null;
  roomMessages: Record<number, Message[]>;
  
  // Messages directs
  conversations: Conversation[];
  activeConversationId: number | null;
  dmMessages: Record<number, Message[]>;
  
  // UI
  typingUsers: Record<number, User[]>;
  onlineUsers: User[];
  notifications: Notification[];
}
```

## 🔗 Hook WebSocket Principal

### **useWebSocket Hook**

```typescript
// hooks/useWebSocket.ts
import { useEffect, useRef, useCallback, useState } from 'react';
import { useChatStore } from '../store/chatStore';

interface UseWebSocketOptions {
  url: string;
  token: string;
  onConnect?: () => void;
  onDisconnect?: (error?: Error) => void;
  onError?: (error: Error) => void;
  enableReconnect?: boolean;
  reconnectDelay?: number;
  maxReconnectAttempts?: number;
}

export function useWebSocket(options: UseWebSocketOptions) {
  const {
    url,
    token,
    onConnect,
    onDisconnect,
    onError,
    enableReconnect = true,
    reconnectDelay = 3000,
    maxReconnectAttempts = 5,
  } = options;

  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout>();
  const reconnectAttemptsRef = useRef(0);
  const messageQueueRef = useRef<WSMessage[]>([]);
  
  const [isConnected, setIsConnected] = useState(false);
  const [isConnecting, setIsConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  const {
    setConnectionStatus,
    processMessage,
    addNotification,
  } = useChatStore();

  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      return;
    }

    setIsConnecting(true);
    setError(null);

    try {
      const ws = new WebSocket(url);
      wsRef.current = ws;

      ws.onopen = () => {
        console.log('WebSocket connected');
        setIsConnected(true);
        setIsConnecting(false);
        setError(null);
        reconnectAttemptsRef.current = 0;
        
        setConnectionStatus(true, false, null);
        
        // Authentification immédiate
        ws.send(JSON.stringify({
          type: 'authenticate',
          data: { token }
        }));
        
        // Envoyer les messages en attente
        while (messageQueueRef.current.length > 0) {
          const message = messageQueueRef.current.shift();
          if (message) {
            ws.send(JSON.stringify(message));
          }
        }
        
        onConnect?.();
      };

      ws.onmessage = (event) => {
        try {
          const message: WSMessage = JSON.parse(event.data);
          processMessage(message);
        } catch (err) {
          console.error('Failed to parse WebSocket message:', err);
        }
      };

      ws.onclose = (event) => {
        console.log('WebSocket disconnected:', event.code, event.reason);
        setIsConnected(false);
        setIsConnecting(false);
        setConnectionStatus(false, false, null);
        
        const error = new Error(`Connection closed: ${event.reason || 'Unknown reason'}`);
        onDisconnect?.(error);
        
        // Reconnexion automatique
        if (enableReconnect && reconnectAttemptsRef.current < maxReconnectAttempts) {
          reconnectAttemptsRef.current++;
          const delay = reconnectDelay * Math.pow(2, reconnectAttemptsRef.current - 1);
          
          console.log(`Attempting reconnection ${reconnectAttemptsRef.current}/${maxReconnectAttempts} in ${delay}ms`);
          
          reconnectTimeoutRef.current = setTimeout(() => {
            connect();
          }, delay);
        } else if (reconnectAttemptsRef.current >= maxReconnectAttempts) {
          const maxAttemptsError = 'Maximum reconnection attempts reached';
          setError(maxAttemptsError);
          setConnectionStatus(false, false, maxAttemptsError);
          
          addNotification({
            type: 'error',
            title: 'Connexion perdue',
            message: 'Impossible de se reconnecter au serveur. Veuillez rafraîchir la page.',
            persistent: true,
          });
        }
      };

      ws.onerror = (event) => {
        console.error('WebSocket error:', event);
        const error = new Error('WebSocket connection error');
        setError(error.message);
        setConnectionStatus(false, false, error.message);
        onError?.(error);
      };

    } catch (err) {
      const error = err as Error;
      console.error('Failed to create WebSocket connection:', error);
      setError(error.message);
      setIsConnecting(false);
      setConnectionStatus(false, false, error.message);
    }
  }, [url, token, enableReconnect, reconnectDelay, maxReconnectAttempts, onConnect, onDisconnect, onError, setConnectionStatus, processMessage, addNotification]);

  const disconnect = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
    }
    
    if (wsRef.current) {
      wsRef.current.close(1000, 'User initiated disconnect');
      wsRef.current = null;
    }
    
    setIsConnected(false);
    setIsConnecting(false);
    setError(null);
    setConnectionStatus(false, false, null);
  }, [setConnectionStatus]);

  const sendMessage = useCallback((message: WSMessage) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify(message));
    } else {
      // Mettre en file d'attente si pas connecté
      messageQueueRef.current.push(message);
      
      if (!isConnected && !isConnecting) {
        connect();
      }
    }
  }, [isConnected, isConnecting, connect]);

  // Actions spécialisées
  const joinRoom = useCallback((roomId: number) => {
    sendMessage({
      type: 'join_room',
      data: { room_id: roomId }
    });
  }, [sendMessage]);

  const leaveRoom = useCallback((roomId: number) => {
    sendMessage({
      type: 'leave_room',
      data: { room_id: roomId }
    });
  }, [sendMessage]);

  const sendRoomMessage = useCallback((roomId: number, content: string, parentId?: number) => {
    sendMessage({
      type: 'send_message',
      data: {
        room_id: roomId,
        content,
        parent_id: parentId,
        metadata: {
          client: 'react-web',
          timestamp: Date.now(),
        }
      }
    });
  }, [sendMessage]);

  const sendDirectMessage = useCallback((conversationId: number, content: string, parentId?: number) => {
    sendMessage({
      type: 'send_dm',
      data: {
        conversation_id: conversationId,
        content,
        parent_id: parentId,
        metadata: {
          client: 'react-web',
          timestamp: Date.now(),
        }
      }
    });
  }, [sendMessage]);

  const addReaction = useCallback((messageId: number, emoji: string) => {
    sendMessage({
      type: 'add_reaction',
      data: {
        message_id: messageId,
        emoji
      }
    });
  }, [sendMessage]);

  const removeReaction = useCallback((messageId: number, emoji: string) => {
    sendMessage({
      type: 'remove_reaction',
      data: {
        message_id: messageId,
        emoji
      }
    });
  }, [sendMessage]);

  const pinMessage = useCallback((roomId: number, messageId: number, pin: boolean = true) => {
    sendMessage({
      type: pin ? 'pin_message' : 'unpin_message',
      data: {
        room_id: roomId,
        message_id: messageId
      }
    });
  }, [sendMessage]);

  useEffect(() => {
    connect();
    
    return () => {
      disconnect();
    };
  }, [connect, disconnect]);

  return {
    isConnected,
    isConnecting,
    error,
    connect,
    disconnect,
    sendMessage,
    
    // Actions spécialisées
    joinRoom,
    leaveRoom,
    sendRoomMessage,
    sendDirectMessage,
    addReaction,
    removeReaction,
    pinMessage,
  };
}
```

## 🗄️ Store Zustand

### **Store Principal**

```typescript
// store/chatStore.ts
import { create } from 'zustand';
import { devtools, subscribeWithSelector } from 'zustand/middleware';
import { produce } from 'immer';

interface ChatState {
  // Connexion
  isConnected: boolean;
  isConnecting: boolean;
  connectionError: string | null;
  
  // Utilisateur
  currentUser: User | null;
  authToken: string | null;
  
  // Salons
  rooms: Room[];
  activeRoomId: number | null;
  roomMessages: Record<number, Message[]>;
  roomTypingUsers: Record<number, User[]>;
  
  // Messages directs
  conversations: Conversation[];
  activeConversationId: number | null;
  dmMessages: Record<number, Message[]>;
  dmTypingUsers: Record<number, User[]>;
  
  // UI
  onlineUsers: User[];
  notifications: AppNotification[];
  unreadCounts: Record<number, number>;
}

interface ChatActions {
  // Connexion
  setConnectionStatus: (connected: boolean, connecting: boolean, error: string | null) => void;
  
  // Authentification
  setCurrentUser: (user: User | null) => void;
  setAuthToken: (token: string | null) => void;
  
  // Salons
  setRooms: (rooms: Room[]) => void;
  addRoom: (room: Room) => void;
  updateRoom: (roomId: number, updates: Partial<Room>) => void;
  setActiveRoom: (roomId: number | null) => void;
  
  // Messages de salon
  addRoomMessage: (roomId: number, message: Message) => void;
  updateRoomMessage: (roomId: number, messageId: number, updates: Partial<Message>) => void;
  setRoomMessages: (roomId: number, messages: Message[]) => void;
  prependRoomMessages: (roomId: number, messages: Message[]) => void;
  
  // Messages directs
  setConversations: (conversations: Conversation[]) => void;
  addConversation: (conversation: Conversation) => void;
  updateConversation: (conversationId: number, updates: Partial<Conversation>) => void;
  setActiveConversation: (conversationId: number | null) => void;
  addDMMessage: (conversationId: number, message: Message) => void;
  updateDMMessage: (conversationId: number, messageId: number, updates: Partial<Message>) => void;
  setDMMessages: (conversationId: number, messages: Message[]) => void;
  
  // Réactions
  updateMessageReactions: (messageId: number, reactions: Record<string, ReactionInfo>) => void;
  
  // Présence et indicateurs
  setOnlineUsers: (users: User[]) => void;
  setTypingUsers: (roomId: number, users: User[]) => void;
  setDMTypingUsers: (conversationId: number, users: User[]) => void;
  
  // Notifications
  addNotification: (notification: Omit<AppNotification, 'id' | 'timestamp'>) => void;
  removeNotification: (id: string) => void;
  clearNotifications: () => void;
  
  // Traitement des messages WebSocket
  processMessage: (message: WSMessage) => void;
  
  // Utilitaires
  markRoomAsRead: (roomId: number) => void;
  markConversationAsRead: (conversationId: number) => void;
  getUnreadCount: () => number;
}

type ChatStore = ChatState & ChatActions;

export const useChatStore = create<ChatStore>()(
  devtools(
    subscribeWithSelector(
      (set, get) => ({
        // État initial
        isConnected: false,
        isConnecting: false,
        connectionError: null,
        currentUser: null,
        authToken: localStorage.getItem('chat_token'),
        rooms: [],
        activeRoomId: null,
        roomMessages: {},
        roomTypingUsers: {},
        conversations: [],
        activeConversationId: null,
        dmMessages: {},
        dmTypingUsers: {},
        onlineUsers: [],
        notifications: [],
        unreadCounts: {},

        // Actions de connexion
        setConnectionStatus: (connected, connecting, error) =>
          set({ isConnected: connected, isConnecting: connecting, connectionError: error }),

        // Actions d'authentification
        setCurrentUser: (user) => set({ currentUser: user }),
        setAuthToken: (token) => {
          if (token) {
            localStorage.setItem('chat_token', token);
          } else {
            localStorage.removeItem('chat_token');
          }
          set({ authToken: token });
        },

        // Actions de salons
        setRooms: (rooms) => set({ rooms }),
        addRoom: (room) =>
          set(produce((state: ChatState) => {
            state.rooms.push(room);
          })),
        updateRoom: (roomId, updates) =>
          set(produce((state: ChatState) => {
            const roomIndex = state.rooms.findIndex(r => r.id === roomId);
            if (roomIndex !== -1) {
              Object.assign(state.rooms[roomIndex], updates);
            }
          })),
        setActiveRoom: (roomId) => set({ activeRoomId: roomId }),

        // Actions de messages de salon
        addRoomMessage: (roomId, message) =>
          set(produce((state: ChatState) => {
            if (!state.roomMessages[roomId]) {
              state.roomMessages[roomId] = [];
            }
            state.roomMessages[roomId].push(message);
            
            // Limiter le nombre de messages en mémoire
            if (state.roomMessages[roomId].length > 100) {
              state.roomMessages[roomId] = state.roomMessages[roomId].slice(-100);
            }
          })),
        
        updateRoomMessage: (roomId, messageId, updates) =>
          set(produce((state: ChatState) => {
            const messages = state.roomMessages[roomId];
            if (messages) {
              const messageIndex = messages.findIndex(m => m.id === messageId);
              if (messageIndex !== -1) {
                Object.assign(messages[messageIndex], updates);
              }
            }
          })),
        
        setRoomMessages: (roomId, messages) =>
          set(produce((state: ChatState) => {
            state.roomMessages[roomId] = messages;
          })),
        
        prependRoomMessages: (roomId, messages) =>
          set(produce((state: ChatState) => {
            if (!state.roomMessages[roomId]) {
              state.roomMessages[roomId] = [];
            }
            state.roomMessages[roomId] = [...messages, ...state.roomMessages[roomId]];
          })),

        // Actions de conversations
        setConversations: (conversations) => set({ conversations }),
        addConversation: (conversation) =>
          set(produce((state: ChatState) => {
            state.conversations.push(conversation);
          })),
        updateConversation: (conversationId, updates) =>
          set(produce((state: ChatState) => {
            const convIndex = state.conversations.findIndex(c => c.id === conversationId);
            if (convIndex !== -1) {
              Object.assign(state.conversations[convIndex], updates);
            }
          })),
        setActiveConversation: (conversationId) => set({ activeConversationId: conversationId }),

        // Actions de messages directs
        addDMMessage: (conversationId, message) =>
          set(produce((state: ChatState) => {
            if (!state.dmMessages[conversationId]) {
              state.dmMessages[conversationId] = [];
            }
            state.dmMessages[conversationId].push(message);
            
            if (state.dmMessages[conversationId].length > 100) {
              state.dmMessages[conversationId] = state.dmMessages[conversationId].slice(-100);
            }
          })),
        
        updateDMMessage: (conversationId, messageId, updates) =>
          set(produce((state: ChatState) => {
            const messages = state.dmMessages[conversationId];
            if (messages) {
              const messageIndex = messages.findIndex(m => m.id === messageId);
              if (messageIndex !== -1) {
                Object.assign(messages[messageIndex], updates);
              }
            }
          })),
        
        setDMMessages: (conversationId, messages) =>
          set(produce((state: ChatState) => {
            state.dmMessages[conversationId] = messages;
          })),

        // Actions de réactions
        updateMessageReactions: (messageId, reactions) =>
          set(produce((state: ChatState) => {
            // Mise à jour dans les messages de salon
            Object.values(state.roomMessages).forEach(messages => {
              const message = messages.find(m => m.id === messageId);
              if (message) {
                message.reactions = reactions;
              }
            });
            
            // Mise à jour dans les messages directs
            Object.values(state.dmMessages).forEach(messages => {
              const message = messages.find(m => m.id === messageId);
              if (message) {
                message.reactions = reactions;
              }
            });
          })),

        // Actions de présence
        setOnlineUsers: (users) => set({ onlineUsers: users }),
        setTypingUsers: (roomId, users) =>
          set(produce((state: ChatState) => {
            state.roomTypingUsers[roomId] = users;
          })),
        setDMTypingUsers: (conversationId, users) =>
          set(produce((state: ChatState) => {
            state.dmTypingUsers[conversationId] = users;
          })),

        // Actions de notifications
        addNotification: (notification) =>
          set(produce((state: ChatState) => {
            const newNotification: AppNotification = {
              ...notification,
              id: Math.random().toString(36).substr(2, 9),
              timestamp: new Date(),
            };
            state.notifications.push(newNotification);
          })),
        
        removeNotification: (id) =>
          set(produce((state: ChatState) => {
            state.notifications = state.notifications.filter(n => n.id !== id);
          })),
        
        clearNotifications: () => set({ notifications: [] }),

        // Traitement des messages WebSocket
        processMessage: (message: WSMessage) => {
          const { type, data } = message;
          const state = get();
          
          switch (type) {
            case 'auth_success':
              state.setCurrentUser(data.user);
              break;
              
            case 'room_joined':
              state.updateRoom(data.room_id, {
                memberCount: data.member_count,
                unreadCount: 0,
              });
              break;
              
            case 'room_message':
              state.addRoomMessage(data.room_id, data);
              if (data.room_id !== state.activeRoomId) {
                state.addNotification({
                  type: 'message',
                  title: `Nouveau message dans ${data.room_name}`,
                  message: `${data.username}: ${data.content}`,
                  roomId: data.room_id,
                });
              }
              break;
              
            case 'dm_message':
              state.addDMMessage(data.conversation_id, data);
              if (data.conversation_id !== state.activeConversationId) {
                state.addNotification({
                  type: 'dm',
                  title: `Message de ${data.username}`,
                  message: data.content,
                  conversationId: data.conversation_id,
                });
              }
              break;
              
            case 'reaction_added':
            case 'reaction_removed':
              // Mettre à jour les réactions (nécessite une requête pour obtenir l'état complet)
              break;
              
            case 'user_presence':
              // Mettre à jour la présence utilisateur
              break;
              
            case 'typing_start':
              if (data.room_id) {
                const currentTyping = state.roomTypingUsers[data.room_id] || [];
                if (!currentTyping.find(u => u.id === data.user_id)) {
                  state.setTypingUsers(data.room_id, [...currentTyping, { id: data.user_id, username: data.username }]);
                }
              }
              break;
              
            case 'typing_stop':
              if (data.room_id) {
                const currentTyping = state.roomTypingUsers[data.room_id] || [];
                state.setTypingUsers(data.room_id, currentTyping.filter(u => u.id !== data.user_id));
              }
              break;
              
            case 'error':
              state.addNotification({
                type: 'error',
                title: 'Erreur',
                message: data.message || 'Une erreur est survenue',
              });
              break;
          }
        },

        // Utilitaires
        markRoomAsRead: (roomId) =>
          set(produce((state: ChatState) => {
            state.unreadCounts[roomId] = 0;
            const room = state.rooms.find(r => r.id === roomId);
            if (room) {
              room.unreadCount = 0;
            }
          })),
        
        markConversationAsRead: (conversationId) =>
          set(produce((state: ChatState) => {
            state.unreadCounts[conversationId] = 0;
            const conversation = state.conversations.find(c => c.id === conversationId);
            if (conversation) {
              conversation.unreadCount = 0;
            }
          })),
        
        getUnreadCount: () => {
          const state = get();
          return Object.values(state.unreadCounts).reduce((total, count) => total + count, 0);
        },
      })
    )
  )
);

interface AppNotification {
  id: string;
  type: 'message' | 'dm' | 'error' | 'info' | 'success';
  title: string;
  message: string;
  roomId?: number;
  conversationId?: number;
  persistent?: boolean;
  timestamp: Date;
}
```

## 🎨 Composants Réutilisables

### **Composant Message**

```tsx
// components/Message.tsx
import React, { useState, useCallback } from 'react';
import { formatDistanceToNow } from 'date-fns';
import { fr } from 'date-fns/locale';
import {
  EllipsisVerticalIcon,
  PaperClipIcon,
  PencilIcon,
  TrashIcon,
  ChatBubbleLeftRightIcon,
} from '@heroicons/react/24/outline';

interface MessageProps {
  message: Message;
  currentUserId: number;
  showThread?: boolean;
  isThreaded?: boolean;
  onReply?: (messageId: number) => void;
  onEdit?: (messageId: number, content: string) => void;
  onDelete?: (messageId: number) => void;
  onReaction?: (messageId: number, emoji: string) => void;
  onRemoveReaction?: (messageId: number, emoji: string) => void;
}

export const MessageComponent: React.FC<MessageProps> = ({
  message,
  currentUserId,
  showThread = true,
  isThreaded = false,
  onReply,
  onEdit,
  onDelete,
  onReaction,
  onRemoveReaction,
}) => {
  const [showMenu, setShowMenu] = useState(false);
  const [isEditing, setIsEditing] = useState(false);
  const [editContent, setEditContent] = useState(message.content);
  const [showReactions, setShowReactions] = useState(false);

  const isOwn = message.authorId === currentUserId;
  const canEdit = isOwn && !message.isEdited;
  const canDelete = isOwn;

  const handleEdit = useCallback(() => {
    if (editContent.trim() && editContent !== message.content) {
      onEdit?.(message.id, editContent.trim());
    }
    setIsEditing(false);
  }, [editContent, message.content, message.id, onEdit]);

  const handleReaction = useCallback((emoji: string) => {
    const reaction = message.reactions[emoji];
    if (reaction?.hasUserReacted) {
      onRemoveReaction?.(message.id, emoji);
    } else {
      onReaction?.(message.id, emoji);
    }
  }, [message.id, message.reactions, onReaction, onRemoveReaction]);

  const popularEmojis = ['👍', '❤️', '😂', '😮', '😢', '😡'];

  return (
    <div className={`group flex ${isOwn ? 'justify-end' : 'justify-start'} ${isThreaded ? 'ml-8' : ''}`}>
      <div className={`max-w-xs lg:max-w-md ${isOwn ? 'order-1' : 'order-2'}`}>
        
        {/* Avatar et nom d'utilisateur */}
        {!isOwn && (
          <div className="flex items-center space-x-2 mb-1">
            <div className="w-8 h-8 bg-blue-500 rounded-full flex items-center justify-center text-white text-sm font-semibold">
              {message.username.charAt(0).toUpperCase()}
            </div>
            <span className="text-sm font-medium text-gray-700">
              {message.username}
            </span>
            <span className="text-xs text-gray-500">
              {formatDistanceToNow(message.createdAt, { addSuffix: true, locale: fr })}
            </span>
          </div>
        )}

        {/* Bulle de message */}
        <div
          className={`relative px-4 py-2 rounded-2xl ${
            isOwn
              ? 'bg-blue-500 text-white'
              : 'bg-gray-100 text-gray-800'
          }`}
        >
          {/* Contenu du message */}
          {isEditing ? (
            <div className="space-y-2">
              <textarea
                value={editContent}
                onChange={(e) => setEditContent(e.target.value)}
                className="w-full p-2 border border-gray-300 rounded resize-none bg-white text-gray-800"
                rows={2}
                autoFocus
              />
              <div className="flex space-x-2">
                <button
                  onClick={handleEdit}
                  className="px-3 py-1 bg-blue-500 text-white text-sm rounded hover:bg-blue-600"
                >
                  Sauvegarder
                </button>
                <button
                  onClick={() => {
                    setIsEditing(false);
                    setEditContent(message.content);
                  }}
                  className="px-3 py-1 bg-gray-300 text-gray-700 text-sm rounded hover:bg-gray-400"
                >
                  Annuler
                </button>
              </div>
            </div>
          ) : (
            <>
              <p className="break-words">{message.content}</p>
              
              {/* Indicateur d'édition */}
              {message.isEdited && (
                <span className={`text-xs ${isOwn ? 'text-blue-100' : 'text-gray-500'}`}>
                  (modifié)
                </span>
              )}
              
              {/* Indicateur de thread */}
              {message.threadCount > 0 && showThread && (
                <div className={`mt-2 text-xs ${isOwn ? 'text-blue-100' : 'text-gray-500'}`}>
                  <ChatBubbleLeftRightIcon className="w-4 h-4 inline mr-1" />
                  {message.threadCount} réponse{message.threadCount > 1 ? 's' : ''}
                </div>
              )}
            </>
          )}

          {/* Menu actions */}
          {!isEditing && (
            <div className="absolute top-0 right-0 transform translate-x-2 -translate-y-2 opacity-0 group-hover:opacity-100 transition-opacity">
              <div className="relative">
                <button
                  onClick={() => setShowMenu(!showMenu)}
                  className="p-1 bg-white rounded-full shadow-md hover:bg-gray-50"
                >
                  <EllipsisVerticalIcon className="w-4 h-4 text-gray-600" />
                </button>
                
                {showMenu && (
                  <div className="absolute right-0 mt-1 w-48 bg-white rounded-md shadow-lg z-10 border">
                    <div className="py-1">
                      {onReply && (
                        <button
                          onClick={() => {
                            onReply(message.id);
                            setShowMenu(false);
                          }}
                          className="flex items-center w-full px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                        >
                          <ChatBubbleLeftRightIcon className="w-4 h-4 mr-2" />
                          Répondre
                        </button>
                      )}
                      
                      {canEdit && onEdit && (
                        <button
                          onClick={() => {
                            setIsEditing(true);
                            setShowMenu(false);
                          }}
                          className="flex items-center w-full px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                        >
                          <PencilIcon className="w-4 h-4 mr-2" />
                          Modifier
                        </button>
                      )}
                      
                      {canDelete && onDelete && (
                        <button
                          onClick={() => {
                            onDelete(message.id);
                            setShowMenu(false);
                          }}
                          className="flex items-center w-full px-4 py-2 text-sm text-red-600 hover:bg-gray-100"
                        >
                          <TrashIcon className="w-4 h-4 mr-2" />
                          Supprimer
                        </button>
                      )}
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Réactions */}
        {Object.keys(message.reactions).length > 0 && (
          <div className="mt-1 flex flex-wrap gap-1">
            {Object.entries(message.reactions).map(([emoji, info]) => (
              <button
                key={emoji}
                onClick={() => handleReaction(emoji)}
                className={`inline-flex items-center px-2 py-1 rounded-full text-xs ${
                  info.hasUserReacted
                    ? 'bg-blue-100 text-blue-800 border border-blue-300'
                    : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                }`}
              >
                <span className="mr-1">{emoji}</span>
                <span>{info.count}</span>
              </button>
            ))}
            
            {/* Bouton pour ajouter une réaction */}
            <div className="relative">
              <button
                onClick={() => setShowReactions(!showReactions)}
                className="inline-flex items-center px-2 py-1 rounded-full text-xs bg-gray-100 text-gray-500 hover:bg-gray-200"
              >
                +
              </button>
              
              {showReactions && (
                <div className="absolute bottom-full left-0 mb-1 bg-white rounded-lg shadow-lg border p-2 z-10">
                  <div className="flex space-x-1">
                    {popularEmojis.map(emoji => (
                      <button
                        key={emoji}
                        onClick={() => {
                          handleReaction(emoji);
                          setShowReactions(false);
                        }}
                        className="p-1 hover:bg-gray-100 rounded"
                      >
                        {emoji}
                      </button>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Timestamp pour les messages envoyés */}
        {isOwn && (
          <div className="text-xs text-gray-500 text-right mt-1">
            {formatDistanceToNow(message.createdAt, { addSuffix: true, locale: fr })}
          </div>
        )}
      </div>
    </div>
  );
};
```

### **Composant Chat Room**

```tsx
// components/ChatRoom.tsx
import React, { useEffect, useRef, useState, useCallback } from 'react';
import { useChatStore } from '../store/chatStore';
import { useWebSocket } from '../hooks/useWebSocket';
import { MessageComponent } from './Message';
import { MessageInput } from './MessageInput';
import { UserList } from './UserList';
import { TypingIndicator } from './TypingIndicator';

interface ChatRoomProps {
  roomId: number;
  token: string;
}

export const ChatRoom: React.FC<ChatRoomProps> = ({ roomId, token }) => {
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const [replyToMessage, setReplyToMessage] = useState<number | null>(null);
  const [isLoadingHistory, setIsLoadingHistory] = useState(false);
  
  const {
    roomMessages,
    activeRoomId,
    roomTypingUsers,
    currentUser,
    setActiveRoom,
    markRoomAsRead,
  } = useChatStore();
  
  const {
    isConnected,
    joinRoom,
    leaveRoom,
    sendRoomMessage,
    addReaction,
    removeReaction,
  } = useWebSocket({
    url: process.env.REACT_APP_WS_URL || 'ws://localhost:8080/ws',
    token,
  });

  const messages = roomMessages[roomId] || [];
  const typingUsers = roomTypingUsers[roomId] || [];

  // Rejoindre le salon à l'activation
  useEffect(() => {
    if (isConnected && roomId !== activeRoomId) {
      joinRoom(roomId);
      setActiveRoom(roomId);
      markRoomAsRead(roomId);
    }
    
    return () => {
      if (activeRoomId === roomId) {
        leaveRoom(roomId);
        setActiveRoom(null);
      }
    };
  }, [roomId, isConnected, activeRoomId, joinRoom, leaveRoom, setActiveRoom, markRoomAsRead]);

  // Scroll automatique vers le bas
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const handleSendMessage = useCallback((content: string) => {
    if (content.trim() && currentUser) {
      sendRoomMessage(roomId, content.trim(), replyToMessage || undefined);
      setReplyToMessage(null);
    }
  }, [roomId, replyToMessage, sendRoomMessage, currentUser]);

  const handleReply = useCallback((messageId: number) => {
    setReplyToMessage(messageId);
  }, []);

  const handleEdit = useCallback((messageId: number, content: string) => {
    // TODO: Implémenter l'édition via API REST
    console.log('Edit message:', messageId, content);
  }, []);

  const handleDelete = useCallback((messageId: number) => {
    // TODO: Implémenter la suppression via API REST
    console.log('Delete message:', messageId);
  }, []);

  const replyMessage = replyToMessage ? messages.find(m => m.id === replyToMessage) : null;

  if (!isConnected) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="text-center">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500 mx-auto mb-4"></div>
          <p className="text-gray-500">Connexion en cours...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-full">
      <div className="flex-1 flex flex-col">
        {/* Zone de messages */}
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {messages.map((message) => (
            <MessageComponent
              key={message.id}
              message={message}
              currentUserId={currentUser?.id || 0}
              onReply={handleReply}
              onEdit={handleEdit}
              onDelete={handleDelete}
              onReaction={addReaction}
              onRemoveReaction={removeReaction}
            />
          ))}
          
          {/* Indicateur de frappe */}
          {typingUsers.length > 0 && (
            <TypingIndicator users={typingUsers} />
          )}
          
          <div ref={messagesEndRef} />
        </div>

        {/* Zone de réponse */}
        {replyMessage && (
          <div className="px-4 py-2 bg-gray-50 border-t border-gray-200">
            <div className="flex items-center justify-between">
              <div className="text-sm text-gray-600">
                Réponse à <span className="font-medium">{replyMessage.username}</span>:
                <span className="ml-1 italic">
                  {replyMessage.content.length > 50 
                    ? `${replyMessage.content.substring(0, 50)}...` 
                    : replyMessage.content}
                </span>
              </div>
              <button
                onClick={() => setReplyToMessage(null)}
                className="text-gray-400 hover:text-gray-600"
              >
                ✕
              </button>
            </div>
          </div>
        )}

        {/* Zone de saisie */}
        <div className="border-t border-gray-200">
          <MessageInput
            onSendMessage={handleSendMessage}
            placeholder={
              replyMessage 
                ? `Répondre à ${replyMessage.username}...`
                : "Tapez votre message..."
            }
            disabled={!isConnected}
          />
        </div>
      </div>

      {/* Liste des utilisateurs */}
      <div className="w-64 border-l border-gray-200">
        <UserList roomId={roomId} />
      </div>
    </div>
  );
};
```

Ce guide couvre les aspects essentiels de l'intégration React avec le serveur de chat Veza. La suite inclura d'autres composants, hooks avancés, et patterns de gestion d'état. 