"""Unified LLM client — OpenAI-compatible (DeepSeek / OpenAI)."""

import json
import logging
import re

import httpx

from app.config import LLM_API_KEY, LLM_BASE_URL, LLM_MODEL, LLM_TIMEOUT

logger = logging.getLogger(__name__)


class LlmError(Exception):
    """Raised when LLM call fails."""


class LlmNotConfiguredError(LlmError):
    """Raised when LLM API key is missing."""


def is_llm_configured() -> bool:
    key = (LLM_API_KEY or "").strip()
    return bool(key) and key not in ("your-api-key-here", "sk-your-key", "changeme")


def probe_llm() -> dict:
    """Lightweight connectivity check for /api/health."""
    if not is_llm_configured():
        return {"ok": False, "error": "LLM_API_KEY not configured"}
    try:
        chat_json('Return JSON: {"ok": true}', system="You output JSON only")
        return {"ok": True, "error": None}
    except LlmError as exc:
        return {"ok": False, "error": str(exc)[:300]}
    except Exception as exc:
        return {"ok": False, "error": str(exc)[:300]}


def _extract_json(text: str) -> dict:
    """Parse JSON from model response, tolerating markdown fences."""
    text = text.strip()
    if not text:
        raise LlmError("模型返回为空")

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    fence_match = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
    if fence_match:
        try:
            return json.loads(fence_match.group(1).strip())
        except json.JSONDecodeError:
            pass

    brace_match = re.search(r"\{[\s\S]*\}", text)
    if brace_match:
        try:
            return json.loads(brace_match.group(0))
        except json.JSONDecodeError as exc:
            raise LlmError(f"JSON 解析失败: {exc}") from exc

    raise LlmError("无法从模型响应中解析 JSON")


def _post_chat(payload: dict) -> dict:
    url = f"{LLM_BASE_URL.rstrip('/')}/chat/completions"
    headers = {
        "Authorization": f"Bearer {LLM_API_KEY}",
        "Content-Type": "application/json",
    }
    with httpx.Client(timeout=LLM_TIMEOUT) as client:
        response = client.post(url, headers=headers, json=payload)
        response.raise_for_status()
        return response.json()


def chat_json(prompt: str, system: str | None = None) -> dict:
    """
    Call OpenAI-compatible chat completions and parse JSON response.
    DeepSeek: uses deepseek-chat by default; retries without response_format if unsupported.
    """
    if not is_llm_configured():
        raise LlmNotConfiguredError(
            "未配置 LLM API Key。请在 backend/.env 设置 LLM_API_KEY（DeepSeek 免费 Key 见 https://platform.deepseek.com）"
        )

    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})

    base_payload = {
        "model": LLM_MODEL,
        "messages": messages,
        "temperature": 0.2,
    }

    payloads = [
        {**base_payload, "response_format": {"type": "json_object"}},
        base_payload,
    ]

    last_error: Exception | None = None
    for payload in payloads:
        try:
            data = _post_chat(payload)
            content = data["choices"][0]["message"]["content"]
            return _extract_json(content)
        except httpx.TimeoutException as exc:
            raise LlmError(f"LLM 请求超时（{LLM_TIMEOUT}s）") from exc
        except httpx.HTTPStatusError as exc:
            last_error = exc
            # Retry without response_format on 400
            if exc.response.status_code == 400 and "response_format" in payload:
                logger.info("Retrying LLM without response_format")
                continue
            detail = exc.response.text[:400]
            raise LlmError(f"LLM API 错误 {exc.response.status_code}: {detail}") from exc
        except httpx.RequestError as exc:
            raise LlmError(f"LLM 网络错误: {exc}") from exc
        except (KeyError, IndexError, TypeError) as exc:
            raise LlmError("LLM 响应格式异常") from exc
        except LlmError:
            raise

    if last_error:
        detail = last_error.response.text[:400]
        raise LlmError(f"LLM API 错误: {detail}") from last_error
    raise LlmError("LLM 调用失败")


def chat_messages(messages: list[dict[str, str]], temperature: float = 0.2) -> str:
    """Multi-turn chat via OpenAI-compatible API."""
    if not is_llm_configured():
        raise LlmNotConfiguredError(
            "未配置 LLM API Key。请在 backend/.env 设置 LLM_API_KEY"
        )
    payload = {
        "model": LLM_MODEL,
        "messages": messages,
        "temperature": temperature,
    }
    try:
        data = _post_chat(payload)
        content = data["choices"][0]["message"]["content"]
        return content if isinstance(content, str) else str(content)
    except httpx.TimeoutException as exc:
        raise LlmError(f"LLM 请求超时（{LLM_TIMEOUT}s）") from exc
    except httpx.HTTPStatusError as exc:
        detail = exc.response.text[:400]
        raise LlmError(f"LLM API 错误 {exc.response.status_code}: {detail}") from exc
    except httpx.RequestError as exc:
        raise LlmError(f"LLM 网络错误: {exc}") from exc
    except (KeyError, IndexError, TypeError) as exc:
        raise LlmError("LLM 响应格式异常") from exc


def chat_messages_stream(messages: list[dict[str, str]], temperature: float = 0.2):
    """Stream chat tokens via SSE from OpenAI-compatible API."""
    if not is_llm_configured():
        raise LlmNotConfiguredError("未配置 LLM API Key")
    url = f"{LLM_BASE_URL.rstrip('/')}/chat/completions"
    headers = {
        "Authorization": f"Bearer {LLM_API_KEY}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": LLM_MODEL,
        "messages": messages,
        "temperature": temperature,
        "stream": True,
    }
    with httpx.Client(timeout=LLM_TIMEOUT) as client:
        with client.stream("POST", url, headers=headers, json=payload) as resp:
            resp.raise_for_status()
            for line in resp.iter_lines():
                if not line or not line.startswith("data:"):
                    continue
                chunk = line[5:].strip()
                if chunk == "[DONE]":
                    break
                try:
                    data = json.loads(chunk)
                    delta = data["choices"][0].get("delta", {})
                    text = delta.get("content")
                    if text:
                        yield text
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue
