.pragma library

// AetherOS colour palettes — the single source of truth.
//
// The object between the PALETTES-BEGIN / PALETTES-END markers is strict
// JSON: the Python backend (lib/aether/palettes.py) parses the same block
// to theme Kitty and Hyprland, so the shell and the terminal can never
// drift apart. tests/python/test_desktop.py asserts that it parses and that
// every palette defines every token.
//
// "aether" is the built-in palette and the only one with both a dark and a
// light variant (theme mode dark/light/auto applies to it). The others are
// community colour schemes reproduced from their published specifications;
// each is inherently dark or light.
//
// Tokens: bg0-2 window backgrounds, glass translucent panel tint, surface*
// fills inside panels, border*, text/text2/text3, accent/accentAlt, status
// colours, and ansi[16] for terminals.

// PALETTES-BEGIN
var palettes = {
    "aether": {"label": "AetherOS", "dark": true,
        "bg0": "#0A0C12", "bg1": "#12141C", "bg2": "#1B1E29", "glass": "#161925",
        "surface": "#1E2230", "surfaceHover": "#272C3D", "surfaceActive": "#30364A",
        "border": "#2A2E3D", "borderStrong": "#3A3F52",
        "text": "#EDEFF7", "text2": "#AEB3C7", "text3": "#7E8399",
        "accent": "#7C9CFF", "accentAlt": "#B48CFF",
        "success": "#4ADE80", "warning": "#FBBF24", "danger": "#F87171", "info": "#38BDF8",
        "ansi": ["#1B1E29", "#F87171", "#4ADE80", "#FBBF24", "#7C9CFF", "#B48CFF", "#38BDF8", "#AEB3C7",
                 "#3A3F52", "#FCA5A5", "#86EFAC", "#FCD34D", "#A5B9FF", "#CDB4FF", "#7DD3FC", "#EDEFF7"]},
    "aether-light": {"label": "AetherOS Light", "dark": false,
        "bg0": "#EEF0F6", "bg1": "#F6F7FB", "bg2": "#FFFFFF", "glass": "#F8F9FC",
        "surface": "#FFFFFF", "surfaceHover": "#E9ECF4", "surfaceActive": "#DCE1EC",
        "border": "#D5D9E4", "borderStrong": "#BCC2D1",
        "text": "#151824", "text2": "#4A5068", "text3": "#7A8096",
        "accent": "#4C6FE0", "accentAlt": "#7B4FE0",
        "success": "#15934A", "warning": "#B7791F", "danger": "#D63B3B", "info": "#0B84C6",
        "ansi": ["#151824", "#D63B3B", "#15934A", "#B7791F", "#4C6FE0", "#7B4FE0", "#0B84C6", "#4A5068",
                 "#7A8096", "#E05252", "#1FA85A", "#C98A2B", "#6584EA", "#9068EA", "#2A9BD8", "#151824"]},
    "oled": {"label": "OLED Black", "dark": true,
        "bg0": "#000000", "bg1": "#000000", "bg2": "#0A0A0C", "glass": "#050507",
        "surface": "#111114", "surfaceHover": "#1A1A1F", "surfaceActive": "#24242B",
        "border": "#1C1C22", "borderStrong": "#2C2C35",
        "text": "#F2F2F7", "text2": "#A9A9B5", "text3": "#71717E",
        "accent": "#8AA4FF", "accentAlt": "#C49BFF",
        "success": "#4ADE80", "warning": "#FBBF24", "danger": "#FF6B6B", "info": "#38BDF8",
        "ansi": ["#111114", "#FF6B6B", "#4ADE80", "#FBBF24", "#8AA4FF", "#C49BFF", "#38BDF8", "#A9A9B5",
                 "#2C2C35", "#FF8E8E", "#7BEBA6", "#FCD34D", "#AFC1FF", "#D8BDFF", "#7DD3FC", "#F2F2F7"]},
    "midnight": {"label": "Midnight", "dark": true,
        "bg0": "#070B17", "bg1": "#0C1224", "bg2": "#121A33", "glass": "#0E1529",
        "surface": "#17213D", "surfaceHover": "#1F2B4D", "surfaceActive": "#28365E",
        "border": "#1E2948", "borderStrong": "#2E3C66",
        "text": "#E6ECFF", "text2": "#A8B4D8", "text3": "#6F7BA3",
        "accent": "#5B8CFF", "accentAlt": "#9D7BFF",
        "success": "#3DDC97", "warning": "#F6C453", "danger": "#FF6B81", "info": "#4CC9F0",
        "ansi": ["#17213D", "#FF6B81", "#3DDC97", "#F6C453", "#5B8CFF", "#9D7BFF", "#4CC9F0", "#A8B4D8",
                 "#2E3C66", "#FF8FA0", "#6BE7B1", "#F9D27E", "#85A8FF", "#B9A0FF", "#7DD8F5", "#E6ECFF"]},
    "aurora": {"label": "Aurora", "dark": true,
        "bg0": "#06110F", "bg1": "#0A1917", "bg2": "#0F2220", "glass": "#0C1D1B",
        "surface": "#13302C", "surfaceHover": "#1A3D38", "surfaceActive": "#224B45",
        "border": "#173733", "borderStrong": "#24504A",
        "text": "#E3FFF8", "text2": "#9FD3C7", "text3": "#64998D",
        "accent": "#34E5B4", "accentAlt": "#A78BFA",
        "success": "#34E5B4", "warning": "#FACC15", "danger": "#FB7185", "info": "#38BDF8",
        "ansi": ["#13302C", "#FB7185", "#34E5B4", "#FACC15", "#38BDF8", "#A78BFA", "#2DD4BF", "#9FD3C7",
                 "#24504A", "#FDA4AF", "#6EF0C9", "#FDE047", "#7DD3FC", "#C4B5FD", "#5EEAD4", "#E3FFF8"]},
    "frost": {"label": "Frost", "dark": true,
        "bg0": "#0E141B", "bg1": "#141C25", "bg2": "#1A2430", "glass": "#18222D",
        "surface": "#202C3A", "surfaceHover": "#283748", "surfaceActive": "#314256",
        "border": "#2A3747", "borderStrong": "#3B4C61",
        "text": "#EEF4FA", "text2": "#B3C2D3", "text3": "#7A8BA0",
        "accent": "#7CC4FF", "accentAlt": "#B7C9FF",
        "success": "#6EE7B7", "warning": "#FCD34D", "danger": "#FCA5A5", "info": "#93C5FD",
        "ansi": ["#202C3A", "#FCA5A5", "#6EE7B7", "#FCD34D", "#7CC4FF", "#B7C9FF", "#93C5FD", "#B3C2D3",
                 "#3B4C61", "#FECACA", "#A7F3D0", "#FDE68A", "#A9D8FF", "#D0DCFF", "#BFDBFE", "#EEF4FA"]},
    "minimal": {"label": "Minimal Mono", "dark": true,
        "bg0": "#0F0F10", "bg1": "#161617", "bg2": "#1D1D1F", "glass": "#18181A",
        "surface": "#222224", "surfaceHover": "#2B2B2E", "surfaceActive": "#353538",
        "border": "#2A2A2D", "borderStrong": "#3A3A3E",
        "text": "#ECECEC", "text2": "#ABABAF", "text3": "#77777C",
        "accent": "#E4E4E7", "accentAlt": "#A1A1AA",
        "success": "#86EFAC", "warning": "#FDE68A", "danger": "#FCA5A5", "info": "#BAE6FD",
        "ansi": ["#222224", "#FCA5A5", "#86EFAC", "#FDE68A", "#BAE6FD", "#D4D4D8", "#A5F3FC", "#ABABAF",
                 "#3A3A3E", "#FECACA", "#BBF7D0", "#FEF08A", "#E0F2FE", "#E4E4E7", "#CFFAFE", "#ECECEC"]},
    "high-contrast": {"label": "High Contrast", "dark": true,
        "bg0": "#000000", "bg1": "#000000", "bg2": "#000000", "glass": "#000000",
        "surface": "#0D0D0D", "surfaceHover": "#262626", "surfaceActive": "#3A3A3A",
        "border": "#FFFFFF", "borderStrong": "#FFFFFF",
        "text": "#FFFFFF", "text2": "#FFFFFF", "text3": "#D9D9D9",
        "accent": "#FFD400", "accentAlt": "#00E5FF",
        "success": "#00FF6A", "warning": "#FFD400", "danger": "#FF4040", "info": "#00E5FF",
        "ansi": ["#000000", "#FF4040", "#00FF6A", "#FFD400", "#4DA6FF", "#FF66FF", "#00E5FF", "#FFFFFF",
                 "#808080", "#FF7373", "#66FF9F", "#FFE566", "#80BFFF", "#FF99FF", "#66F0FF", "#FFFFFF"]},
    "catppuccin-mocha": {"label": "Catppuccin Mocha", "dark": true,
        "bg0": "#11111B", "bg1": "#181825", "bg2": "#1E1E2E", "glass": "#181825",
        "surface": "#313244", "surfaceHover": "#45475A", "surfaceActive": "#585B70",
        "border": "#313244", "borderStrong": "#45475A",
        "text": "#CDD6F4", "text2": "#A6ADC8", "text3": "#6C7086",
        "accent": "#89B4FA", "accentAlt": "#CBA6F7",
        "success": "#A6E3A1", "warning": "#F9E2AF", "danger": "#F38BA8", "info": "#89DCEB",
        "ansi": ["#45475A", "#F38BA8", "#A6E3A1", "#F9E2AF", "#89B4FA", "#F5C2E7", "#94E2D5", "#BAC2DE",
                 "#585B70", "#F38BA8", "#A6E3A1", "#F9E2AF", "#89B4FA", "#F5C2E7", "#94E2D5", "#A6ADC8"]},
    "catppuccin-latte": {"label": "Catppuccin Latte", "dark": false,
        "bg0": "#DCE0E8", "bg1": "#E6E9EF", "bg2": "#EFF1F5", "glass": "#EFF1F5",
        "surface": "#FFFFFF", "surfaceHover": "#DCE0E8", "surfaceActive": "#CCD0DA",
        "border": "#CCD0DA", "borderStrong": "#ACB0BE",
        "text": "#4C4F69", "text2": "#5C5F77", "text3": "#8C8FA1",
        "accent": "#1E66F5", "accentAlt": "#8839EF",
        "success": "#40A02B", "warning": "#DF8E1D", "danger": "#D20F39", "info": "#04A5E5",
        "ansi": ["#5C5F77", "#D20F39", "#40A02B", "#DF8E1D", "#1E66F5", "#EA76CB", "#179299", "#ACB0BE",
                 "#6C6F85", "#D20F39", "#40A02B", "#DF8E1D", "#1E66F5", "#EA76CB", "#179299", "#BCC0CC"]},
    "nord": {"label": "Nord", "dark": true,
        "bg0": "#242933", "bg1": "#2E3440", "bg2": "#3B4252", "glass": "#2E3440",
        "surface": "#3B4252", "surfaceHover": "#434C5E", "surfaceActive": "#4C566A",
        "border": "#3B4252", "borderStrong": "#4C566A",
        "text": "#ECEFF4", "text2": "#D8DEE9", "text3": "#8892A6",
        "accent": "#88C0D0", "accentAlt": "#B48EAD",
        "success": "#A3BE8C", "warning": "#EBCB8B", "danger": "#BF616A", "info": "#81A1C1",
        "ansi": ["#3B4252", "#BF616A", "#A3BE8C", "#EBCB8B", "#81A1C1", "#B48EAD", "#88C0D0", "#E5E9F0",
                 "#4C566A", "#BF616A", "#A3BE8C", "#EBCB8B", "#81A1C1", "#B48EAD", "#8FBCBB", "#ECEFF4"]},
    "dracula": {"label": "Dracula", "dark": true,
        "bg0": "#191A21", "bg1": "#21222C", "bg2": "#282A36", "glass": "#21222C",
        "surface": "#343746", "surfaceHover": "#44475A", "surfaceActive": "#565A72",
        "border": "#343746", "borderStrong": "#44475A",
        "text": "#F8F8F2", "text2": "#C9CBDA", "text3": "#6272A4",
        "accent": "#BD93F9", "accentAlt": "#FF79C6",
        "success": "#50FA7B", "warning": "#F1FA8C", "danger": "#FF5555", "info": "#8BE9FD",
        "ansi": ["#21222C", "#FF5555", "#50FA7B", "#F1FA8C", "#BD93F9", "#FF79C6", "#8BE9FD", "#F8F8F2",
                 "#6272A4", "#FF6E6E", "#69FF94", "#FFFFA5", "#D6ACFF", "#FF92DF", "#A4FFFF", "#FFFFFF"]},
    "tokyo-night": {"label": "Tokyo Night", "dark": true,
        "bg0": "#16161E", "bg1": "#1A1B26", "bg2": "#1F2335", "glass": "#1A1B26",
        "surface": "#24283B", "surfaceHover": "#292E42", "surfaceActive": "#3B4261",
        "border": "#292E42", "borderStrong": "#414868",
        "text": "#C0CAF5", "text2": "#A9B1D6", "text3": "#565F89",
        "accent": "#7AA2F7", "accentAlt": "#BB9AF7",
        "success": "#9ECE6A", "warning": "#E0AF68", "danger": "#F7768E", "info": "#7DCFFF",
        "ansi": ["#15161E", "#F7768E", "#9ECE6A", "#E0AF68", "#7AA2F7", "#BB9AF7", "#7DCFFF", "#A9B1D6",
                 "#414868", "#F7768E", "#9ECE6A", "#E0AF68", "#7AA2F7", "#BB9AF7", "#7DCFFF", "#C0CAF5"]},
    "gruvbox": {"label": "Gruvbox", "dark": true,
        "bg0": "#1D2021", "bg1": "#282828", "bg2": "#32302F", "glass": "#282828",
        "surface": "#3C3836", "surfaceHover": "#504945", "surfaceActive": "#665C54",
        "border": "#3C3836", "borderStrong": "#504945",
        "text": "#EBDBB2", "text2": "#D5C4A1", "text3": "#928374",
        "accent": "#FABD2F", "accentAlt": "#FE8019",
        "success": "#B8BB26", "warning": "#FABD2F", "danger": "#FB4934", "info": "#83A598",
        "ansi": ["#282828", "#CC241D", "#98971A", "#D79921", "#458588", "#B16286", "#689D6A", "#A89984",
                 "#928374", "#FB4934", "#B8BB26", "#FABD2F", "#83A598", "#D3869B", "#8EC07C", "#EBDBB2"]},
    "rose-pine": {"label": "Rosé Pine", "dark": true,
        "bg0": "#13111C", "bg1": "#191724", "bg2": "#1F1D2E", "glass": "#191724",
        "surface": "#26233A", "surfaceHover": "#403D52", "surfaceActive": "#524F67",
        "border": "#26233A", "borderStrong": "#403D52",
        "text": "#E0DEF4", "text2": "#908CAA", "text3": "#6E6A86",
        "accent": "#C4A7E7", "accentAlt": "#EBBCBA",
        "success": "#9CCFD8", "warning": "#F6C177", "danger": "#EB6F92", "info": "#31748F",
        "ansi": ["#26233A", "#EB6F92", "#31748F", "#F6C177", "#9CCFD8", "#C4A7E7", "#EBBCBA", "#E0DEF4",
                 "#6E6A86", "#EB6F92", "#31748F", "#F6C177", "#9CCFD8", "#C4A7E7", "#EBBCBA", "#E0DEF4"]},
    "everforest": {"label": "Everforest", "dark": true,
        "bg0": "#232A2E", "bg1": "#2D353B", "bg2": "#343F44", "glass": "#2D353B",
        "surface": "#3D484D", "surfaceHover": "#475258", "surfaceActive": "#4F585E",
        "border": "#3D484D", "borderStrong": "#4F585E",
        "text": "#D3C6AA", "text2": "#9DA9A0", "text3": "#7A8478",
        "accent": "#A7C080", "accentAlt": "#83C092",
        "success": "#A7C080", "warning": "#DBBC7F", "danger": "#E67E80", "info": "#7FBBB3",
        "ansi": ["#475258", "#E67E80", "#A7C080", "#DBBC7F", "#7FBBB3", "#D699B6", "#83C092", "#D3C6AA",
                 "#7A8478", "#E67E80", "#A7C080", "#DBBC7F", "#7FBBB3", "#D699B6", "#83C092", "#D3C6AA"]},
    "solarized": {"label": "Solarized Dark", "dark": true,
        "bg0": "#00212B", "bg1": "#002B36", "bg2": "#073642", "glass": "#002B36",
        "surface": "#073642", "surfaceHover": "#0B4553", "surfaceActive": "#125566",
        "border": "#073642", "borderStrong": "#586E75",
        "text": "#EEE8D5", "text2": "#93A1A1", "text3": "#657B83",
        "accent": "#268BD2", "accentAlt": "#6C71C4",
        "success": "#859900", "warning": "#B58900", "danger": "#DC322F", "info": "#2AA198",
        "ansi": ["#073642", "#DC322F", "#859900", "#B58900", "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
                 "#002B36", "#CB4B16", "#586E75", "#657B83", "#839496", "#6C71C4", "#93A1A1", "#FDF6E3"]},
    "one-dark": {"label": "One Dark", "dark": true,
        "bg0": "#1B1F23", "bg1": "#21252B", "bg2": "#282C34", "glass": "#21252B",
        "surface": "#2C313A", "surfaceHover": "#3E4451", "surfaceActive": "#4B5263",
        "border": "#2C313A", "borderStrong": "#3E4451",
        "text": "#D7DAE0", "text2": "#ABB2BF", "text3": "#5C6370",
        "accent": "#61AFEF", "accentAlt": "#C678DD",
        "success": "#98C379", "warning": "#E5C07B", "danger": "#E06C75", "info": "#56B6C2",
        "ansi": ["#282C34", "#E06C75", "#98C379", "#E5C07B", "#61AFEF", "#C678DD", "#56B6C2", "#ABB2BF",
                 "#5C6370", "#E06C75", "#98C379", "#E5C07B", "#61AFEF", "#C678DD", "#56B6C2", "#FFFFFF"]},
    "monokai": {"label": "Monokai", "dark": true,
        "bg0": "#1A1A17", "bg1": "#1E1F1C", "bg2": "#272822", "glass": "#1E1F1C",
        "surface": "#33342C", "surfaceHover": "#3E3D32", "surfaceActive": "#49483E",
        "border": "#33342C", "borderStrong": "#49483E",
        "text": "#F8F8F2", "text2": "#CFCFC2", "text3": "#75715E",
        "accent": "#A6E22E", "accentAlt": "#AE81FF",
        "success": "#A6E22E", "warning": "#E6DB74", "danger": "#F92672", "info": "#66D9EF",
        "ansi": ["#272822", "#F92672", "#A6E22E", "#F4BF75", "#66D9EF", "#AE81FF", "#A1EFE4", "#F8F8F2",
                 "#75715E", "#F92672", "#A6E22E", "#F4BF75", "#66D9EF", "#AE81FF", "#A1EFE4", "#F9F8F5"]}
};
// PALETTES-END

// Colour-blind-safe status colours (Okabe-Ito): blue/orange/vermillion
// instead of green/amber/red, which protan/deutan vision can't separate.
var colorBlindStatus = { "success": "#0072B2", "warning": "#E69F00", "danger": "#D55E00", "info": "#56B4E9" };

function ids() {
    var out = [];
    for (var k in palettes) if (k !== "aether-light") out.push(k);
    return out;
}

// User themes (aether theme create/import → ~/.config/aether-shell/themes)
// arrive as an object id -> palette, already validated by the backend.

// Resolve a palette id (+ the dark/light decision, which only matters for
// the built-in palette) to a token object. Unknown ids fall back to the
// built-in palette, so a hand-edited config can never blank the shell.
function resolve(id, dark, user) {
    if (user && id && user[id] && user[id].bg0) return user[id];
    if (!id || !palettes[id] || id === "aether" || id === "aether-light")
        return dark ? palettes["aether"] : palettes["aether-light"];
    return palettes[id];
}
