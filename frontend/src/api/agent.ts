import { apiClient } from './client';
import type { AgentChatResponse, AgentMode } from '../types/agent';

export async function agentChat(
  message: string,
  currentSqlId?: number | null,
  mode?: AgentMode,
): Promise<AgentChatResponse> {
  const { data } = await apiClient.post<AgentChatResponse>('/agent/chat', {
    message,
    current_sql_id: currentSqlId ?? null,
    mode,
  });
  return data;
}

export async function agentExplain(sqlId: number): Promise<AgentChatResponse> {
  const { data } = await apiClient.post<AgentChatResponse>('/agent/explain', {
    sql_id: sqlId,
  });
  return data;
}

export async function agentRecommendSimilar(
  sqlId: number,
): Promise<AgentChatResponse> {
  const { data } = await apiClient.post<AgentChatResponse>(
    '/agent/recommend-similar',
    { sql_id: sqlId },
  );
  return data;
}

export async function agentRewrite(
  sqlId: number,
  instruction: string,
  crossSql = false,
): Promise<AgentChatResponse> {
  const { data } = await apiClient.post<AgentChatResponse>('/agent/rewrite', {
    sql_id: sqlId,
    instruction,
    cross_sql: crossSql,
  });
  return data;
}

export async function agentCrossSqlRewrite(
  sqlId: number,
  instruction: string,
): Promise<AgentChatResponse> {
  const { data } = await apiClient.post<AgentChatResponse>(
    '/agent/cross-sql-rewrite',
    { sql_id: sqlId, instruction },
  );
  return data;
}

export async function agentGenerateSql(instruction: string): Promise<AgentChatResponse> {
  const { data } = await apiClient.post<AgentChatResponse>('/agent/generate-sql', {
    instruction,
  });
  return data;
}
