"""API keys in the desktop keyring (freedesktop Secret Service — GNOME
Keyring or KWallet), through libsecret's `secret-tool`.

Keys are passed on stdin (never argv: argv is visible in `ps`), never written
to config.json, logs or the audit trail. If no keyring is available, the
only other source is the AETHER_AI_API_KEY environment variable — documented
for headless use, never persisted by AetherOS.
"""

from __future__ import annotations

import re
from typing import Optional

from ..util import Context

SERVICE = "aetheros-ai"
PROVIDER_RE = re.compile(r"^[a-z0-9-]{1,32}$")


def available(ctx: Context) -> bool:
    return ctx.which("secret-tool") is not None


def store(ctx: Context, provider: str, key: str) -> Optional[str]:
    """Returns an error message, or None on success."""
    if not PROVIDER_RE.match(provider):
        return "bad provider name"
    key = key.strip()
    if not key or len(key) > 4096 or any(c in key for c in "\n\r\x00"):
        return "the key is empty or malformed"
    if not available(ctx):
        return "secret-tool not found (sudo dnf install libsecret) — or set AETHER_AI_API_KEY for this session"
    res = ctx.run(["secret-tool", "store", "--label=AetherOS assistant (%s)" % provider, "service", SERVICE, "provider", provider],
                  timeout=30, input_text=key)
    return None if res.ok else ("the keyring refused the key: %s" % (res.err or "").strip()[:200])


def lookup(ctx: Context, provider: str) -> Optional[str]:
    env = ctx.env.get("AETHER_AI_API_KEY")
    if env:
        return env.strip()
    if not PROVIDER_RE.match(provider) or not available(ctx):
        return None
    res = ctx.run(["secret-tool", "lookup", "service", SERVICE, "provider", provider], timeout=15)
    return res.out.strip() if res.ok and res.out.strip() else None


def clear(ctx: Context, provider: str) -> bool:
    if not PROVIDER_RE.match(provider) or not available(ctx):
        return False
    return ctx.run(["secret-tool", "clear", "service", SERVICE, "provider", provider], timeout=15).ok
