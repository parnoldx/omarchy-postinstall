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

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Handy dictation (https://handy.computer). SIGUSR2 is the Wayland control
-- path; `handy --toggle-transcription` hangs on single-instance D-Bus here.
o.bind("CTRL + F1", "Toggle dictation", os.getenv("HOME") .. "/.local/bin/handy-toggle")

-- Super+Shift+E was Hey Email. Super+Shift+A was ChatGPT.
-- Toggle Thunderbird / Herdr on special workspaces. Launch puts the next
-- matching window on the overlay and shows it; later presses show/hide.
hl.unbind("SUPER + SHIFT + E")
hl.unbind("SUPER + SHIFT + A")

o.window({ class = ".*[Tt]hunderbird.*" }, { workspace = "special:mail" })
o.window({ class = ".*[Hh]erdr.*" }, { workspace = "special:herdr" })

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
    launch = o.launch("thunderbird"),
    is_app = function(win)
      return window_class(win):find("thunderbird", 1, true) ~= nil
    end,
  },
  herdr = {
    -- Dedicated Foot window so Neo compose works and the overlay stays
    -- identifiable (app-id org.omarchy.herdr) instead of a generic foot.
    launch = o.launch("foot --app-id=org.omarchy.herdr herdr"),
    is_app = function(win)
      return window_class(win):find("herdr", 1, true) ~= nil
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

local function is_terminal(win)
  local class = window_class(win)
  return class:find("herdr", 1, true)
    or class:find("ghostty", 1, true)
    or class:find("alacritty", 1, true)
    or class:find("kitty", 1, true)
    or class:find("foot", 1, true)
    or class:find("org.omarchy", 1, true)
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

  -- Herdr's class can land after map, or stay as the terminal class.
  if pending.herdr and is_terminal(win) then
    move_to_special(win, "herdr")
    show_special("herdr")
    pending.herdr = nil
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

o.bind("SUPER + SHIFT + A", "Toggle Herdr", function()
  toggle_overlay("herdr")
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
