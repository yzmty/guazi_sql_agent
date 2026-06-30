import { apiClient, getToken } from './client';
import type { AgentChatResponse, AgentMode } from '../types/agent';

export interface ConversationSummary {
  id: number;
  title: string;
  current_sql_id: number | null;
  updated_at: string | null;
}

export interface ConversationMessageRecord {
  id: number;
  role: 'user' | 'assistant' | 'system';
  content: string;
  mode?: AgentMode | 'chat';
  data?: Record<string, unknown>;
  created_at?: string;
}

export interface IndexStats {
  total: number;
  ready: number;
  pending: number;
  failed: number;
  queue_pending: number;
}

export type ChatStreamPayload = AgentChatResponse & {
  mode?: AgentMode | 'chat';
  event?: 'token' | 'done' | 'result';
  text?: string;
};

export interface ConversationChatStreamHandlers {
  /** Incremental token for free-form chat mode. */
  onToken?: (text: string) => void;
  /** Final chat turn or structured result. */
  onComplete?: (payload: ChatStreamPayload) => void;
}

export async function listConversations(): Promise<ConversationSummary[]> {
  const { data } = await apiClient.get<{ items: ConversationSummary[] }>('/conversations');
  return data.items;
}

export async function createConversation(
  currentSqlId?: number | null,
): Promise<ConversationSummary> {
  const { data } = await apiClient.post<ConversationSummary>('/conversations', {
    title: '新对话',
    current_sql_id: currentSqlId ?? null,
  });
  return data;
}

export async function getConversation(id: number): Promise<{
  id: number;
  title: string;
  current_sql_id: number | null;
  messages: ConversationMessageRecord[];
}> {
  const { data } = await apiClient.get(`/conversations/${id}`);
  return data;
}

export async function deleteConversation(id: number): Promise<void> {
  await apiClient.delete(`/conversations/${id}`);
}

export async function getIndexStats(): Promise<IndexStats> {
  const { data } = await apiClient.get<IndexStats>('/conversations/index-stats');
  return data;
}

export async function conversationChat(
  conversationId: number,
  message: string,
  currentSqlId?: number | null,
  libraryScope: 'personal' | 'shared' = 'personal',
): Promise<AgentChatResponse & { mode?: AgentMode | 'chat' }> {
  const { data } = await apiClient.post<AgentChatResponse>(`/conversations/${conversationId}/chat`, {
    message,
    current_sql_id: currentSqlId ?? null,
    stream: false,
    library_scope: libraryScope,
  });
  return data;
}

function dispatchStreamPayload(
  payload: ChatStreamPayload,
  handlers: ConversationChatStreamHandlers,
) {
  if (payload.event === 'token' && payload.text) {
    handlers.onToken?.(payload.text);
    return;
  }
  if (payload.event === 'done' || payload.event === 'result') {
    handlers.onComplete?.(payload);
    return;
  }
  // Legacy: single-shot structured response without event field
  if (payload.success !== undefined) {
    handlers.onComplete?.(payload);
  }
}

export async function conversationChatStream(
  conversationId: number,
  message: string,
  currentSqlId: number | null | undefined,
  libraryScope: 'personal' | 'shared',
  handlers: ConversationChatStreamHandlers,
): Promise<void> {
  const token = getToken();
  const resp = await fetch(`/api/conversations/${conversationId}/chat`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({
      message,
      current_sql_id: currentSqlId ?? null,
      stream: true,
      library_scope: libraryScope,
    }),
  });
  if (!resp.ok || !resp.body) {
    throw new Error('流式请求失败');
  }
  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const parts = buffer.split('\n\n');
    buffer = parts.pop() || '';
    for (const part of parts) {
      const line = part.trim();
      if (!line.startsWith('data:')) continue;
      const payloadText = line.slice(5).trim();
      if (payloadText === '[DONE]') return;
      dispatchStreamPayload(JSON.parse(payloadText) as ChatStreamPayload, handlers);
    }
  }
}
