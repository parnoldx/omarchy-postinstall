-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
hl.config({
  general = {
    -- Tighter spacing between windows (defaults: 5 / 10).
    gaps_in = 2,
    gaps_out = 4,
  },

  decoration = {
    -- Soften the default square corners a little.
    rounding = 4,
  },
})

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- Fuzzy file finder (SUPER+CTRL+F). Wide enough for yazi's list + preview.
-- https://wiki.hypr.land/Configuring/Basics/Window-Rules/
o.window("^(org\\.omarchy\\.finder)$", { name = "windowrule-fzfyazi-finder", float = true })
o.window("^(org\\.omarchy\\.finder)$", { center = true })
o.window("^(org\\.omarchy\\.finder)$", { size = { "monitor_w * 0.82", "monitor_h * 0.82" } })
