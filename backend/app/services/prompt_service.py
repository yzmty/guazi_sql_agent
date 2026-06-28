"""Prompt builders for Agent modes — keep prompts out of API layer."""

import json


def _json(data: dict | list) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2)


SYSTEM_PROMPT = """你是瓜子二手车商业分析团队的 SQL 知识库助手。
你只能基于用户提供的 SQL 元数据和 SQL 正文回答，不要编造不存在的表、字段或业务逻辑。
如果信息不足，请明确说明不确定。
输出必须是合法 JSON，不要包含 markdown 代码块或其他多余文字。
对业务解释请使用商业分析语境，面向数据分析师而非 DBA。
改写 SQL 时绝对不能建议修改原始文件，输出的是草稿版本。"""


def build_find_sql_prompt(question: str, candidates: list[dict]) -> str:
    return f"""{SYSTEM_PROMPT}

## 任务
用户在 SQL 知识库中搜索相关 SQL。请从候选列表中选出最相关的 SQL（最多 5 条），并给出推荐理由。

## 用户问题
{question}

## 候选 SQL 列表
{_json(candidates)}

## 输出 JSON 格式
{{
  "mode": "find_sql",
  "summary": "一段总结，说明找到了哪些类型的 SQL",
  "results": [
    {{
      "sql_id": 1,
      "file_name": "文件名.sql",
      "reason": "推荐理由，结合业务场景说明"
    }}
  ]
}}"""


def build_explain_sql_prompt(sql_record: dict) -> str:
    return f"""{SYSTEM_PROMPT}

## 任务
请结构化解释以下 SQL，帮助商业分析师理解其用途和分析场景。

## SQL 元数据与正文
{_json(sql_record)}

## 输出 JSON 格式
{{
  "mode": "explain_sql",
  "sql_id": {sql_record.get("id", 0)},
  "title": "文件名",
  "summary": "一句话总结",
  "business_meaning": "业务含义",
  "main_metrics": ["指标1", "指标2"],
  "main_dimensions": ["维度1"],
  "core_tables": ["表1"],
  "logic_points": ["关键逻辑点1"],
  "filter_conditions": ["主要过滤条件"],
  "output_shape": "输出结果大概长什么样",
  "applicable_questions": ["适合回答的业务问题1"]
}}"""


def build_recommend_sql_prompt(source_sql: dict, candidates: list[dict]) -> str:
    return f"""{SYSTEM_PROMPT}

## 任务
基于当前 SQL，从候选列表中推荐最相似的 SQL（最多 5 条），重新排序并说明相似原因。

## 当前 SQL
{_json(source_sql)}

## 候选相似 SQL
{_json(candidates)}

## 输出 JSON 格式
{{
  "mode": "recommend_similar_sql",
  "source_sql_id": {source_sql.get("id", 0)},
  "summary": "一段总结",
  "results": [
    {{
      "sql_id": 2,
      "file_name": "文件名.sql",
      "reason": "相似原因，如相同业务/场景/核心表/指标"
    }}
  ]
}}"""


def build_rewrite_sql_prompt(sql_record: dict, instruction: str) -> str:
    return f"""{SYSTEM_PROMPT}

## 任务
根据用户指令改写 SQL。**这是草稿，不会覆盖原始文件。**
要求：
1. 尽量保留原 SQL 结构
2. 不要编造不存在的字段；信息不足时可保守修改并给出风险提示
3. rewritten_sql 必须是完整可读的 SQL 文本

## 当前 SQL 元数据与正文
{_json(sql_record)}

## 用户改写指令
{instruction}

## 输出 JSON 格式
{{
  "mode": "rewrite_sql",
  "sql_id": {sql_record.get("id", 0)},
  "instruction": "{instruction}",
  "summary": "改写总结",
  "changes": ["改动说明1"],
  "risk_notes": ["风险提示，如有"],
  "rewritten_sql": "完整改写后的 SQL"
}}"""


def build_cross_sql_rewrite_prompt(
    source_sql: dict,
    instruction: str,
    target_dimension: str | None,
    candidate_sqls: list[dict],
    dimension_cooccurrence: list[dict],
    dimension_field_hints: list[dict],
) -> str:
    dim_label = target_dimension or "（从指令推断）"
    return f"""{SYSTEM_PROMPT}

## 任务
用户要在**当前 SQL** 上增加维度「{dim_label}」。请从知识库中**其他 SQL** 借鉴 JOIN 路径与字段用法，合并生成改写草稿。
**这是草稿，不会覆盖原始文件。**

## 要求
1. 优先复用「候选 SQL」中已验证的 JOIN 片段（join_fragments），不要凭空编造表名
2. 结合「维度共现统计」选择最可信的表；共现 count 越高越优先
3. 对比 source 与 candidate 的 grain_hints（GROUP BY / SELECT），在 risk_notes 中说明粒度风险
4. 每个借鉴来源必须在 reference_sqls 中标注 sql_id 和 file_name
5. rewritten_sql 必须是完整可执行的 SQL 文本
6. 若无法安全合并，保守修改并在 risk_notes 说明原因

## 当前 SQL（待改写）
{_json(source_sql)}

## 用户指令
{instruction}

## 目标维度
{dim_label}

## 语义检索候选 SQL（含 JOIN 片段与粒度对比）
{_json(candidate_sqls)}

## 库内维度-表共现统计（该维度在哪些表最常出现）
{_json(dimension_cooccurrence)}

## 库内维度字段提示（SQL 正文中与该维度相关的字段 token）
{_json(dimension_field_hints)}

## 输出 JSON 格式
{{
  "mode": "cross_sql_rewrite",
  "sql_id": {source_sql.get("id", 0)},
  "instruction": "{instruction}",
  "target_dimension": "{target_dimension or ""}",
  "summary": "跨 SQL 改写总结，说明借鉴了哪些 SQL",
  "changes": ["改动说明1，注明借鉴来源"],
  "risk_notes": ["粒度/JOIN 风险提示"],
  "reference_sqls": [
    {{
      "sql_id": 12,
      "file_name": "xxx.sql",
      "reason": "借鉴原因",
      "borrowed_joins": ["JOIN ... ON ..."]
    }}
  ],
  "rewritten_sql": "完整合并后的 SQL"
}}"""


def build_generate_sql_prompt(instruction: str, reference_sqls: list[dict]) -> str:
    return f"""{SYSTEM_PROMPT}

## 任务
用户希望**基于知识库中已有 SQL** 合成一条**全新的 SQL 草稿**（不是从候选里原样复制）。
**这是草稿，不会自动写入知识库。**

## 要求
1. 从「参考 SQL」中学习表名、JOIN 路径、字段命名、过滤习惯，组合成满足用户需求的 SQL
2. 不要凭空编造参考 SQL 中从未出现过的表；字段尽量来自参考 SQL 正文
3. 在 reference_sqls 中标注借鉴了哪些 sql_id / file_name，以及借用了什么（表/JOIN/逻辑）
4. rewritten_sql 必须是完整可读的 SQL 文本
5. 在 risk_notes 中说明口径不确定或需人工确认的点
6. 若参考 SQL 不足以支撑需求，保守生成并在 risk_notes 明确说明缺失信息

## 用户需求
{instruction}

## 知识库参考 SQL（含 JOIN 片段与 SQL 预览）
{_json(reference_sqls)}

## 输出 JSON 格式
{{
  "mode": "generate_sql",
  "instruction": "{instruction}",
  "summary": "合成总结，说明新 SQL 的业务目的与借鉴来源",
  "changes": ["新 SQL 相对参考 SQL 的组合说明"],
  "risk_notes": ["口径/JOIN/字段不确定点"],
  "reference_sqls": [
    {{
      "sql_id": 12,
      "file_name": "xxx.sql",
      "reason": "借鉴原因",
      "borrowed_joins": ["JOIN ... ON ..."]
    }}
  ],
  "rewritten_sql": "完整合成后的 SQL"
}}"""
