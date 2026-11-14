-- AetherOS — hyprlang (.conf) compatibility layer for Hyprland's Lua config.
--
-- Hyprland 0.57 reads only ~/.config/hypr/hyprland.lua. AetherOS keeps its
-- settings in hyprlang .conf files (hyprland.conf and the fragments the
-- `aether` tools regenerate), so this module parses those files on every
-- load and turns each line into the matching hl.* call. It also exposes a
-- global `aether` table that the hyprctl shim (scripts/bin/hyprctl) uses to
-- run legacy `hyprctl keyword …` / `hyprctl dispatch <name> …` commands.
--
-- Problems are collected rather than fatal: one bad line never stops the
-- rest of the configuration from loading. They are written to
-- $XDG_STATE_HOME/aether/hypr-lua.log.

local M = { errors = {} }

local HOME = os.getenv("HOME") or ""
local STUBS = "/usr/share/hypr/stubs/hl.meta.lua"

-- A display manager starts Hyprland without a login shell, so ~/.local/bin
-- (where the aether-* tools are linked) is not on its PATH and every bind or
-- exec-once that calls them fails with "command not found". Children inherit
-- Hyprland's environment, so adding it here fixes all of them.
do
    local path = os.getenv("PATH") or "/usr/local/bin:/usr/bin"
    local bin = HOME .. "/.local/bin"
    if HOME ~= "" and not (":" .. path .. ":"):find(":" .. bin .. ":", 1, true) then
        pcall(hl.env, "PATH", bin .. ":" .. path)
    end
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function err(where, msg)
    M.errors[#M.errors + 1] = where .. ": " .. tostring(msg)
end

local function split(s, sep, max)
    local out, start = {}, 1
    while true do
        if max and #out == max - 1 then out[#out + 1] = trim(s:sub(start)); break end
        local i = s:find(sep, start, true)
        if not i then out[#out + 1] = trim(s:sub(start)); break end
        out[#out + 1] = trim(s:sub(start, i - 1))
        start = i + #sep
    end
    return out
end

local function expand(path)
    return (path:gsub("^~", HOME):gsub("%$HOME", HOME))
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

-- Option types, read from Hyprland's own stubs so conversions follow the
-- installed version. option -> type string, e.g. "boolean", "integer|boolean".
local TYPES = {}
do
    local f = io.open(STUBS, "r")
    if f then
        for line in f:lines() do
            local k, t = line:match("^%-%-%-@field %['([^']+)'%] (%S+)")
            if k then TYPES[k] = t end
        end
        f:close()
    end
end

local BOOL = { ["true"] = true, yes = true, on = true, ["1"] = true,
               ["false"] = false, no = false, off = false, ["0"] = false }

-- Convert a hyprlang value string for option `key` (dotted path).
local function convert(key, v)
    v = trim(v)
    local t = TYPES[key] or ""
    if t:match("^boolean") and BOOL[v:lower()] ~= nil then return BOOL[v:lower()] end
    if t:match("integer") or t:match("number") then
        local n = tonumber(v)
        if n then return n end
        if t:match("boolean") and BOOL[v:lower()] ~= nil then return BOOL[v:lower()] end
    end
    if t:match("Gradient") then
        -- "rgba(a) rgba(b) 45deg" -> { colors = { "rgba(a)", "rgba(b)" }, angle = 45 }
        local colors, angle = {}, nil
        for tok in v:gmatch("%S+") do
            local deg = tok:match("^(%-?[%d.]+)deg$")
            if deg then angle = tonumber(deg) else colors[#colors + 1] = tok end
        end
        if #colors > 1 or angle then return { colors = colors, angle = angle } end
    end
    if t:match("CssGap") then
        local a, b, c, d = v:match("^(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)$")
        if a then return { top = tonumber(a), right = tonumber(b), bottom = tonumber(c), left = tonumber(d) } end
    end
    if t == "" then
        if BOOL[v:lower()] ~= nil and not tonumber(v) then return BOOL[v:lower()] end
        local n = tonumber(v)
        if n then return n end
    end
    return v
end

-- hyprland.conf keeps the pre-0.57 names (it is also read by older Hyprland).
-- Options that moved are applied under their new name; options that no longer
-- exist and have no replacement are dropped without a warning.
local MOVED = { ["misc.vfr"] = "debug.vfr" }
local GONE = { ["dwindle.pseudotile"] = true }  -- now the per-window pseudo dispatcher

-- Apply one option given as a dotted path ("general.col.active_border").
local function set_option(key, value, where)
    key = key:gsub(":", "."):gsub("%-", "_")
    if next(TYPES) and not TYPES[key] then
        if MOVED[key] and TYPES[MOVED[key]] then key = MOVED[key]
        elseif GONE[key] then return true end
    end
    if next(TYPES) and not TYPES[key] then
        err(where, "unknown option '" .. key .. "' (skipped)")
        return false
    end
    local root, node = {}, nil
    node = root
    local parts = split(key, ".")
    for i = 1, #parts - 1 do
        node[parts[i]] = {}
        node = node[parts[i]]
    end
    node[parts[#parts]] = convert(key, value)
    local ok, e = pcall(hl.config, root)
    if not ok then err(where, key .. " = " .. value .. ": " .. tostring(e)) end
    return ok
end

---------------------------------------------------------------------------
-- Dispatchers: legacy name + argument string -> hl.dsp dispatcher
---------------------------------------------------------------------------

local DIR = { l = "left", r = "right", u = "up", d = "down", t = "up", b = "down",
              left = "left", right = "right", up = "up", down = "down" }

local function ws(v)
    v = trim(v)
    return tonumber(v) or v
end

-- "exact 10 20,address:0x1" -> "exact 10 20", "address:0x1"
local function split_window(arg)
    local a, w = arg:match("^(.-),%s*(address:%S+)$")
    if a then return trim(a), w end
    return arg, nil
end

local function xy(arg)
    local exact, x, y = arg:match("^(exact%s+)(%-?[%d.]+%%?)%s+(%-?[%d.]+%%?)$")
    if not exact then x, y = arg:match("^(%-?[%d.]+%%?)%s+(%-?[%d.]+%%?)$") end
    return tonumber(x) or x, tonumber(y) or y, exact == nil
end

local D = {}
D.exec = function(a) return hl.dsp.exec_cmd(a) end
D.execr = function(a) return hl.dsp.exec_raw(a) end
D.killactive = function() return hl.dsp.window.close() end
D.closewindow = function(a) return hl.dsp.window.close({ window = a }) end
-- "address:0x…" / "class:…": also switches to the window's workspace.
D.focuswindow = function(a) return hl.dsp.focus({ window = trim(a) }) end
D.forcekillactive = function() return hl.dsp.window.kill() end
D.exit = function() return hl.dsp.exit() end
D.fullscreen = function(a)
    local mode = (trim(a) == "1") and "maximized" or "fullscreen"
    return hl.dsp.window.fullscreen({ mode = mode, action = "toggle" })
end
D.togglefloating = function(a)
    return hl.dsp.window.float({ action = "toggle", window = a ~= "" and a or nil })
end
D.setfloating = function(a) return hl.dsp.window.float({ action = "set", window = a ~= "" and a or nil }) end
D.settiled = function(a) return hl.dsp.window.float({ action = "unset", window = a ~= "" and a or nil }) end
D.centerwindow = function() return hl.dsp.window.center() end
D.pseudo = function() return hl.dsp.window.pseudo() end
D.pin = function() return hl.dsp.window.pin() end
D.togglesplit = function() return hl.dsp.layout("togglesplit") end
D.swapsplit = function() return hl.dsp.layout("swapsplit") end
D.layoutmsg = function(a) return hl.dsp.layout(a) end
D.workspace = function(a) return hl.dsp.focus({ workspace = ws(a) }) end
D.movetoworkspace = function(a)
    local w, win = split_window(a)
    return hl.dsp.window.move({ workspace = ws(w), window = win })
end
D.movetoworkspacesilent = function(a)
    local w, win = split_window(a)
    return hl.dsp.window.move({ workspace = ws(w), window = win, follow = false })
end
D.movefocus = function(a) return hl.dsp.focus({ direction = DIR[trim(a)] or trim(a) }) end
D.movewindow = function(a)
    a = trim(a)
    if a == "" then return hl.dsp.window.drag() end
    return hl.dsp.window.move({ direction = DIR[a] or a })
end
D.swapwindow = function(a) return hl.dsp.window.swap({ direction = DIR[trim(a)] or trim(a) }) end
D.resizewindow = function() return hl.dsp.window.resize() end
D.resizeactive = function(a)
    local x, y, rel = xy(trim(a))
    return hl.dsp.window.resize({ x = x, y = y, relative = rel })
end
D.resizewindowpixel = function(a)
    local p, win = split_window(a)
    local x, y, rel = xy(p)
    return hl.dsp.window.resize({ x = x, y = y, relative = rel, window = win })
end
D.moveactive = function(a)
    local x, y, rel = xy(trim(a))
    return hl.dsp.window.move({ x = x, y = y, relative = rel })
end
D.movewindowpixel = function(a)
    local p, win = split_window(a)
    local x, y, rel = xy(p)
    return hl.dsp.window.move({ x = x, y = y, relative = rel, window = win })
end
D.cyclenext = function() return hl.dsp.window.cycle_next() end
D.bringactivetotop = function() return hl.dsp.window.bring_to_top() end
D.alterzorder = function(a) return hl.dsp.window.alter_zorder({ mode = trim(a) }) end
D.togglespecialworkspace = function(a)
    a = trim(a)
    return hl.dsp.workspace.toggle_special(a ~= "" and a or nil)
end
D.focusmonitor = function(a) return hl.dsp.focus({ monitor = trim(a) }) end
D.movecurrentworkspacetomonitor = function(a) return hl.dsp.workspace.move({ monitor = trim(a) }) end
D.renameworkspace = function(a)
    local id, name = trim(a):match("^(%S+)%s*(.*)$")
    return hl.dsp.workspace.rename({ workspace = ws(id), name = name ~= "" and name or nil })
end
D.togglegroup = function() return hl.dsp.group.toggle() end
D.changegroupactive = function(a)
    a = trim(a)
    if a == "b" or a == "prev" then return hl.dsp.group.prev() end
    if tonumber(a) then return hl.dsp.group.active({ index = tonumber(a) }) end
    return hl.dsp.group.next()
end
D.lockgroups = function(a) return hl.dsp.group.lock({ all = true, action = trim(a) ~= "" and trim(a) or nil }) end
D.submap = function(a) return hl.dsp.submap(trim(a)) end
D.global = function(a) return hl.dsp.global(trim(a)) end
D.pass = function(a) return hl.dsp.pass({ window = trim(a) }) end
D.dpms = function(a)
    local action, mon = trim(a):match("^(%S*)%s*(.*)$")
    return hl.dsp.dpms({ action = action ~= "" and action or "toggle", monitor = mon ~= "" and mon or nil })
end
D.forcerendererreload = function() return hl.dsp.force_renderer_reload() end

function M.dispatcher(name, arg, where)
    name = trim(name or ""):lower()
    local f = D[name]
    if not f then err(where or "dispatch", "unsupported dispatcher '" .. name .. "'"); return nil end
    local ok, d = pcall(f, arg or "")
    if not ok then err(where or "dispatch", name .. " " .. (arg or "") .. ": " .. tostring(d)); return nil end
    return d
end

---------------------------------------------------------------------------
-- Keywords
---------------------------------------------------------------------------

local BIND_FLAGS = { l = "locked", r = "release", e = "repeating", n = "non_consuming",
                     t = "transparent", i = "ignore_mods", o = "long_press", c = "click",
                     g = "drag", p = "dont_inhibit", u = "submap_universal" }

local binds, bind_order = {}, {}
local exec_once = {}

local function bind_key(mods, key)
    local parts = {}
    for m in mods:gmatch("[^%s_+]+") do parts[#parts + 1] = m:upper() end
    parts[#parts + 1] = key
    return table.concat(parts, " + ")
end

local function add_bind(kw, value, where, desc)
    local flags = kw:match("^bind(%a*)$") or ""
    local has_desc = flags:find("d", 1, true) ~= nil
    local nfields = has_desc and 5 or 4
    local f = split(value, ",", nfields)
    local mods, key = f[1] or "", f[2] or ""
    local dname, darg
    if has_desc then desc, dname, darg = f[3], f[4], f[5] or "" else dname, darg = f[3], f[4] or "" end
    local opts = {}
    for c in flags:gmatch(".") do
        if c == "m" then opts.mouse = true
        elseif BIND_FLAGS[c] then opts[BIND_FLAGS[c]] = true end
    end
    if desc and desc ~= "" then opts.description = desc end
    local d
    if opts.mouse then
        local n = trim(dname or ""):lower()
        if n == "movewindow" then d = hl.dsp.window.drag()
        elseif n == "resizewindow" then d = hl.dsp.window.resize() end
    else
        d = M.dispatcher(dname, darg, where)
    end
    if not d then return end
    local id = bind_key(mods, trim(key)) .. "|" .. flags
    if not binds[id] then
        binds[id] = { key = bind_key(mods, trim(key)), opts = opts, list = {}, where = where }
        bind_order[#bind_order + 1] = id
    end
    table.insert(binds[id].list, d)
end

local function flush_binds()
    for _, id in ipairs(bind_order) do
        local b = binds[id]
        local action = b.list[1]
        if #b.list > 1 then
            local list = b.list
            action = function() for _, d in ipairs(list) do hl.dispatch(d) end end
        end
        local ok, e = pcall(hl.bind, b.key, action, next(b.opts) and b.opts or nil)
        if not ok then err(b.where, "bind " .. b.key .. ": " .. tostring(e)) end
    end
end

local function do_monitor(value, where)
    local f = split(value, ",")
    local spec = { output = f[1] or "" }
    if (f[2] or ""):lower() == "disable" or (f[2] or ""):lower() == "disabled" then
        spec.disabled = true
    else
        spec.mode = f[2] ~= "" and f[2] or "preferred"
        spec.position = f[3] ~= "" and f[3] or "auto"
        spec.scale = tonumber(f[4]) or f[4] or "auto"
        local i = 5
        while f[i] do
            local k, v = f[i], f[i + 1]
            if k and v then spec[k] = tonumber(v) or v end
            i = i + 2
        end
    end
    local ok, e = pcall(hl.monitor, spec)
    if not ok then err(where, "monitor " .. value .. ": " .. tostring(e)) end
end

-- "match:class ^(x)$, float on" -> { match = { class = "^(x)$" }, float = true }
local function rule_spec(value)
    local spec = { match = {} }
    for _, part in ipairs(split(value, ",")) do
        local mk, mv = part:match("^match:(%S+)%s+(.+)$")
        if mk then
            if BOOL[mv:lower()] ~= nil and not tonumber(mv) then mv = BOOL[mv:lower()] end
            spec.match[mk] = mv
        else
            local k, v = part:match("^(%S+)%s*(.*)$")
            if k then
                if v == "" or v:lower() == "on" or v:lower() == "true" then spec[k] = true
                elseif v:lower() == "off" or v:lower() == "false" then spec[k] = false
                else spec[k] = tonumber(v) or v end
            end
        end
    end
    return spec
end

local WS_KEYS = { gapsin = "gaps_in", gapsout = "gaps_out", bordersize = "border_size",
                  border = "no_border", rounding = "no_rounding", shadow = "no_shadow",
                  decorate = "decorate", persistent = "persistent", default = "default",
                  monitor = "monitor", defaultName = "default_name", layout = "layout",
                  ["on-created-empty"] = "on_created_empty" }
local WS_INVERT = { no_border = true, no_rounding = true, no_shadow = true }

local function do_workspace(value, where)
    local f = split(value, ",")
    local spec = { workspace = f[1] }
    local n = 0
    for i = 2, #f do
        local k, v = f[i]:match("^([%w%-]+):(.*)$")
        local key = k and WS_KEYS[k]
        if key then
            local b = BOOL[v:lower()]
            if WS_INVERT[key] and b ~= nil then spec[key] = not b
            elseif b ~= nil and not tonumber(v) then spec[key] = b
            else spec[key] = tonumber(v) or v end
            n = n + 1
        elseif f[i] ~= "" then
            err(where, "workspace rule '" .. f[i] .. "' not supported")
        end
    end
    if n == 0 then return end
    local ok, e = pcall(hl.workspace_rule, spec)
    if not ok then err(where, "workspace " .. value .. ": " .. tostring(e)) end
end

local function do_gesture(value, where)
    local f = split(value, ",", 5)
    local spec = { fingers = tonumber(f[1]), direction = f[2], action = f[3] }
    if f[3] == "dispatcher" then
        local name, arg = f[4], f[5] or ""
        spec.action = function() local d = M.dispatcher(name, arg, where); if d then hl.dispatch(d) end end
    end
    local ok, e = pcall(hl.gesture, spec)
    if not ok then err(where, "gesture " .. value .. ": " .. tostring(e)) end
end

local function do_animation(value, where)
    local f = split(value, ",", 5)
    local spec = { leaf = f[1], enabled = f[2] == "1" or f[2] == "true" }
    if spec.enabled or f[3] then
        spec.speed = tonumber(f[3])
        if f[4] and f[4] ~= "" then spec.bezier = f[4] end
        if f[5] and f[5] ~= "" then spec.style = f[5] end
    end
    local ok, e = pcall(hl.animation, spec)
    if not ok then err(where, "animation " .. value .. ": " .. tostring(e)) end
end

local function do_bezier(value, where)
    local f = split(value, ",")
    local ok, e = pcall(hl.curve, f[1], { type = "bezier",
        points = { { tonumber(f[2]), tonumber(f[3]) }, { tonumber(f[4]), tonumber(f[5]) } } })
    if not ok then err(where, "bezier " .. value .. ": " .. tostring(e)) end
end

---------------------------------------------------------------------------
-- Parser
---------------------------------------------------------------------------

local vars = {}
local loaded = {}

local function subst(s)
    return (s:gsub("%$([%w_]+)", function(n) return vars[n] end))
end

local function strip_comment(line)
    -- "##" is an escaped "#"; a lone "#" starts a comment.
    local out, desc = {}, nil
    local i = 1
    while i <= #line do
        local c = line:sub(i, i)
        if c == "#" then
            if line:sub(i + 1, i + 1) == "#" then out[#out + 1] = "#"; i = i + 2
            else desc = line:sub(i):match("^#:%s*(.-)%s*$"); break end
        else
            out[#out + 1] = c; i = i + 1
        end
    end
    return table.concat(out), desc
end

function M.load(path)
    path = expand(path)
    if loaded[path] then return end
    local f = io.open(path, "r")
    if not f then return end
    loaded[path] = true
    local stack = {}
    local device = nil
    local short = path:gsub("^" .. HOME:gsub("%p", "%%%0"), "~")

    local function handle(raw, where)
        local line, desc = strip_comment(raw)
        line = trim(line)
        if line == "" then return end

        local sec = line:match("^([%w_%.:%-]+)%s*{$")
        if sec then
            stack[#stack + 1] = sec
            if sec == "device" then device = {} end
            return
        end
        if line == "}" then
            local closed = table.remove(stack)
            if closed == "device" and device then
                local ok, e = pcall(hl.device, device)
                if not ok then err(where, "device: " .. tostring(e)) end
                device = nil
            end
            return
        end

        local key, value = line:match("^([^=]-)%s*=%s*(.*)$")
        if not key then err(where, "cannot parse: " .. line); return end
        key = trim(key)
        local vname = key:match("^%$([%w_]+)$")
        if vname then vars[vname] = subst(value); return end
        value = subst(value)

            if device then
                device[key:gsub("%-", "_")] = convert("input." .. key:gsub("%-", "_"), value)
            elseif #stack == 0 then
                if key == "source" then
                    local p = expand(value)
                    if file_exists(p) then M.load(p) end
                elseif key == "monitor" then do_monitor(value, where)
                elseif key == "env" then
                    local kv = split(value, ",", 2)
                    local ok, e = pcall(hl.env, kv[1], kv[2] or "")
                    if not ok then err(where, "env: " .. tostring(e)) end
                elseif key == "exec-once" then exec_once[#exec_once + 1] = value
                elseif key == "exec" then
                    local ok, e = pcall(hl.exec_cmd, value)
                    if not ok then err(where, "exec: " .. tostring(e)) end
                elseif key:match("^bind%a*$") then add_bind(key, value, where, desc)
                elseif key == "unbind" then
                    local kv = split(value, ",")
                    pcall(hl.unbind, bind_key(kv[1] or "", kv[2] or ""))
                elseif key == "workspace" then do_workspace(value, where)
                elseif key == "windowrule" or key == "windowrulev2" then
                    local ok, e = pcall(hl.window_rule, rule_spec(value))
                    if not ok then err(where, "windowrule " .. value .. ": " .. tostring(e)) end
                elseif key == "layerrule" then
                    local ok, e = pcall(hl.layer_rule, rule_spec(value))
                    if not ok then err(where, "layerrule " .. value .. ": " .. tostring(e)) end
                elseif key == "gesture" then do_gesture(value, where)
                elseif key == "bezier" then do_bezier(value, where)
                elseif key == "animation" then do_animation(value, where)
                else
                    set_option(key, value, where)
                end
            else
                local top = stack[1]
                if top == "animations" and key == "bezier" then do_bezier(value, where)
                elseif top == "animations" and key == "animation" then do_animation(value, where)
                else
                    set_option(table.concat(stack, ".") .. "." .. key, value, where)
                end
            end
    end

    local n = 0
    for raw in f:lines() do
        n = n + 1
        local where = short .. ":" .. n
        local ok, e = pcall(handle, raw, where)
        if not ok then err(where, e) end
    end
    f:close()
end

-- Finish: register binds and startup commands, write the problem log.
function M.finish()
    flush_binds()
    local cmds = exec_once
    hl.on("hyprland.start", function()
        for _, c in ipairs(cmds) do pcall(hl.exec_cmd, c) end
    end)
    local dir = (os.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")) .. "/aether"
    os.execute("mkdir -p '" .. dir .. "'")
    local log = io.open(dir .. "/hypr-lua.log", "w")
    if log then
        log:write(os.date("%Y-%m-%d %H:%M:%S"), "  ", #M.errors, " problem(s)\n")
        for _, e in ipairs(M.errors) do log:write(e, "\n") end
        log:close()
    end
end

---------------------------------------------------------------------------
-- Runtime API for the hyprctl shim:  hyprctl dispatch 'aether.keyword(...)'
---------------------------------------------------------------------------

aether = {
    keyword = function(key, value)
        key = trim(key)
        if key == "monitor" then do_monitor(value, "hyprctl keyword")
        elseif key:match("^bind%a*$") then
            binds, bind_order = {}, {}
            add_bind(key, value, "hyprctl keyword")
            flush_binds()
        elseif key == "windowrule" or key == "windowrulev2" then hl.window_rule(rule_spec(value))
        elseif key == "layerrule" then hl.layer_rule(rule_spec(value))
        elseif key == "workspace" then do_workspace(value, "hyprctl keyword")
        elseif key == "animation" then do_animation(value, "hyprctl keyword")
        elseif key == "bezier" then do_bezier(value, "hyprctl keyword")
        elseif key == "env" then local kv = split(value, ",", 2); hl.env(kv[1], kv[2] or "")
        else set_option(key, value, "hyprctl keyword") end
        return hl.dsp.no_op()
    end,
    dispatch = function(name, arg)
        return M.dispatcher(name, arg, "hyprctl dispatch") or hl.dsp.no_op()
    end,
}

return M
