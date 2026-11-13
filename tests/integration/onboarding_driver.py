#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# Drives ./install.sh's onboarding on a pseudo-terminal like a person would:
#   onboarding_driver.py TRANSCRIPT CMD…
# Welcome → support screen (cancel) → Start installation → Recommended → yes →
# live install → final menu → Exit. Optional questions are answered "no".
# Prints "steps matched N of M" and exits with the installer's status.
import os, pty, re, sys, time, select

# (prompt regex, reply); reply None = a marker, or the final menu's Exit.
script = [
    (r"Press Enter to continue", "\n"),
    (r"Continue to the installer", None),   # marker only
    (r"Choose 1-\d+ \(q to cancel\): ", "q\n"),       # support screen -> cancel
    (r"Start installation[\s\S]*Choose 1-\d+", "1\n"),
    (r"Recommended installation[\s\S]*Choose 1-\d+", "1\n"),
    (r"Ready to install[\s\S]*\[Y/n\]", "y\n"),
    (r"Press Enter for the final menu", "\n"),
    (r"View the installation report[\s\S]*Choose 1-\d+", None),
]
out = open(sys.argv[1], "wb")
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[2], sys.argv[2:])
buf = b""; step = 0; deadline = time.time() + 400
def send(s): os.write(fd, s.encode())
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.5)
    if r:
        try: data = os.read(fd, 65536)
        except OSError: break
        if not data: break
        out.write(data); out.flush(); buf += data
    text = re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", buf).decode("utf-8", "replace")
    # yes/no questions that may or may not appear: answer "n"
    if re.search(r"\[y/N\] $", text) or re.search(r"(Bluetooth|Icon font|Your ~/.zshrc)[\s\S]*\[Y/n\] $", text):
        send("n\n"); buf = b""; continue
    while step < len(script):
        pat, reply = script[step]
        m = re.search(pat, text)
        if not m: break
        step += 1
        if reply is None:
            if pat.startswith("View"):  # final menu: choose Exit (last item)
                n = re.findall(r"(\d+)\) Exit", text)
                send((n[-1] if n else "q") + "\n")
            continue
        send(reply); buf = b""; text = ""
        break
pid2, status = os.waitpid(pid, 0)
code = os.waitstatus_to_exitcode(status)
print("steps matched %d of %d" % (step, len(script)))
sys.exit(code if step == len(script) else 99)
