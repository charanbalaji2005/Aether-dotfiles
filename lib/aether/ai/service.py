"""Glue between config, keyring, providers, registry, history and audit."""

from __future__ import annotations

import json
import os
from typing import Any, Dict, Iterator, List, Optional

from .. import audit, config as config_mod
from ..redact import redact
from ..util import Context, state_dir
from . import providers, registry, secrets


def settings() -> Dict[str, Any]:
    out = dict(config_mod.defaults()["ai"])
    data, _err = config_mod.load()
    clean, _p = config_mod.validate({"ai": (data or {}).get("ai", {})})
    out.update(clean.get("ai", {}))
    return out


def history_path() -> str:
    return os.path.join(state_dir(), "ai-history.jsonl")


def status(ctx: Context, probe: bool = False) -> Dict[str, Any]:
    s = settings()
    why = providers.check_endpoint(s["endpoint"], s["localOnly"])
    key = secrets.lookup(ctx, s["provider"]) if s["provider"] == "openai" else None
    out = {"enabled": s["enabled"], "provider": s["provider"], "endpoint": s["endpoint"], "model": s["model"],
           "localOnly": s["localOnly"], "endpointProblem": why, "keyStored": bool(key),
           "keyring": secrets.available(ctx), "reachable": None, "models": []}
    if probe and why is None:
        try:
            out["models"] = providers.make(s["provider"], s["endpoint"], s["model"], key).models()
            out["reachable"] = True
        except providers.ProviderError as exc:
            out["reachable"] = False
            out["error"] = str(exc)
    return out


def _context(ctx: Context) -> str:
    from .. import capabilities
    from ..hw import system
    try:
        caps = capabilities.summary(ctx)
        mem = system.meminfo(ctx)
        parts = ["GPU: %s" % (caps["desktopGpu"]["name"] if caps.get("desktopGpu") else "unknown"),
                 "GPUs: %s" % ", ".join("%s (%s, %s)" % (g["name"], g["kind"], g["driver"]) for g in caps.get("gpus", [])),
                 "Memory: %.1f GiB" % (mem.get("MemTotal", 0) / float(1 << 30)),
                 "Visual quality recommendation: %s" % caps["tier"]]
        return "\n".join(parts)
    except Exception:  # noqa: BLE001 — context is optional
        return ""


def ask(ctx: Context, messages: List[Dict[str, str]]) -> Iterator[Dict[str, Any]]:
    """Yields {"type": "delta", "text"} … then {"type": "final", …} or {"type": "error"}."""
    s = settings()
    if not s["enabled"]:
        yield {"type": "error", "error": "The assistant is off (Settings → AI assistant)."}
        return
    why = providers.check_endpoint(s["endpoint"], s["localOnly"])
    if why:
        yield {"type": "error", "error": why}
        return
    clean = [{"role": m["role"], "content": m["content"][:8000]} for m in messages[-20:]
             if isinstance(m, dict) and m.get("role") in ("user", "assistant") and isinstance(m.get("content"), str)]
    if not clean or clean[-1]["role"] != "user":
        yield {"type": "error", "error": "no question"}
        return
    key = secrets.lookup(ctx, s["provider"]) if s["provider"] == "openai" else None
    if s["provider"] == "openai" and not key and not s["localOnly"]:
        yield {"type": "error", "error": "No API key stored for this provider (Settings → AI assistant, or `aether ai set-key`)."}
        return
    convo = [{"role": "system", "content": registry.system_prompt(_context(ctx) if s["shareSystemInfo"] else "")}] + clean
    text = ""
    try:
        for piece in providers.make(s["provider"], s["endpoint"], s["model"], key).chat(convo):
            text += piece
            yield {"type": "delta", "text": piece}
    except providers.ProviderError as exc:
        yield {"type": "error", "error": str(exc)}
        return
    visible, actions, rejected = registry.extract(text)
    audit.record("ai", "reply", {"provider": s["provider"], "model": s["model"], "proposed": [a["action"] for a in actions],
                                 "rejected": rejected})
    if s["keepHistory"]:
        _append_history(clean[-1]["content"], visible)
    yield {"type": "final", "text": visible, "actions": actions, "rejected": rejected}


def _append_history(question: str, answer: str) -> None:
    os.makedirs(state_dir(), mode=0o700, exist_ok=True)
    fd = os.open(history_path(), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(fd, "a", encoding="utf-8") as fh:
        fh.write(json.dumps({"q": redact(question), "a": redact(answer)}) + "\n")


def clear_history() -> bool:
    try:
        os.remove(history_path())
        return True
    except FileNotFoundError:
        return False
