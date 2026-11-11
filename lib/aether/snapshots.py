"""Configuration snapshots: create, verify, preview, restore, last-known-good.

A snapshot is a tar.gz of the *per-machine user state* under
~/.config/aether-shell (config.json, generated Hyprland fragments, terminal
themes, saved layouts and profiles) with a MANIFEST.json carrying a SHA-256
per file. The repository's own files are not included — git already
versions those, and `scripts/backup.sh` covers the symlinked locations.

Restoring never trusts the archive: member names are checked against an
allowlist, links/devices are refused, hashes are verified, and the current
state is snapshotted first so a restore can itself be undone.
"""

from __future__ import annotations

import difflib
import hashlib
import io
import json
import os
import re
import tarfile
import time
from typing import Any, Dict, List, Optional, Tuple

from . import config as config_mod
from .util import config_dir, state_dir

FORMAT = 1
KEEP = 12
MAX_FILE = 4 << 20  # nothing we snapshot is anywhere near 4 MiB

# component -> path prefixes relative to ~/.config/aether-shell
COMPONENTS: Dict[str, Tuple[str, ...]] = {
    "shell": ("config.json",),
    "hyprland": ("hypr/",),
    "terminal": ("terminal/",),
    "layouts": ("layouts.json",),
    "profiles": ("profiles/",),
}
_SKIP = re.compile(r"(\.bak-\d|\.tmp$|/gpu-[0-9A-Za-z-]+$)")
LABEL_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,39}$")
LKG = "last-known-good"


def snapshot_dir() -> str:
    return os.path.join(state_dir(), "snapshots")


def _component_of(rel: str) -> Optional[str]:
    for name, prefixes in COMPONENTS.items():
        for p in prefixes:
            if rel == p or (p.endswith("/") and rel.startswith(p)):
                return name
    return None


def _collect(components: Optional[List[str]]) -> List[str]:
    base = config_dir()
    wanted = set(components or COMPONENTS)
    out: List[str] = []
    for root, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
        for f in files:
            full = os.path.join(root, f)
            rel = os.path.relpath(full, base).replace(os.sep, "/")
            if os.path.islink(full) or _SKIP.search("/" + rel):
                continue
            if _component_of(rel) in wanted and os.path.getsize(full) <= MAX_FILE:
                out.append(rel)
    return sorted(out)


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def create(label: str = "manual", components: Optional[List[str]] = None) -> Optional[str]:
    """Write a snapshot; returns its path, or None when there is nothing to save."""
    if not LABEL_RE.match(label):
        raise ValueError("label must be lowercase letters, digits and '-' (max 40)")
    for c in components or []:
        if c not in COMPONENTS:
            raise ValueError("unknown component %r (choose: %s)" % (c, ", ".join(COMPONENTS)))
    files = _collect(components)
    if not files:
        return None
    base = config_dir()
    os.makedirs(snapshot_dir(), mode=0o700, exist_ok=True)
    blobs = {}
    for rel in files:
        with open(os.path.join(base, rel), "rb") as fh:
            blobs[rel] = fh.read()
    cfg, _ = config_mod.load()
    manifest = {
        "format": FORMAT,
        "created": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "label": label,
        "schemaVersion": config_mod.version_of(cfg) if cfg else config_mod.SCHEMA_VERSION,
        "files": {rel: _sha(data) for rel, data in blobs.items()},
    }
    if label == LKG:
        path = os.path.join(snapshot_dir(), LKG + ".tar.gz")
    else:
        path = os.path.join(snapshot_dir(), "%s-%s.tar.gz" % (time.strftime("%Y%m%d-%H%M%S"), label))
        n = 1
        while os.path.exists(path):  # two snapshots in the same second
            path = os.path.join(snapshot_dir(), "%s-%s-%d.tar.gz" % (time.strftime("%Y%m%d-%H%M%S"), label, n))
            n += 1
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as raw, tarfile.open(fileobj=raw, mode="w:gz") as tar:
        def add(name: str, data: bytes) -> None:
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = len(data), 0o600, int(time.time())
            tar.addfile(info, io.BytesIO(data))
        add("MANIFEST.json", json.dumps(manifest, indent=2).encode("utf-8"))
        for rel, data in blobs.items():
            add(rel, data)
    os.replace(tmp, path)
    _prune()
    return path


def _prune() -> None:
    try:
        names = sorted(f for f in os.listdir(snapshot_dir()) if f.endswith(".tar.gz") and f != LKG + ".tar.gz")
    except OSError:
        return
    for old in names[:-KEEP]:
        try:
            os.remove(os.path.join(snapshot_dir(), old))
        except OSError:
            pass


def _read(path: str) -> Tuple[Optional[Dict[str, Any]], Dict[str, bytes], List[str]]:
    """Return (manifest, {rel: bytes}, problems) without writing anything."""
    problems: List[str] = []
    blobs: Dict[str, bytes] = {}
    manifest = None
    try:
        with tarfile.open(path, "r:gz") as tar:
            for member in tar:
                name = member.name
                if not member.isfile():
                    problems.append("%s: not a regular file (links and devices are refused)" % name)
                    continue
                if name.startswith("/") or ".." in name.split("/") or "\\" in name or member.size > MAX_FILE:
                    problems.append("%s: unsafe path or oversized member" % name)
                    continue
                fh = tar.extractfile(member)
                data = fh.read() if fh else b""
                if name == "MANIFEST.json":
                    try:
                        manifest = json.loads(data.decode("utf-8"))
                    except ValueError:
                        problems.append("MANIFEST.json is not valid JSON")
                elif _component_of(name) is None:
                    problems.append("%s: not a path AetherOS snapshots (refused)" % name)
                else:
                    blobs[name] = data
    except (tarfile.TarError, OSError, EOFError) as exc:
        return None, {}, ["cannot read archive: %s" % exc]
    if not isinstance(manifest, dict) or not isinstance(manifest.get("files"), dict):
        problems.append("missing or malformed MANIFEST.json")
        return None, blobs, problems
    if manifest.get("format") != FORMAT:
        problems.append("snapshot format %r is not supported (expected %d)" % (manifest.get("format"), FORMAT))
    for rel, digest in manifest["files"].items():
        if rel not in blobs:
            problems.append("%s: listed in the manifest but missing" % rel)
        elif _sha(blobs[rel]) != digest:
            problems.append("%s: checksum mismatch (archive is corrupt or was modified)" % rel)
    for rel in blobs:
        if rel not in manifest["files"]:
            problems.append("%s: present but not in the manifest" % rel)
    ver = manifest.get("schemaVersion")
    if isinstance(ver, int) and ver > config_mod.SCHEMA_VERSION:
        problems.append("snapshot is from a newer AetherOS (config version %d > %d)" % (ver, config_mod.SCHEMA_VERSION))
    return manifest, blobs, problems


def verify(path: str) -> Tuple[bool, List[str]]:
    _m, _b, problems = _read(path)
    return not problems, problems


def listing() -> List[Dict[str, Any]]:
    out = []
    try:
        names = sorted(f for f in os.listdir(snapshot_dir()) if f.endswith(".tar.gz"))
    except OSError:
        return out
    for name in names:
        full = os.path.join(snapshot_dir(), name)
        manifest, _b, problems = _read(full)
        out.append({
            "name": name[:-7], "path": full, "size": os.path.getsize(full),
            "created": (manifest or {}).get("created"), "label": (manifest or {}).get("label"),
            "files": len((manifest or {}).get("files", {})), "valid": not problems,
            "lastKnownGood": name == LKG + ".tar.gz",
        })
    out.sort(key=lambda s: s["created"] or "", reverse=True)
    return out


def resolve(name: str) -> Optional[str]:
    """Accept a path, a snapshot name, 'latest' or 'last-known-good'."""
    if os.path.isfile(name):
        return name
    snaps = listing()
    if name == "latest":
        rest = [s for s in snaps if not s["lastKnownGood"]]
        return rest[0]["path"] if rest else None
    for s in snaps:
        if s["name"] == name:
            return s["path"]
    return None


def preview(path: str, components: Optional[List[str]] = None) -> Dict[str, Any]:
    """What a restore would change, including text diffs."""
    manifest, blobs, problems = _read(path)
    base = config_dir()
    wanted = set(components or COMPONENTS)
    changes = []
    for rel in sorted(blobs):
        if _component_of(rel) not in wanted:
            continue
        cur_path = os.path.join(base, rel)
        try:
            with open(cur_path, "rb") as fh:
                cur = fh.read()
        except OSError:
            cur = None
        if cur == blobs[rel]:
            continue
        entry: Dict[str, Any] = {"path": rel, "change": "create" if cur is None else "modify"}
        try:
            old = (cur or b"").decode("utf-8").splitlines(True)
            new = blobs[rel].decode("utf-8").splitlines(True)
            entry["diff"] = "".join(difflib.unified_diff(old, new, "current/" + rel, "snapshot/" + rel))
        except UnicodeDecodeError:
            entry["diff"] = "(binary)"
        changes.append(entry)
    return {"valid": not problems, "problems": problems, "changes": changes,
            "created": (manifest or {}).get("created"), "label": (manifest or {}).get("label")}


def restore(path: str, components: Optional[List[str]] = None) -> Dict[str, Any]:
    """Restore a verified snapshot. The current state is snapshotted first."""
    manifest, blobs, problems = _read(path)
    if problems:
        return {"ok": False, "problems": problems}
    wanted = set(components or COMPONENTS)
    if "config.json" in blobs and "shell" in wanted:
        try:
            data = json.loads(blobs["config.json"].decode("utf-8"))
            data, _notes = config_mod.migrate(data)
            data, cfg_problems = config_mod.validate(data)
        except (ValueError, UnicodeDecodeError) as exc:
            return {"ok": False, "problems": ["config.json in the snapshot is unusable: %s" % exc]}
        blobs["config.json"] = (json.dumps(data, indent=4, ensure_ascii=False) + "\n").encode("utf-8")
    else:
        cfg_problems = []
    undo = create("pre-restore")
    base = config_dir()
    restored: List[str] = []
    for rel, data in blobs.items():
        if _component_of(rel) not in wanted:
            continue
        dest = os.path.join(base, rel)
        # Belt and braces: the resolved destination must stay inside base.
        if os.path.commonpath([os.path.realpath(base), os.path.realpath(os.path.dirname(dest))]) != os.path.realpath(base):
            continue
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        tmp = dest + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, dest)
        restored.append(rel)
    return {"ok": True, "restored": sorted(restored), "undo": undo, "notes": cfg_problems}
