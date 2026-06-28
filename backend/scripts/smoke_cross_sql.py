# -*- coding: utf-8 -*-
from app.services.agent_service import is_cross_sql_rewrite_request
from app.services.cross_sql_rewrite_service import extract_target_dimension

assert extract_target_dimension("\u52a0\u4e0a\u57ce\u5e02\u7ef4\u5ea6") == "\u57ce\u5e02"
assert extract_target_dimension("\u589e\u52a0\u6e20\u9053\u5b57\u6bb5") == "\u6e20\u9053"
assert is_cross_sql_rewrite_request("\u52a0\u4e0a\u57ce\u5e02\u7ef4\u5ea6", 1) is True
assert is_cross_sql_rewrite_request("\u6539\u6210\u6700\u8fd130\u5929", 1) is False
print("all ok")
