"""Audit trail of actions taken on the user's behalf: AI-proposed actions the
user confirmed, automation runs, imports, restores, display changes.
JSON lines in ~/.local/state/aether/audit.log (0600, rotated at 1 MiB, 3
kept). Values are redacted before writing; nothing leaves the machine."""

from __future__ import annotations

import json
import os
import time
from typing import Any, Dict, List

from .redact import redact
from .util import state_dir

MAX = 1 << 20
KEEP = 3


def path() -> str:
    return os.path.join(state_dir(), "audit.log")


def _rotate() -> None:
    p = path()
    try:
        if os.path.getsize(p) < MAX:
            return
    except OSError:
        return
    for i in range(KEEP - 1, 0, -1):
        src, dst = "%s.%d" % (p, i), "%s.%d" % (p, i + 1)
        if os.path.exists(src):
            os.replace(src, dst)
    os.replace(p, p + ".1")


def record(actor: str, action: str, args: Any = None, result: str = "ok", detail: str = "") -> None:
    try:
        os.makedirs(state_dir(), mode=0o700, exist_ok=True)
        _rotate()
        entry = {"time": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "actor": actor, "action": action,
                 "args": redact(args), "result": result, "detail": redact(detail)}
        fd = os.open(path(), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(fd, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        pass  # auditing must never break the action itself


def tail(n: int = 50) -> List[Dict[str, Any]]:
    try:
        with open(path(), encoding="utf-8") as fh:
            lines = fh.readlines()[-n:]
    except OSError:
        return []
    out = []
    for l in lines:
        try:
            out.append(json.loads(l))
        except ValueError:
            continue
    return out
