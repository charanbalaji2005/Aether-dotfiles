"""Shared plumbing for the aether CLI: system access, command execution,
logging, terminal output and confirmation prompts.

Every piece of hardware detection goes through a ``Context`` object rather
than touching ``/sys``, ``/proc`` or ``subprocess`` directly. In normal use
the context is the live system. Tests (and bug reports) can point it at a
captured fixture tree via ``AETHER_SYSROOT`` and canned command output via
``AETHER_COMMAND_FIXTURES`` — that is the only reason the indirection
exists, and neither variable is ever set by AetherOS itself.
"""

from __future__ import annotations

import json
import logging
import logging.handlers
import os
import shutil
import subprocess
import sys
from typing import Dict, Iterable, List, Optional, Sequence

__all__ = [
    "Context",
    "CommandResult",
    "default_context",
    "get_logger",
    "Output",
    "confirm",
    "state_dir",
    "config_dir",
    "parse_version",
    "version_at_least",
]


class CommandResult:
    """Outcome of running an external command.

    ``rc`` is 127 when the binary does not exist and 124 on timeout, mirroring
    the shell conventions so callers can treat every failure uniformly.
    """

    __slots__ = ("argv", "rc", "out", "err")

    def __init__(self, argv: Sequence[str], rc: int, out: str = "", err: str = ""):
        self.argv = list(argv)
        self.rc = rc
        self.out = out
        self.err = err

    @property
    def ok(self) -> bool:
        return self.rc == 0

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return "CommandResult(%r, rc=%d)" % (self.argv, self.rc)


_NT_COLON = ""  # same substitution Cygwin/MSYS use for ':' in Windows file names


def fixture_encode(rel: str) -> str:
    """Fixture trees only: PCI slot names contain ':' which Windows forbids in
    file names, so fixture trees store it as U+F03A. Never applied to the
    live system (sysroot '/')."""
    return rel.replace(":", _NT_COLON) if os.name == "nt" else rel


def fixture_decode(rel: str) -> str:
    return rel.replace(_NT_COLON, ":") if os.name == "nt" else rel


class Context:
    """Access point for everything detection code reads from the system."""

    def __init__(
        self,
        sysroot: str = "/",
        command_fixtures: Optional[Dict[str, dict]] = None,
        env: Optional[Dict[str, str]] = None,
        fixture_bins: Optional[Iterable[str]] = None,
    ):
        self.sysroot = sysroot or "/"
        self._fixtures = command_fixtures
        self._fixture_bins = set(fixture_bins or [])
        self.env = dict(os.environ if env is None else env)
        self._which_cache: Dict[str, Optional[str]] = {}
        # Commands requested while running against fixtures, so tests can
        # assert that something was (or was NOT) executed.
        self.calls: List[str] = []

    # -- filesystem -------------------------------------------------------
    @property
    def is_live(self) -> bool:
        return self.sysroot in ("", "/") and self._fixtures is None

    def path(self, p: str) -> str:
        if self.sysroot in ("", "/"):
            return p
        return os.path.join(self.sysroot, fixture_encode(p.lstrip("/")))

    def read(self, p: str, default: Optional[str] = None) -> Optional[str]:
        try:
            with open(self.path(p), "r", encoding="utf-8", errors="replace") as fh:
                return fh.read()
        except (OSError, ValueError):
            return default

    def read_bytes(self, p: str) -> Optional[bytes]:
        try:
            with open(self.path(p), "rb") as fh:
                return fh.read()
        except OSError:
            return None

    def read_line(self, p: str, default: Optional[str] = None) -> Optional[str]:
        text = self.read(p)
        if text is None:
            return default
        return text.strip()

    def read_int(self, p: str) -> Optional[int]:
        text = self.read_line(p)
        if text is None:
            return None
        try:
            return int(text, 0) if text.lower().startswith("0x") else int(text)
        except ValueError:
            return None

    def exists(self, p: str) -> bool:
        return os.path.exists(self.path(p))

    def isdir(self, p: str) -> bool:
        return os.path.isdir(self.path(p))

    def listdir(self, p: str) -> List[str]:
        try:
            return sorted(os.listdir(self.path(p)))
        except OSError:
            return []

    def readlink_base(self, p: str) -> Optional[str]:
        try:
            return os.path.basename(os.readlink(self.path(p)))
        except OSError:
            return None

    def glob(self, pattern: str) -> List[str]:
        import glob as _glob

        base = self.path("/")
        hits = _glob.glob(self.path(pattern))
        if self.sysroot in ("", "/"):
            return sorted(hits)
        # Map fixture paths back to their logical absolute form.
        out = []
        for h in hits:
            rel = os.path.relpath(h, base).replace(os.sep, "/")
            out.append("/" + fixture_decode(rel))
        return sorted(out)

    # -- commands ---------------------------------------------------------
    def which(self, name: str) -> Optional[str]:
        if self._fixtures is not None:
            return "/usr/bin/" + name if name in self._fixture_bins else None
        if name not in self._which_cache:
            self._which_cache[name] = shutil.which(name)
        return self._which_cache[name]

    def run(
        self,
        argv: Sequence[str],
        timeout: float = 15.0,
        input_text: Optional[str] = None,
    ) -> CommandResult:
        """Run a command without a shell. Never raises for ordinary failure."""
        argv = list(argv)
        if self._fixtures is not None:
            key = " ".join(argv)
            self.calls.append(key)
            if not argv or argv[0] not in self._fixture_bins:
                return CommandResult(argv, 127, "", "%s: not found" % (argv[0] if argv else ""))
            entry = self._fixtures.get(key)
            if entry is None:
                return CommandResult(argv, 1, "", "no fixture for: " + key)
            return CommandResult(argv, int(entry.get("rc", 0)), entry.get("out", ""), entry.get("err", ""))

        if not argv or self.which(argv[0]) is None and not os.path.isabs(argv[0]):
            return CommandResult(argv, 127, "", "%s: not found" % (argv[0] if argv else ""))
        try:
            proc = subprocess.run(
                argv,
                input=input_text,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout,
                text=True,
                errors="replace",
                env=self.env,
            )
        except FileNotFoundError:
            return CommandResult(argv, 127, "", "%s: not found" % argv[0])
        except subprocess.TimeoutExpired:
            return CommandResult(argv, 124, "", "timed out after %ss" % timeout)
        except OSError as exc:
            return CommandResult(argv, 126, "", str(exc))
        return CommandResult(argv, proc.returncode, proc.stdout, proc.stderr)


_DEFAULT: Optional[Context] = None


def default_context() -> Context:
    """The live system, unless a fixture root was requested for testing."""
    global _DEFAULT
    if _DEFAULT is None:
        sysroot = os.environ.get("AETHER_SYSROOT", "/")
        fixtures = None
        bins: List[str] = []
        fixture_file = os.environ.get("AETHER_COMMAND_FIXTURES")
        if fixture_file:
            with open(fixture_file, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            fixtures = data.get("commands", {})
            bins = data.get("bins", [])
        _DEFAULT = Context(sysroot=sysroot, command_fixtures=fixtures, fixture_bins=bins)
    return _DEFAULT


# -- versions -------------------------------------------------------------

def parse_version(text: Optional[str]) -> Optional[tuple]:
    """Extract the first dotted numeric version from free text."""
    if not text:
        return None
    import re

    m = re.search(r"(\d+)\.(\d+)(?:\.(\d+))?", text)
    if not m:
        m2 = re.search(r"\b(\d+)\b", text)
        return (int(m2.group(1)),) if m2 else None
    return tuple(int(g) for g in m.groups() if g is not None)


def version_at_least(version: Optional[tuple], minimum: tuple) -> Optional[bool]:
    if version is None:
        return None
    padded = tuple(version) + (0,) * (len(minimum) - len(version))
    return padded >= minimum


# -- locations ------------------------------------------------------------

def _home() -> str:
    return os.environ.get("HOME") or os.path.expanduser("~")


def state_dir() -> str:
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(_home(), ".local", "state")
    return os.path.join(base, "aether")


def config_dir() -> str:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(_home(), ".config")
    return os.path.join(base, "aether-shell")


# -- logging --------------------------------------------------------------

_LOGGER: Optional[logging.Logger] = None


def get_logger() -> logging.Logger:
    """File logger at ~/.local/state/aether/aether.log (rotated, 3x1 MiB).

    Logging failures (read-only home, etc.) degrade to a null handler — the
    CLI must keep working even when it can't write its log.
    """
    global _LOGGER
    if _LOGGER is not None:
        return _LOGGER
    logger = logging.getLogger("aether")
    logger.setLevel(logging.INFO)
    logger.propagate = False
    try:
        os.makedirs(state_dir(), exist_ok=True)
        handler: logging.Handler = logging.handlers.RotatingFileHandler(
            os.path.join(state_dir(), "aether.log"), maxBytes=1 << 20, backupCount=3, encoding="utf-8"
        )
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    except OSError:
        handler = logging.NullHandler()
    logger.addHandler(handler)
    _LOGGER = logger
    return logger


# -- terminal output ------------------------------------------------------

class Output:
    """Small helper for consistent, colour-aware terminal output."""

    def __init__(self, stream=None, color: Optional[bool] = None):
        self.stream = stream or sys.stdout
        if color is None:
            color = (
                hasattr(self.stream, "isatty")
                and self.stream.isatty()
                and "NO_COLOR" not in os.environ
                and os.environ.get("TERM") != "dumb"
            )
        self.color = bool(color)
        self.counts = {"pass": 0, "warn": 0, "fail": 0}

    def _c(self, code: str, text: str) -> str:
        return "\033[%sm%s\033[0m" % (code, text) if self.color else text

    def write(self, text: str = "") -> None:
        self.stream.write(text + "\n")

    def heading(self, text: str) -> None:
        self.write()
        self.write(self._c("1", text))

    def kv(self, key: str, value, width: int = 22) -> None:
        if value is None or value == "":
            value = self._c("2", "unavailable")
        self.write("  %s %s" % ((key + ":").ljust(width), value))

    def status(self, level: str, text: str) -> None:
        labels = {"pass": ("32", "PASS"), "warn": ("33", "WARN"), "fail": ("31", "FAIL"), "info": ("36", "INFO")}
        code, label = labels.get(level, ("0", level.upper()))
        if level in self.counts:
            self.counts[level] += 1
        self.write("  %s  %s" % (self._c(code, label), text))

    def note(self, text: str) -> None:
        for line in text.splitlines():
            self.write("        " + self._c("2", line) if line else "")

    def bullet(self, text: str) -> None:
        self.write("  - " + text)


def confirm(question: str, assume_yes: bool = False, typed: Optional[str] = None) -> bool:
    """Ask for confirmation. Non-interactive sessions default to *no*.

    When ``typed`` is set the user must type that exact word (used for
    actions that install drivers or touch boot-critical state).
    """
    if assume_yes:
        return True
    if not sys.stdin or not sys.stdin.isatty():
        sys.stdout.write("%s -> not confirmed (stdin is not a terminal; pass --yes to proceed)\n" % question)
        return False
    try:
        if typed:
            reply = input("%s Type '%s' to continue: " % (question, typed))
            return reply.strip() == typed
        reply = input("%s [y/N] " % question)
    except EOFError:
        return False
    return reply.strip().lower() in ("y", "yes")


def is_root() -> bool:
    return hasattr(os, "geteuid") and os.geteuid() == 0
