# -*- coding: utf-8 -*-
from app.services.agent_service import detect_mode
from app.services.generate_sql_service import is_generate_sql_request

assert detect_mode("\u505c\u552e\u4e1a\u52a1\u600e\u4e48\u770b", None) == "chat"
assert detect_mode("\u627c\u505c\u552e\u76f8\u5173sql", None) == "find_sql"
assert detect_mode("\u6839\u636e\u77e5\u8bc6\u5e93\u5e2e\u6211\u5199\u4e00\u6761\u505c\u552e\u5206\u6790SQL", None) == "generate_sql"
assert is_generate_sql_request("\u6839\u636e\u77e5\u8bc6\u5e93\u5e2e\u6211\u5199\u4e00\u6761\u505c\u552e\u5206\u6790SQL")
assert detect_mode("\u6539\u6210\u6700\u8fd130\u5929", 1) == "rewrite_sql"
print("all ok")
