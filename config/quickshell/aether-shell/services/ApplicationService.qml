pragma Singleton
import Quickshell
import Quickshell.Io
import "../core"

// Discovers installed applications from XDG .desktop entries. Quickshell has
// no built-in application-discovery module, so this reads the standard
// application directories directly and parses the Desktop Entry spec's
// simple key=value format itself.
Singleton {
    id: root

    property bool available: false
    property var applications: [] // [{id, name, genericName, comment, exec, icon, categories, terminal}]

    readonly property string _scanScript: [
        'for d in "$HOME/.local/share/applications" /usr/share/applications /usr/local/share/applications /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications"; do',
        '  [ -d "$d" ] || continue',
        '  for f in "$d"/*.desktop; do',
        '    [ -f "$f" ] || continue',
        '    echo "###AETHER-ENTRY###$f"',
        '    cat "$f"',
        '  done',
        'done'
    ].join("\n")

    Process {
        id: scanProcess
        command: ["bash", "-c", root._scanScript]
        stdout: StdioCollector {
            onStreamFinished: root._parse(this.text)
        }
    }

    Process {
        id: launchProcess
    }

    function refresh() {
        scanProcess.running = true;
    }

    function _parse(text) {
        const chunks = text.split("###AETHER-ENTRY###").filter(function(c) { return c.trim().length > 0; });
        const seen = {};
        const result = [];

        for (const chunk of chunks) {
            const newlineIndex = chunk.indexOf("\n");
            if (newlineIndex < 0) continue;
            const path = chunk.substring(0, newlineIndex).trim();
            const body = chunk.substring(newlineIndex + 1);
            const id = path.split("/").pop();

            // First directory in the scan order wins, matching XDG precedence
            // (user's ~/.local/share/applications is searched first above).
            if (seen[id]) continue;

            const entry = root._parseDesktopEntry(body, path);
            if (!entry) continue;
            if (entry.noDisplay || entry.hidden) continue;
            if (!entry.name || !entry.argv || entry.argv.length === 0) continue;

            seen[id] = true;
            entry.id = id;
            result.push(entry);
        }

        result.sort(function(a, b) { return a.name.localeCompare(b.name); });
        root.applications = result;
        root.available = true;
        Logger.info("ApplicationService", "Discovered " + result.length + " applications");
    }

    function _parseExec(execStr, fields, desktopPath) {
        if (!execStr) return [];
        const rawArgs = [];
        let current = "";
        let inQuote = false;
        let i = 0;

        while (i < execStr.length) {
            const c = execStr.charAt(i);
            if (c === "\\") {
                if (i + 1 < execStr.length) {
                    const next = execStr.charAt(i + 1);
                    if (inQuote) {
                        if (next === '"' || next === '\\' || next === '$' || next === '`') {
                            current += next;
                            i += 2;
                            continue;
                        }
                    } else {
                        current += next;
                        i += 2;
                        continue;
                    }
                }
                current += c;
                i++;
            } else if (c === '"') {
                inQuote = !inQuote;
                i++;
            } else if (!inQuote && (c === ' ' || c === '\t')) {
                if (current.length > 0) {
                    rawArgs.push(current);
                    current = "";
                }
                i++;
            } else {
                current += c;
                i++;
            }
        }
        if (current.length > 0) {
            rawArgs.push(current);
        }

        const finalArgv = [];
        for (const arg of rawArgs) {
            if (arg === "%i") {
                if (fields.Icon && fields.Icon.length > 0) {
                    finalArgv.push("--icon");
                    finalArgv.push(fields.Icon);
                }
                continue;
            }
            if (arg === "%f" || arg === "%F" || arg === "%u" || arg === "%U" ||
                arg === "%d" || arg === "%D" || arg === "%n" || arg === "%N" || arg === "%v" || arg === "%m") {
                continue;
            }

            let expanded = "";
            let j = 0;
            while (j < arg.length) {
                if (arg.charAt(j) === "%" && j + 1 < arg.length) {
                    const code = arg.charAt(j + 1);
                    if (code === "%") {
                        expanded += "%";
                        j += 2;
                    } else if (code === "c") {
                        expanded += (fields.Name || "");
                        j += 2;
                    } else if (code === "k") {
                        expanded += (desktopPath || "");
                        j += 2;
                    } else if (code === "i") {
                        if (fields.Icon && fields.Icon.length > 0) {
                            expanded += fields.Icon;
                        }
                        j += 2;
                    } else if ("fFuUdDnNvm".indexOf(code) >= 0) {
                        j += 2;
                    } else {
                        j += 2;
                    }
                } else {
                    expanded += arg.charAt(j);
                    j++;
                }
            }

            if (expanded.trim().length > 0) {
                finalArgv.push(expanded);
            }
        }

        return finalArgv;
    }

    function _parseDesktopEntry(body, desktopPath) {
        const lines = body.split("\n");
        let inSection = false;
        const fields = {};

        for (let line of lines) {
            line = line.trim();
            if (line.length === 0 || line.charAt(0) === "#") continue;

            if (line.charAt(0) === "[") {
                inSection = (line === "[Desktop Entry]");
                continue;
            }
            if (!inSection) continue;

            const eq = line.indexOf("=");
            if (eq < 0) continue;
            const key = line.substring(0, eq).trim();
            const value = line.substring(eq + 1).trim();
            if (!(key in fields)) fields[key] = value; // first occurrence in the section wins
        }

        if (!fields.Name || !fields.Exec) return null;

        const argv = root._parseExec(fields.Exec, fields, desktopPath);
        if (argv.length === 0) return null;

        return {
            name: fields.Name,
            genericName: fields.GenericName || "",
            comment: fields.Comment || "",
            exec: fields.Exec,
            argv: argv,
            icon: fields.Icon || "",
            categories: (fields.Categories || "").split(";").filter(function(c) { return c.length > 0; }),
            terminal: fields.Terminal === "true",
            noDisplay: fields.NoDisplay === "true",
            hidden: fields.Hidden === "true"
        };
    }

    function launch(app) {
        if (!app || !app.argv || app.argv.length === 0) return;
        Logger.info("ApplicationService", "Launching " + app.name + " (" + app.argv[0] + ")");
        if (app.terminal) {
            launchProcess.command = ["kitty", "-e"].concat(app.argv);
        } else {
            launchProcess.command = app.argv;
        }
        launchProcess.running = true;
    }

    function search(query) {
        if (!query || query.length === 0) {
            return root.applications.slice(0, 40);
        }
        const q = query.toLowerCase();
        const scored = [];
        for (const app of root.applications) {
            const score = root._score(q, app.name.toLowerCase());
            if (score > 0) scored.push({ app: app, score: score });
        }
        scored.sort(function(a, b) { return b.score - a.score; });
        return scored.map(function(s) { return s.app; });
    }

    // Simple ordered-subsequence fuzzy match with bonuses for exact/prefix/
    // contiguous matches, sufficient for launcher-style search.
    function _score(query, target) {
        if (target === query) return 1000;
        if (target.indexOf(query) === 0) return 500 - target.length;
        if (target.indexOf(query) >= 0) return 200 - target.length;

        let qi = 0;
        let consecutive = 0;
        let bonus = 0;
        for (let ti = 0; ti < target.length && qi < query.length; ti++) {
            if (target.charAt(ti) === query.charAt(qi)) {
                qi++;
                consecutive++;
                bonus += consecutive;
            } else {
                consecutive = 0;
            }
        }
        return qi === query.length ? bonus : 0;
    }

    Component.onCompleted: refresh()
}
