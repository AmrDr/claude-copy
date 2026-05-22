-- claude-copy.lua
-- Hammerspoon module for Claude Copy.
-- Source it from ~/.hammerspoon/init.lua:  require("claude-copy")
-- (The install.sh does this for you.)

local M = {}

local CFG_DIR = os.getenv("HOME") .. "/.config/claude-copy"
local CONFIG  = CFG_DIR .. "/config.ini"
local CORE    = CFG_DIR .. "/claude_copy.py"

-- Minimal INI reader (sections + key=value). Tolerates # and ; comments.
local function readConfig(path)
    local cfg = { hotkey = "ctrl+alt+c" }
    local f = io.open(path, "r")
    if not f then return cfg end
    local section = nil
    for line in f:lines() do
        local t = (line:gsub("^%s+", ""):gsub("%s+$", ""))
        if t ~= "" and t:sub(1, 1) ~= "#" and t:sub(1, 1) ~= ";" then
            local s = t:match("^%[(.-)%]$")
            if s then
                section = s:lower()
            else
                local k, v = t:match("^([^=]+)=(.*)$")
                if k and v then
                    k = (k:gsub("%s+$", "")):lower()
                    v = v:gsub("^%s+", "")
                    if section == "hotkey" and k == "combo" then cfg.hotkey = v end
                end
            end
        end
    end
    f:close()
    return cfg
end

-- "ctrl+alt+c" -> ({"ctrl","alt"}, "c")
local function parseHotkey(s)
    local modmap = {
        ctrl = "ctrl", control = "ctrl",
        alt = "alt", option = "alt",
        shift = "shift",
        cmd = "cmd", command = "cmd", super = "cmd", win = "cmd", meta = "cmd",
    }
    local mods, key = {}, nil
    for part in string.gmatch(s:lower(), "[^%+]+") do
        part = (part:gsub("^%s+", ""):gsub("%s+$", ""))
        local m = modmap[part]
        if m then table.insert(mods, m)
        elseif part ~= "" then key = part end
    end
    return mods, key
end

local function shellQuote(s)
    return "'" .. (s or ""):gsub("'", [['"'"']]) .. "'"
end

local function copy()
    local title = ""
    local app = hs.application.frontmostApplication()
    if app then
        local win = app:focusedWindow()
        if win then title = win:title() or "" end
    end

    local cmd = "python3 " .. shellQuote(CORE) .. " --window-title " .. shellQuote(title)
    local out, ok, _, rc = hs.execute(cmd, true)
    out = out or ""
    local firstLine = out:match("[^\r\n]+") or ""
    if ok and firstLine:sub(1, 3) == "OK " then
        hs.alert.show("Copied: " .. firstLine:sub(4), 1.2)
    elseif firstLine:sub(1, 4) == "ERR " then
        hs.alert.show("Error: " .. firstLine:sub(5), 2)
    else
        hs.alert.show("Claude Copy failed (rc=" .. tostring(rc) .. ")", 2)
    end
end

function M.start()
    local cfg = readConfig(CONFIG)
    local mods, key = parseHotkey(cfg.hotkey)
    if not key then
        hs.alert.show("Claude Copy: bad hotkey '" .. cfg.hotkey .. "'", 3)
        return
    end
    if M._binding then M._binding:delete() end
    M._binding = hs.hotkey.bind(mods, key, copy)
    hs.alert.show("Claude Copy: " .. cfg.hotkey, 1.5)
end

M.start()
return M
