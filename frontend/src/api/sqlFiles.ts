/** API client for backend SQL file endpoints. */

import { apiClient } from './client';
import type {
  BatchSaveResponse,
  FilterOptions,
  ParseBatchItem,
  SearchFilters,
  SqlFileDetail,
  SqlFileListResponse,
} from '../types/sqlFile';

export async function searchSqlFiles(
  filters: SearchFilters,
): Promise<SqlFileListResponse> {
  const { data } = await apiClient.get<SqlFileListResponse>('/sql-files', {
    params: filters,
  });
  return data;
}

export async function getSqlFileDetail(id: number): Promise<SqlFileDetail> {
  const { data } = await apiClient.get<SqlFileDetail>(`/sql-files/${id}`);
  return data;
}

export async function getFilterOptions(): Promise<FilterOptions> {
  const { data } = await apiClient.get<FilterOptions>('/sql-files/filter-options');
  return data;
}

export async function parseSqlBatch(
  items: { file_name: string; full_content: string }[],
): Promise<ParseBatchItem[]> {
  const { data } = await apiClient.post<{ items: ParseBatchItem[] }>(
    '/sql-files/parse-batch',
    { items },
  );
  return data.items;
}

export async function batchSaveSql(
  items: { id?: number; file_name?: string; full_content: string }[],
): Promise<BatchSaveResponse> {
  const { data } = await apiClient.post<BatchSaveResponse>('/sql-files/batch-save', {
    items,
  });
  return data;
}

export async function createSqlFile(
  full_content: string,
  file_name?: string,
): Promise<SqlFileDetail> {
  const { data } = await apiClient.post<SqlFileDetail>('/sql-files', {
    full_content,
    file_name,
  });
  return data;
}

export async function updateSqlFile(
  id: number,
  full_content: string,
  file_name?: string,
): Promise<SqlFileDetail> {
  const { data } = await apiClient.put<SqlFileDetail>(`/sql-files/${id}`, {
    full_content,
    file_name,
  });
  return data;
}

export async function deleteSqlFile(id: number): Promise<void> {
  await apiClient.delete(`/sql-files/${id}`);
}
