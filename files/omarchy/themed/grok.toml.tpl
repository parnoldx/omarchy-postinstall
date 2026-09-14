# Grok TUI theme — filled from the active Omarchy palette.
#
# This is a user template: `omarchy theme set` regenerates
# ~/.local/state/omarchy/current/theme/grok.toml from it.
# Edit the mappings here; do not edit the generated file.
#
# Grok has no loadable custom theme, so a theme-set hook overlays
# these slots onto the compiled TokyoNight palette. Restart Grok
# after a theme change.

name = "omarchy"
base = "{{ theme_type }}"

[colors]
bg_base = "{{ background }}"
bg_light = "{{ lighter_background }}"
bg_dark = "{{ dark_background }}"
bg_highlight = "{{ selection }}"
bg_hover = "{{ mix background foreground 10% }}"
bg_terminal = "{{ background }}"
bg_visual = "{{ mix background accent 18% }}"

accent_user = "{{ accent }}"
accent_assistant = "{{ bright_magenta }}"
accent_thinking = "{{ muted }}"
accent_tool = "{{ dark_foreground }}"
accent_system = "{{ blue }}"
accent_error = "{{ red }}"
accent_success = "{{ green }}"
accent_running = "{{ bright_magenta }}"
accent_skill = "{{ cyan }}"
accent_plan = "{{ yellow }}"
accent_verify = "{{ magenta }}"
accent_remember = "{{ green }}"
accent_model = "{{ cyan }}"

text_primary = "{{ bright_foreground }}"
text_secondary = "{{ foreground }}"
gray_dim = "{{ muted }}"
gray = "{{ dark_foreground }}"
gray_bright = "{{ light_foreground }}"

command = "{{ yellow }}"
path = "{{ orange }}"
running = "{{ bright_cyan }}"
warning = "{{ yellow }}"
fuzzy_accent = "{{ accent }}"

selection_border = "{{ mix accent background 45% }}"
hover_border = "{{ mix background foreground 18% }}"
prompt_border = "{{ mix accent background 50% }}"
prompt_border_active = "{{ mix accent background 32% }}"

scrollbar_bg = "{{ dark_background }}"
scrollbar_fg = "{{ selection }}"

diff_delete_bg = "{{ mix background red 15% }}"
diff_delete_fg = "{{ red }}"
diff_insert_bg = "{{ mix background green 15% }}"
diff_insert_fg = "{{ green }}"
diff_equal_fg = "{{ dark_foreground }}"
diff_gutter_fg = "{{ dark_foreground }}"

paste_bg = "{{ dark_background }}"
paste_fg = "{{ foreground }}"
paste_dim = "{{ muted }}"

md_heading_h1 = "{{ cyan }}"
md_heading_h2 = "{{ blue }}"
md_heading_h3 = "{{ orange }}"
md_heading_h4 = "{{ red }}"
md_heading_h5 = "{{ green }}"
md_heading_h6 = "{{ magenta }}"
md_code = "{{ bright_green }}"
md_code_bg = "{{ selection }}"
md_text = "{{ bright_foreground }}"
md_muted = "{{ dark_foreground }}"
md_task_checked = "{{ bright_cyan }}"
md_task_unchecked = "{{ blue }}"
link_fg = "{{ accent }}"
