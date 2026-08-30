pragma Singleton
import Quickshell

Singleton {
    id: root

    readonly property int levelDebug: 0
    readonly property int levelInfo: 1
    readonly property int levelWarn: 2
    readonly property int levelError: 3

    property int minLevel: levelInfo
    property var history: []
    readonly property int historyLimit: 300

    function _label(level) {
        switch (level) {
        case levelDebug: return "DEBUG";
        case levelWarn: return "WARN";
        case levelError: return "ERROR";
        default: return "INFO";
        }
    }

    function _emit(level, tag, message) {
        if (level < root.minLevel) return;

        const entry = {
            time: new Date().toISOString(),
            level: level,
            tag: tag,
            message: message
        };

        // Reassign (rather than push) so QML property-change notification
        // fires for anything bound to `history`.
        const next = root.history.concat([entry]);
        root.history = next.length > root.historyLimit
            ? next.slice(next.length - root.historyLimit)
            : next;

        const line = "[" + root._label(level) + "] " + tag + ": " + message;
        if (level >= levelError) console.error(line);
        else if (level === levelWarn) console.warn(line);
        else console.log(line);
    }

    function debug(tag, message) { root._emit(levelDebug, tag, message); }
    function info(tag, message) { root._emit(levelInfo, tag, message); }
    function warn(tag, message) { root._emit(levelWarn, tag, message); }
    function error(tag, message) { root._emit(levelError, tag, message); }
}
