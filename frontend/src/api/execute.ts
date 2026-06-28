import { apiClient } from './client';
import {
  LocalBridgeNotConfiguredError,
  LocalBridgeUnavailableError,
  executeViaLocalBridge,
  fetchLocalBridgeStatus,
  isDorisNetworkError,
} from './localBridge';

export interface ExecuteResult {
  columns: string[];
  rows: unknown[][];
  row_count: number;
  truncated: boolean;
  executed_sql: string;
}

export async function detectSqlParams(sql: string): Promise<string[]> {
  const { data } = await apiClient.post<{ params: string[] }>('/sql/detect-params', {
    sql,
  });
  return data.params;
}

async function executeViaCloud(payload: {
  sql: string;
  start_date: string;
  end_date: string;
  params?: Record<string, string>;
  sql_file_id?: number;
}): Promise<ExecuteResult> {
  const { data } = await apiClient.post<ExecuteResult>('/sql/execute', payload);
  return data;
}

export async function executeSql(payload: {
  sql: string;
  start_date: string;
  end_date: string;
  params?: Record<string, string>;
  sql_file_id?: number;
}): Promise<ExecuteResult & { viaLocalBridge?: boolean }> {
  const bridge = await fetchLocalBridgeStatus();

  if (bridge.available && bridge.configured) {
    const result = await executeViaLocalBridge(payload);
    return { ...result, viaLocalBridge: true };
  }

  if (bridge.available && !bridge.configured) {
    throw new LocalBridgeNotConfiguredError();
  }

  try {
    return await executeViaCloud(payload);
  } catch (e: unknown) {
    const detail =
      (e as { response?: { data?: { detail?: string } } })?.response?.data?.detail ||
      (e instanceof Error ? e.message : '');
    if (isDorisNetworkError(String(detail))) {
      throw new LocalBridgeUnavailableError();
    }
    throw e;
  }
}

export {
  LocalBridgeNotConfiguredError,
  LocalBridgeUnavailableError,
  fetchLocalBridgeStatus,
  tryAutoConfigureFromStash,
} from './localBridge';
