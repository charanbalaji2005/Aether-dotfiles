import Quickshell
import Quickshell.Io
import "../../services"

// Toggle from Hyprland with:
//   bind = , Print, exec, qs -c aether-shell ipc call screenshot full
//   bind = SHIFT, Print, exec, qs -c aether-shell ipc call screenshot region
Scope {
    IpcHandler {
        target: "screenshot"
        function full(): void { ScreenshotService.captureFullScreen(); }
        function region(): void { ScreenshotService.captureRegion(); }
    }
}
