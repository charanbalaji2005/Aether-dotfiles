"""Secret redaction for anything written to logs, the audit trail or a
diagnostics report. Conservative: it prefers redacting a harmless value to
leaking a credential."""

from __future__ import annotations

import logging
import re
from typing import Any

_PATTERNS = [
    (re.compile(r"\b(sk|rk|pk)-[A-Za-z0-9_-]{16,}"), r"\1-[REDACTED]"),                 # OpenAI-style keys
    (re.compile(r"\b(gh[pousr]_)[A-Za-z0-9]{20,}"), r"\1[REDACTED]"),                    # GitHub tokens
    (re.compile(r"\bxox[abpr]-[A-Za-z0-9-]{10,}"), "xox-[REDACTED]"),                    # Slack
    (re.compile(r"(?i)\b(bearer)\s+[A-Za-z0-9._~+/=-]{8,}"), r"\1 [REDACTED]"),
    (re.compile(r"(?i)\b(authorization)\s*[:=]\s*\S+"), r"\1: [REDACTED]"),
    (re.compile(r"(?i)\b(api[_-]?key|access[_-]?token|secret|password|passwd|psk)([\"']?\s*[:=]\s*[\"']?)[^\s\"',;]+"), r"\1\2[REDACTED]"),
    (re.compile(r"(?i)(https?://)[^/\s:@]+:[^/\s@]+@"), r"\1[REDACTED]@"),               # credentials in URLs
]


def redact(value: Any) -> Any:
    """Redact strings, recursively inside lists/dicts (keys named like
    secrets have their whole value replaced)."""
    if isinstance(value, str):
        out = value
        for pat, rep in _PATTERNS:
            out = pat.sub(rep, out)
        return out
    if isinstance(value, dict):
        return {k: ("[REDACTED]" if isinstance(k, str) and re.search(r"(?i)key|token|secret|password|psk", k) and v else redact(v))
                for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [redact(v) for v in value]
    return value


class RedactingFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        try:
            msg = record.getMessage()
        except Exception:  # noqa: BLE001
            return True
        record.msg, record.args = redact(msg), None
        return True
