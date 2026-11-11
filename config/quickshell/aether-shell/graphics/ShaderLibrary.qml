pragma Singleton
import QtQuick
import Quickshell
import "../theme"
import "../core"

// Where shader effects load their compiled shaders from, and which ones
// failed.
//
// Preference: shaders compiled locally for the installed Qt
// (scripts/build-shaders.sh → ~/.cache/aether-shell/shaders, reported by
// `aether capabilities` as shaderDir), else the .qsb files bundled next to
// the sources. A shader that fails to load is recorded here once and every
// effect using it switches to its non-shader fallback for the session.
Singleton {
    id: root

    property var failed: ({})
    readonly property bool enabled: Effects.shaders

    function url(name) {
        if (Effects.shaderDir && Effects.shaderDir.length > 0)
            return "file://" + Effects.shaderDir + "/" + name + ".frag.qsb";
        return Qt.resolvedUrl("shaders/" + name + ".frag.qsb");
    }

    function failedNames() { return root.failed; }

    function usable(name) {
        return root.enabled && !root.failed[name];
    }

    function reportStatus(name, status, log) {
        if (status !== ShaderEffect.Error || root.failed[name]) return;
        const f = Object.assign({}, root.failed);
        f[name] = true;
        root.failed = f;
        Logger.warn("ShaderLibrary", "Shader '" + name + "' failed to load; using the fallback. " + (log || ""));
    }
}
