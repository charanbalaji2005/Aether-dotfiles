"""Chat providers over HTTP (standard library only).

* ollama — POST {endpoint}/api/chat, NDJSON stream; GET /api/tags
* openai — any OpenAI-compatible server: POST {endpoint}/v1/chat/completions
  with SSE streaming; GET /v1/models (OpenAI, vLLM, llama.cpp server,
  LM Studio, LocalAI, OpenRouter, …)

`local_only` (the default) refuses endpoints that aren't loopback, so with it
on, nothing you type leaves the machine.
"""

from __future__ import annotations

import ipaddress
import json
import socket
import urllib.error
import urllib.parse
import urllib.request
from typing import Dict, Iterator, List, Optional


class ProviderError(Exception):
    pass


def check_endpoint(url: str, local_only: bool) -> Optional[str]:
    """None if acceptable, else why not."""
    try:
        p = urllib.parse.urlsplit(url)
    except ValueError:
        return "not a URL"
    if p.scheme not in ("http", "https") or not p.hostname:
        return "the endpoint must be an http(s) URL"
    if p.username or p.password:
        return "credentials don't belong in the URL (use `aether ai set-key`)"
    if local_only:
        host = p.hostname
        if host == "localhost":
            return None
        try:
            if ipaddress.ip_address(host).is_loopback:
                return None
        except ValueError:
            pass
        return "local-only mode is on: %s is not this machine (turn it off in Settings → AI to use a remote provider)" % host
    if p.scheme == "http" and p.hostname not in ("localhost",) and not _is_loopback(p.hostname):
        return "remote endpoints must use https (your messages and key would travel unencrypted)"
    return None


def _is_loopback(host: str) -> bool:
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


class Provider:
    name = "base"

    def __init__(self, endpoint: str, model: str, api_key: Optional[str] = None, timeout: float = 120.0):
        self.endpoint = endpoint.rstrip("/")
        self.model = model
        self.api_key = api_key
        self.timeout = timeout

    def _request(self, path: str, body: Optional[dict] = None):
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        if self.api_key:
            headers["Authorization"] = "Bearer " + self.api_key
        data = json.dumps(body).encode("utf-8") if body is not None else None
        req = urllib.request.Request(self.endpoint + path, data=data, headers=headers, method="POST" if body is not None else "GET")
        try:
            return urllib.request.urlopen(req, timeout=self.timeout)
        except urllib.error.HTTPError as exc:
            detail = exc.read(300).decode("utf-8", "replace") if hasattr(exc, "read") else ""
            raise ProviderError("HTTP %d from %s: %s" % (exc.code, self.name, detail.strip()[:200]))
        except (urllib.error.URLError, socket.timeout, OSError) as exc:
            raise ProviderError("can't reach %s at %s (%s)" % (self.name, self.endpoint, getattr(exc, "reason", exc)))

    def models(self) -> List[str]:
        raise NotImplementedError

    def chat(self, messages: List[Dict[str, str]]) -> Iterator[str]:
        raise NotImplementedError


class Ollama(Provider):
    name = "ollama"

    def models(self) -> List[str]:
        with self._request("/api/tags") as r:
            data = json.loads(r.read().decode("utf-8"))
        return [m.get("name", "") for m in data.get("models", []) if m.get("name")]

    def chat(self, messages: List[Dict[str, str]]) -> Iterator[str]:
        with self._request("/api/chat", {"model": self.model, "messages": messages, "stream": True}) as r:
            for raw in r:
                line = raw.decode("utf-8", "replace").strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except ValueError:
                    continue
                if obj.get("error"):
                    raise ProviderError("ollama: %s" % obj["error"])
                piece = (obj.get("message") or {}).get("content") or ""
                if piece:
                    yield piece
                if obj.get("done"):
                    return


class OpenAICompatible(Provider):
    name = "openai"

    def _base(self) -> str:
        return "" if self.endpoint.endswith("/v1") else "/v1"

    def models(self) -> List[str]:
        with self._request(self._base() + "/models") as r:
            data = json.loads(r.read().decode("utf-8"))
        return sorted(m.get("id", "") for m in data.get("data", []) if m.get("id"))

    def chat(self, messages: List[Dict[str, str]]) -> Iterator[str]:
        with self._request(self._base() + "/chat/completions", {"model": self.model, "messages": messages, "stream": True}) as r:
            for raw in r:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                payload = line[5:].strip()
                if payload == "[DONE]":
                    return
                try:
                    obj = json.loads(payload)
                except ValueError:
                    continue
                if obj.get("error"):
                    raise ProviderError("provider error: %s" % (obj["error"].get("message") if isinstance(obj["error"], dict) else obj["error"]))
                choices = obj.get("choices") or []
                piece = (choices[0].get("delta") or {}).get("content") if choices else None
                if piece:
                    yield piece


PROVIDERS = {"ollama": Ollama, "openai": OpenAICompatible}


def make(name: str, endpoint: str, model: str, api_key: Optional[str]) -> Provider:
    if name not in PROVIDERS:
        raise ProviderError("unknown provider %r (choose: %s)" % (name, ", ".join(PROVIDERS)))
    return PROVIDERS[name](endpoint, model, api_key)
