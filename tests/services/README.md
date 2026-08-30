# Service tests — why this directory is mostly empty

The shell's services (`HyprlandService`, `AudioService`, `BluetoothService`, etc.) wrap Quickshell
modules that talk to Hyprland, PipeWire, BlueZ, UPower, and NetworkManager. Real unit tests for
them need either:

1. A live Quickshell + Qt6 QML test runner (`Qt.test` / `QtTest` via `qmltestrunner`), or
2. Mocked versions of Quickshell's `Hyprland`, `Pipewire`, `Bluetooth`, `UPower`,
   `Notifications`, and `Mpris` singletons.

Neither exists in the environment this repo was developed in — no Qt6/Quickshell installation,
no display server, no D-Bus session. Writing tests here that don't actually exercise the real
code paths would be exactly the "fake tests that merely return success" this project explicitly
rules out, so this directory doesn't contain that.

**What actually gets checked instead:**
- `tests/shell/test_qml_structure.sh` — brace/paren balance and import resolution across every
  `.qml` file (real, runs, catches real classes of error)
- Manual verification during development against Quickshell's official documentation for each
  API used (see each service's comments and the shell's own `PROGRESS.md` for exactly what was
  and wasn't confirmed against an authoritative source)

**If you have a real Quickshell environment:** the highest-value next step here would be a
`qmltestrunner`-based suite that mocks the Quickshell singletons and drives each service's
reactive properties/functions directly. That's real, achievable work — it just needs to happen
somewhere Quickshell is actually installed.
