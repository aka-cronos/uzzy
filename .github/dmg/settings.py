# dmgbuild settings for Uzzy.dmg (issue #115, variant C3). dmgbuild writes the
# window's .DS_Store itself, so no Finder automation runs on the headless
# runner. Used by .github/workflows/release.yml, from the repository root:
#
#   dmgbuild -s .github/dmg/settings.py -D app=path/to/Uzzy.app Uzzy Uzzy.dmg

app = defines["app"]

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = ["Uzzy.app"]

# dmgbuild finds background@2x.png next to it and combines both into one
# HiDPI TIFF with tiffutil -cathidpicheck.
background = ".github/dmg/background.png"

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
default_view = "icon-view"
include_icon_view_settings = True
arrange_by = None
label_pos = "bottom"
icon_size = 128
text_size = 13

# The background is 640x400; Finder's window bounds also include its ~31pt
# title bar.
window_rect = ((200, 160), (640, 400 + 31))
icon_locations = {"Uzzy.app": (170, 205), "Applications": (470, 205)}
