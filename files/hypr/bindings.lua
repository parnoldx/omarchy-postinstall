-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Super+Shift+B was a second Browser binding (Super+Shift+Return remains Browser).
-- Open the Bitwarden wrapper (rbw-tui in a floating terminal), same as the
-- launcher desktop entry and the Passwörter menu item.
hl.unbind("SUPER + SHIFT + B")
o.bind("SUPER + SHIFT + B", "Bitwarden", "omarchy-launch-tui --app-id=TUI.float rbw-tui")

-- Voxtype dictation (https://voxtype.io). Transcript lands in a runtime file;
-- the orchestrator routes it (insert / rewrite / ask / do).
-- Ctrl+F1 inserts. Ctrl+Shift+F1 rewrites then inserts.
-- Ctrl+F2 asks (card). Ctrl+Shift+F2 does it via the default agent + skills.
-- Unbind first: Lua reload adds binds and does not replace them.
hl.unbind("CTRL + F1")
hl.unbind("CTRL + F2")
hl.unbind("CTRL + SHIFT + F1")
hl.unbind("CTRL + SHIFT + F2")
o.bind("CTRL + F1", "Toggle dictation", os.getenv("HOME") .. "/.local/bin/voxtype-toggle")
o.bind("CTRL + SHIFT + F1", "Toggle dictation (agent)", os.getenv("HOME") .. "/.local/bin/voxtype-agent-toggle")
o.bind("CTRL + F2", "Toggle dictation (ask)", os.getenv("HOME") .. "/.local/bin/voxtype-ask-toggle")
o.bind("CTRL + SHIFT + F2", "Toggle dictation (do)", os.getenv("HOME") .. "/.local/bin/voxtype-do-toggle")

-- Fix once, remembered: select the corrected word, press Ctrl+F3, confirm.
hl.unbind("CTRL + F3")
o.bind("CTRL + F3", "voxtype: learn correction", os.getenv("HOME") .. "/.local/bin/voxtype-fix")

-- Super+Shift+E was Hey Email. Toggle Thunderbird (mail) on its special
-- workspace. Launch puts the next matching window there and shows it; later
-- presses show/hide.
-- Super+Shift+F is the stock File manager bind (see flea block below).

hl.unbind("SUPER + SHIFT + E")
hl.unbind("SUPER + SHIFT + A")

o.window({ class = ".*[Tt]hunderbird.*" }, { workspace = "special:mail" })

local function window_class(win)
  return ((win.class or "") .. " " .. (win.initial_class or "")):lower()
end

local function on_special(win, name)
  local ws = win.workspace
  if not ws then
    return false
  end
  return ws.name == "special:" .. name or (ws.special and (ws.name == name or ws.config_name == name))
end

local function special_visible(name)
  local ws = hl.get_active_special_workspace()
  if not ws then
    return false
  end
  return ws.name == "special:" .. name or ws.name == name or ws.config_name == name
end

local function show_special(name)
  if not special_visible(name) then
    hl.dispatch(hl.dsp.workspace.toggle_special(name))
  end
end

local function move_to_special(win, name)
  if on_special(win, name) then
    return
  end
  hl.dispatch(hl.dsp.window.move({ workspace = "special:" .. name, window = win, follow = false }))
end

local overlays = {
  mail = {
    -- MOZ_LEGACY_HOME=1 works around Thunderbird <=153.x creating an empty
    -- ~/thunderbird folder on every start (bug in its XDG-migration code;
    -- upstream fix is already in mozilla-central).
    -- REMOVE THIS when your thunderbird is newer than 153.x AND deleting
    -- ~/thunderbird and starting Thunderbird once no longer recreates it.
    launch = o.launch("env MOZ_LEGACY_HOME=1 thunderbird"),
    is_app = function(win)
      return window_class(win):find("thunderbird", 1, true) ~= nil
    end,
  },
}

local pending = {}

local function collect_overlay_windows(name)
  local spec = overlays[name]
  local wins = {}
  for _, win in ipairs(hl.get_windows()) do
    if spec.is_app(win) then
      table.insert(wins, win)
    end
  end
  return wins
end

local function claim_overlay_window(win)
  if not win then
    return
  end

  for name, spec in pairs(overlays) do
    if spec.is_app(win) then
      move_to_special(win, name)
      if pending[name] then
        show_special(name)
        pending[name] = nil
      end
      return
    end
  end
end

hl.on("window.open", claim_overlay_window)
hl.on("window.class", claim_overlay_window)

local function toggle_overlay(name)
  local spec = overlays[name]
  local wins = collect_overlay_windows(name)

  if #wins == 0 then
    if pending[name] then
      hl.dispatch(hl.dsp.workspace.toggle_special(name))
      return
    end

    pending[name] = true
    hl.dispatch(hl.dsp.exec_cmd(spec.launch, { workspace = "special:" .. name }))
    show_special(name)
    hl.timer(function()
      pending[name] = nil
      for _, win in ipairs(collect_overlay_windows(name)) do
        move_to_special(win, name)
      end
    end, { timeout = 5000, type = "oneshot" })
    return
  end

  for _, win in ipairs(wins) do
    move_to_special(win, name)
  end
  hl.dispatch(hl.dsp.workspace.toggle_special(name))
end

o.bind("SUPER + SHIFT + E", "Toggle Thunderbird", function()
  toggle_overlay("mail")
end)

-- Super+A (was Shift+A): scratchpad toggle of special:ai, same pattern as
-- Super+S. An empty workspace always spawns the persistent herdr session in a
-- terminal, so the first open is always herdr; later presses show/hide.
-- Re-running the Lua on reload doesn't clear earlier binds, so unbind first.
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + A", "Toggle Herdr", function()
  local empty = true
  for _, win in ipairs(hl.get_windows()) do
    if on_special(win, "ai") then
      empty = false
      break
    end
  end
  if empty then
    hl.dispatch(hl.dsp.exec_cmd("omarchy-launch-terminal-herdr", { workspace = "special:ai" }))
  end
  hl.dispatch(hl.dsp.workspace.toggle_special("ai"))
end)

-- Super+J was toggle split (dwindle only). Dispatch the native action for
-- the active workspace layout: togglesplit on dwindle, consume_or_expel on
-- scrolling. Special workspaces take precedence over regular ones.
hl.unbind("SUPER + J")

local window_layout_dispatchers = {
  dwindle = hl.dsp.layout("togglesplit"),
  scrolling = hl.dsp.layout("consume_or_expel prev"),
}

local function toggle_window_layout()
  local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
  local dispatcher = workspace and window_layout_dispatchers[workspace.tiled_layout]

  if dispatcher then
    hl.dispatch(dispatcher)
  end
end

o.bind("SUPER + J", "Toggle window split / consume or expel", toggle_window_layout)

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Rebind SUPER+SHIFT+G from Signal / WhatsApp Web to the local Quickshell client.
-- SUPER+SHIFT+W stays Omawrite. SUPER+SHIFT+ALT+G still opens WhatsApp Web.
hl.unbind("SUPER + SHIFT + G")
o.bind("SUPER + SHIFT + G", "WhatsApp", os.getenv("HOME") .. "/.local/bin/whatsapp-gui --toggle")

-- Swap the Display and Calendar panel keybindings.
-- Defaults: SUPER+CTRL+D = Display, SUPER+CTRL+ALT+D = Calendar.
-- After this: SUPER+CTRL+D = Calendar, SUPER+CTRL+ALT+D = Display.
hl.unbind("SUPER + CTRL + D")
hl.unbind("SUPER + CTRL + ALT + D")
o.bind("SUPER + CTRL + ALT + D", "Display", "omarchy-shell shell toggle omarchy.monitor")
o.bind("SUPER + CTRL + D", "Calendar", "omarchy-shell shell toggle omarchy.clock")

-- Open/toggle Mailbox email notification panel
hl.unbind("SUPER + SHIFT + ALT + E")
o.bind("SUPER + SHIFT + ALT + E", "Mailbox panel", "omarchy-shell shell toggle mailbox.email")

-- fzf + yazi file finder (Walker `-m files` replacement).
-- SUPER+CTRL+F was Tiled full screen (still on SUPER+ALT+F as Full width;
-- SUPER+F remains Full screen). The script launches its own terminal.
-- Floating size for org.omarchy.finder is set in looknfeel.lua.
local fzfyazi = os.getenv("HOME") .. "/.config/hypr/fzfyazi/fuzzy-file-names.sh"
hl.unbind("SUPER + CTRL + F") -- default: Tiled full screen
o.bind("SUPER + CTRL + F", "Search files (Yazi)", fzfyazi)
o.bind("SUPER + CTRL + SHIFT + F", "Browse files (fuzzy)", fzfyazi .. " browse")
o.bind("SUPER + CTRL + ALT + F", "Search by file type", fzfyazi .. " type")


-- flea --default: superseded — restored Omarchy defaults (nautilus)
-- Re-running the Lua on reload doesn't clear earlier binds, so unbind first.
hl.unbind("SUPER + SHIFT + F")
o.bind("SUPER + SHIFT + F", "File manager", { omarchy = "nautilus" })
hl.unbind("SUPER + ALT + SHIFT + F")
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)", { omarchy = "nautilus-cwd" })
-- flea --default: end.

o.bind("SUPER + N", "ToDo", "omarchy-shell shell toggle pa.todo '{}'")

-- Super+M was unbound. Launch the Mailbox desktop client.
hl.unbind("SUPER + M")
o.bind("SUPER + M", "Mailbox", { launch = "mailbox-gui" })

-- YouTube Music plugin: Super+Ctrl+Shift+M opens the player popup, and
-- Super+K expands search while that popup is open. Super+K still opens
-- the Keybindings menu everywhere else.
pcall(dofile, os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.itsdotdev.youtube-music/hypr-bindings.lua")

-- Plugin file toggles the player; always open it instead.
hl.unbind("SUPER + CTRL + SHIFT + M")
o.bind(
  "SUPER + CTRL + SHIFT + M",
  "YouTube Music",
  "omarchy-shell shell summon io.github.itsdotdev.youtube-music"
)

-- chord-expander (snippet expander)
pcall(dofile, os.getenv("HOME") .. "/.config/chord-expander/submap.lua")

-- Reprieve-lite: SUPER+W parks the focused window on a hidden special
-- workspace and really closes it after 5s. SUPER+Z within those 5s undoes it
-- (same live window, back on its workspace, fullscreen refocused).
local REPRIEVE_WS = "special:reprieve"
local reprieved = {} -- most recent last: { win, home, fullscreen, timer }

hl.unbind("SUPER + W") -- default: Close window

local function is_parked(win)
  local ws = win.workspace
  return ws ~= nil and ws.name == REPRIEVE_WS
end

-- State (and timers) don't survive a Hyprland reload; anything still parked
-- when this file re-runs is past its reprieve — close it.
for _, win in ipairs(hl.get_windows()) do
  if is_parked(win) then
    hl.dispatch(hl.dsp.window.close({ window = win }))
  end
end

o.bind("SUPER + W", "Close window (5s undo)", function()
  local win = hl.get_active_window()
  if not win or is_parked(win) then
    return
  end
  local entry = {
    win = win,
    home = win.workspace and win.workspace.name or "1",
    fullscreen = win.fullscreen, -- 0 none, 1 maximized, 2 fullscreen
  }
  table.insert(reprieved, entry)
  hl.dispatch(hl.dsp.window.move({ workspace = REPRIEVE_WS, window = win, follow = false }))
  entry.timer = hl.timer(function()
    for i, e in ipairs(reprieved) do
      if e == entry then
        table.remove(reprieved, i)
        break
      end
    end
    hl.dispatch(hl.dsp.window.close({ window = win }))
  end, { timeout = 5000, type = "oneshot" })
end)

o.bind("SUPER + Z", "Undo close", function()
  local entry = table.remove(reprieved)
  if not entry then
    return
  end
  if entry.timer then
    entry.timer:set_enabled(false)
  end
  hl.dispatch(hl.dsp.window.move({ workspace = entry.home, window = entry.win }))
  if entry.fullscreen == 1 or entry.fullscreen == 2 then
    hl.dispatch(hl.dsp.window.fullscreen({
      mode = entry.fullscreen == 1 and "maximized" or "fullscreen",
      action = "set",
      window = entry.win,
    }))
  end
  hl.dispatch(hl.dsp.focus({ window = entry.win }))
end)
