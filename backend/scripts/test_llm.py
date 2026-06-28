from app.services.llm_service import chat_json, is_llm_configured
from app.config import LLM_BASE_URL, LLM_MODEL

print("configured:", is_llm_configured())
print("base_url:", LLM_BASE_URL)
print("model:", LLM_MODEL)
try:
    result = chat_json('Return JSON: {"ok": true}', system="You output JSON only")
    print("success:", result)
except Exception as exc:
    print("FAIL:", type(exc).__name__, exc)
