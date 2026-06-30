import { apiClient } from './client';
import type { FilterOptions, SqlFileDetail, SqlFileListItem } from '../types/sqlFile';

export type LibraryScope = 'personal' | 'shared';

export interface SharedGroupStatus {
  group_id: number;
  group_name: string;
  owner_email: string;
  is_owner: boolean;
  status: string | null;
  role: string | null;
  can_access: boolean;
}

export interface SharedGroupMember {
  id: number;
  email: string;
  role: string;
  status: string;
  created_at?: string | null;
  approved_at?: string | null;
}

export interface SharedSqlListResponse {
  total: number;
  list: SqlFileListItem[];
}

export async function getSharedGroupStatus(): Promise<SharedGroupStatus> {
  const { data } = await apiClient.get<SharedGroupStatus>('/shared-group/status');
  return data;
}

export async function joinSharedGroup(): Promise<SharedGroupStatus> {
  const { data } = await apiClient.post<SharedGroupStatus>('/shared-group/join');
  return data;
}

export async function listSharedGroupMembers(status?: string): Promise<SharedGroupMember[]> {
  const { data } = await apiClient.get<{ items: SharedGroupMember[] }>('/shared-group/members', {
    params: status ? { status } : undefined,
  });
  return data.items;
}

export async function approveSharedMember(email: string): Promise<SharedGroupMember> {
  const { data } = await apiClient.post<SharedGroupMember>('/shared-group/members/approve', {
    email,
  });
  return data;
}

export async function removeSharedMember(email: string): Promise<void> {
  await apiClient.post('/shared-group/members/remove', { email });
}

export async function getSharedFilterOptions(): Promise<FilterOptions> {
  const { data } = await apiClient.get<FilterOptions>('/shared-group/sql-files/filter-options');
  return data;
}

export async function listSharedSqlFiles(params?: {
  keyword?: string;
  business?: string;
  scene?: string;
  tag?: string;
  core_table?: string;
  author?: string;
  page?: number;
  page_size?: number;
}): Promise<SharedSqlListResponse> {
  const { data } = await apiClient.get<SharedSqlListResponse>('/shared-group/sql-files', {
    params,
  });
  return data;
}

export async function getSharedSqlDetail(id: number): Promise<SqlFileDetail & { storage_mode?: string; uploaded_by?: string; scope?: string }> {
  const { data } = await apiClient.get(`/shared-group/sql-files/${id}`);
  return data;
}

export async function deleteSharedSql(id: number): Promise<void> {
  await apiClient.delete(`/shared-group/sql-files/${id}`);
}

export async function batchSaveSharedSql(
  items: Array<{
    file_name?: string;
    full_content: string;
    storage_mode?: 'public' | 'encrypted';
    is_public?: boolean;
  }>,
): Promise<{ success: boolean; inserted: number; updated: number; errors: string[] }> {
  const { data } = await apiClient.post('/shared-group/sql-files/batch-save', { items });
  return data;
}
