/** Agent message and response types. */

export type AgentMode =
  | 'find_sql'
  | 'explain_sql'
  | 'recommend_similar_sql'
  | 'rewrite_sql'
  | 'cross_sql_rewrite'
  | 'generate_sql'
  | 'chat';

export interface SqlRecommendationItem {
  sql_id: number;
  file_name: string;
  reason: string;
  business?: string;
  scene?: string;
}

export interface JoinFragment {
  join_type?: string;
  table?: string;
  alias?: string;
  on_condition?: string;
  join_sql?: string;
  parser?: string;
}

export interface CrossSqlReference {
  sql_id: number;
  file_name: string;
  reason: string;
  borrowed_joins?: string[];
  join_fragments?: JoinFragment[];
  grain_comparison?: string[];
}

export interface DimensionCooccurrence {
  table: string;
  count: number;
  sql_count: number;
  ratio: number;
}

export interface DimensionFieldHint {
  field: string;
  count: number;
}

export interface FindSqlData {
  mode: 'find_sql';
  summary: string;
  results: SqlRecommendationItem[];
  llm_used?: boolean;
  semantic_used?: boolean;
}

export interface ExplainSqlData {
  mode: 'explain_sql';
  sql_id: number;
  title: string;
  summary: string;
  business_meaning: string;
  main_metrics: string[];
  main_dimensions: string[];
  core_tables: string[];
  logic_points: string[];
  filter_conditions?: string[];
  output_shape?: string;
  applicable_questions: string[];
  llm_used?: boolean;
}

export interface RecommendSimilarData {
  mode: 'recommend_similar_sql';
  source_sql_id: number;
  summary: string;
  results: SqlRecommendationItem[];
  llm_used?: boolean;
}

export interface RewriteSqlData {
  mode: 'rewrite_sql' | 'cross_sql_rewrite' | 'generate_sql';
  sql_id?: number;
  instruction: string;
  summary: string;
  changes: string[];
  risk_notes?: string[];
  rewritten_sql: string;
  is_draft?: boolean;
  warning?: string;
  llm_used?: boolean;
  semantic_used?: boolean;
  target_dimension?: string | null;
  reference_sqls?: CrossSqlReference[];
  dimension_cooccurrence?: DimensionCooccurrence[];
  dimension_field_hints?: DimensionFieldHint[];
}

export interface ChatData {
  mode: 'chat';
  summary: string;
  llm_used?: boolean;
}

export type AgentResponseData =
  | FindSqlData
  | ExplainSqlData
  | RecommendSimilarData
  | RewriteSqlData
  | ChatData;

export interface AgentChatResponse {
  success: boolean;
  mode?: AgentMode;
  data?: AgentResponseData;
  message?: string;
}

export interface AgentMessage {
  id: string;
  role: 'user' | 'assistant';
  mode?: AgentMode;
  text?: string;
  data?: AgentResponseData;
  error?: string;
  createdAt: string;
  streaming?: boolean;
}
