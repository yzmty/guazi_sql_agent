"""Unit tests for cross-SQL rewrite helpers."""

from app.services.cross_sql_rewrite_service import extract_target_dimension
from app.services.dimension_stats_service import dimension_matches
from app.utils.sql_join_extractor import extract_grain_hints, extract_join_fragments


SAMPLE_SQL = """
SELECT
  a.clue_id,
  b.city_name,
  COUNT(*) AS cnt
FROM dw.inspection_task a
LEFT JOIN dim.city b ON a.city_id = b.city_id
WHERE a.dt >= '2024-01-01'
GROUP BY a.clue_id, b.city_name
"""


def test_extract_target_dimension():
    assert extract_target_dimension("加上城市维度") == "城市"
    assert extract_target_dimension("增加渠道字段") == "渠道"
    assert extract_target_dimension("跨sql加门店维度") == "门店"


def test_dimension_matches():
    assert dimension_matches("城市名称", "城市")
    assert dimension_matches("dim.city_name", "city")


def test_extract_join_fragments():
    joins = extract_join_fragments(SAMPLE_SQL)
    assert len(joins) >= 1
    assert any("city" in (j.get("table") or "").lower() for j in joins)


def test_extract_grain_hints():
    hints = extract_grain_hints(SAMPLE_SQL)
    assert hints.get("group_by_fields") or hints.get("tables")
