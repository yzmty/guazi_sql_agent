/** Shared TypeScript types for SQL file API responses. */

export interface SqlFileListItem {
  id: number;
  file_name: string;
  business?: string | null;
  scene?: string | null;
  tags: string[];
  metrics: string[];
  dimensions: string[];
  core_tables: string[];
  authors: string[];
  description?: string | null;
  score?: number | null;
  index_status?: string | null;
}

export interface SqlFileDetail {
  id: number;
  file_name: string;
  file_path?: string | null;
  metrics: string[];
  business?: string | null;
  scene?: string | null;
  tags: string[];
  dimensions: string[];
  core_tables: string[];
  authors: string[];
  description?: string | null;
  sql_content?: string | null;
  comment_block?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  index_status?: string | null;
  index_error?: string | null;
  indexed_at?: string | null;
}

export interface SqlFileListResponse {
  total: number;
  list: SqlFileListItem[];
}

export interface BatchSaveResponse {
  success: boolean;
  inserted: number;
  updated: number;
  errors: string[];
}

export interface ParseBatchItem {
  file_name: string;
  valid: boolean;
  error: string | null;
  parsed: Record<string, unknown> | null;
  full_content?: string | null;
}

export interface FilterOptions {
  businesses: string[];
  authors: string[];
  tags: string[];
  core_tables: string[];
}

export interface SearchFilters {
  keyword?: string;
  business?: string;
  scene?: string;
  tag?: string;
  core_table?: string;
  author?: string;
  page?: number;
  page_size?: number;
}
