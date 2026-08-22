-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Handy dictation daemon (hidden; hotkeys via Hyprland bindings)
o.launch_on_start("handy --start-hidden")

-- Handy maps a 680x570 settings window. If that window is visible (launcher,
-- or Linux ignoring --start-hidden when the tray is off), keep it a centered
-- float so it cannot tile across the whole workspace at login.
o.window({ class = "^handy$" }, {
  float = true,
  center = true,
  suppress_event = "fullscreen maximize",
})
