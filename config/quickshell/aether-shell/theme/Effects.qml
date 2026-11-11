pragma Singleton
import QtQuick
import Quickshell

// Effective graphics quality for components. theme/ can't read services, so
// these are bound once at the shell root from PerformanceService, which
// decides them from the user's setting, the hardware, power state, safe
// mode and measured frame pacing (see services/PerformanceService.qml).
//
// Components read only these flags; they never decide quality themselves.
Singleton {
    property string tier: "balanced"      // "eco" | "balanced" | "ultra"
    property bool shaders: true           // ShaderEffect materials allowed and loadable
    property bool glow: true              // animated accent edges
    property bool particles: false        // ambient particle systems
    property bool parallax: false         // pointer-driven depth
    property bool lightFollow: true       // glass specular follows the pointer
    property bool ambient: true           // slow ambient animation (lock screen aurora)
    property string shaderDir: ""         // locally compiled .qsb directory ("" = bundled)

    readonly property bool eco: tier === "eco"
    readonly property bool ultra: tier === "ultra"
}
