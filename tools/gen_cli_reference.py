#!/usr/bin/python3
"""Writes docs/CLI_REFERENCE.md from the `aether` argument parser itself,
so the reference can't drift from the code.

    python3 tools/gen_cli_reference.py          rewrite the file
    python3 tools/gen_cli_reference.py --check  exit 1 if it is out of date (CI)
"""
import argparse
import os as _os
_os.environ["COLUMNS"] = "100"  # argparse wraps to the terminal: pin it so the output is reproducible
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "lib"))
from aether import __version__  # noqa: E402
from aether.cli import build_parser  # noqa: E402

OUT = os.path.join(REPO, "docs", "CLI_REFERENCE.md")


def _subparsers(p):
    for a in p._actions:
        if isinstance(a, argparse._SubParsersAction):
            helps = {c.dest: c.help for c in a._choices_actions}
            return [(name, sp, helps.get(name) or "") for name, sp in a.choices.items()]
    return []


def _usage(p):
    return p.format_usage().replace("usage: ", "").strip()


def render():
    root = build_parser()
    out = ["# `aether` command reference", "",
           "Generated from the CLI's own argument parser by `tools/gen_cli_reference.py` (AetherOS %s)." % __version__,
           "Every command supports `--json` where it reports data, never needs root, and logs to",
           "`~/.local/state/aether/aether.log` (secrets redacted).", ""]
    cmds = sorted(_subparsers(root), key=lambda x: x[0])
    out.append("| Command | Purpose |")
    out.append("|---|---|")
    for name, _sp, h in cmds:
        out.append("| [`%s`](#aether-%s) | %s |" % (name, name, h.replace("|", "\\|")))
    out.append("")
    for name, sp, h in cmds:
        out += ["## aether %s" % name, "", h, "", "```", _usage(sp)]
        for a in sp._actions:
            if a.option_strings and a.dest != "help":
                out.append("  %-28s %s" % (", ".join(a.option_strings), a.help or ""))
        out.append("```")
        subs = _subparsers(sp)
        if subs:
            out.append("")
            for sname, ssp, sh in subs:
                out.append("- `aether %s %s` — %s" % (name, sname, sh or _usage(ssp).split(" ", 2)[-1]))
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def main():
    text = render()
    if "--check" in sys.argv:
        current = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
        if current != text:
            sys.stderr.write("docs/CLI_REFERENCE.md is out of date: run python3 tools/gen_cli_reference.py\n")
            return 1
        print("CLI reference is up to date")
        return 0
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print("wrote %s" % OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
