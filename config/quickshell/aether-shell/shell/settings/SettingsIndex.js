.pragma library
// Searchable index of Settings: section id, title, and the words people use
// for what's inside. Shared by the launcher and the Settings search box.
var entries = [
    { id: "appearance", title: "Appearance", words: "theme dark light auto accent colour color transparency blur wallpaper accent from wallpaper" },
    { id: "style", title: "Style & palette", words: "palette nord catppuccin dracula tokyo gruvbox oled midnight aurora frost minimal custom theme glass corners rounded icons icon theme cursor" },
    { id: "effects", title: "Effects & motion", words: "quality performance eco ultra shaders glow particles animation animations springs motion speed reduce motion gpu pressure adaptive" },
    { id: "bar", title: "Bar", words: "panel top bottom floating height clock stats network speed tray workspaces" },
    { id: "dockisland", title: "Dock & island", words: "dock magnification autohide favourites dynamic island media timer focus pomodoro visualiser" },
    { id: "notifications", title: "Notifications", words: "do not disturb dnd toasts timeout per-app mute priority sound" },
    { id: "wallpaper", title: "Wallpaper", words: "background image per monitor dim blur" },
    { id: "wallfx", title: "Wallpaper effects", words: "transition parallax depth ambient particles aurora schedule video live wallpaper gradient per workspace" },
    { id: "battery", title: "Battery", words: "battery icon low critical charging colours alerts power saver automatic" },
    { id: "lock", title: "Lock screen", words: "lock clock idle timeout suspend display off dim screen" },
    { id: "gestures", title: "Gestures", words: "touchpad swipe three fingers edges screen edge" },
    { id: "automation", title: "Automation", words: "rules triggers when then automatic workflow" },
    { id: "profiles", title: "Profiles", words: "desktop profile gaming developer minimal cinematic battery saver" },
    { id: "terminal", title: "Terminal", words: "kitty foot alacritty ghostty font opacity cursor zsh shell profile meridian" },
    { id: "keyboard", title: "Keyboard", words: "keyboard layout language variant repeat rate delay caps lock xkb options" },
    { id: "mouse", title: "Mouse & touchpad", words: "mouse touchpad pointer speed sensitivity acceleration natural scroll tap to click" },
    { id: "displays", title: "Displays", words: "monitor display resolution refresh rate hz scale position hidpi multi-monitor profile" },
    { id: "workspaces", title: "Workspaces", words: "workspace names icons app rules session restore" },
    { id: "widgets", title: "Widgets", words: "desktop widgets clock calendar cpu gpu media battery network install" },
    { id: "gpu", title: "GPU & rendering", words: "gpu nvidia amd intel vram renderer vulkan opengl hybrid prime render diagnostics" },
    { id: "accessibility", title: "Accessibility", words: "scale size large text high contrast colour blind focus rings reduced motion 24 hour" },
    { id: "privacy", title: "Privacy & security", words: "privacy clipboard history retention exclude password security selinux firewall audit log microphone camera" },
    { id: "ai", title: "AI assistant", words: "assistant ai ollama openai model api key local llm chat" },
    { id: "startup", title: "Startup applications", words: "autostart startup login apps" },
    { id: "backup", title: "Backup & recovery", words: "backup snapshot restore recovery safe mode last known good rollback" },
    { id: "performance", title: "Performance", words: "hyprland profile compositor blur telemetry interval battery" },
    { id: "developer", title: "Developer", words: "developer logs debug safe mode reload shell diagnostics" },
    { id: "about", title: "About", words: "version about system information dependencies" }
];

function search(q, limit) {
    q = (q || "").toLowerCase().trim();
    if (q.length < 2) return [];
    var out = [];
    for (var i = 0; i < entries.length; i++) {
        var e = entries[i];
        var t = e.title.toLowerCase();
        var score = t.indexOf(q) === 0 ? 3 : t.indexOf(q) >= 0 ? 2 : (" " + e.words + " ").indexOf(" " + q) >= 0 ? 1 : 0;
        if (score > 0) out.push({ entry: e, score: score });
    }
    out.sort(function(a, b) { return b.score - a.score; });
    return out.slice(0, limit || 4).map(function(x) { return x.entry; });
}
