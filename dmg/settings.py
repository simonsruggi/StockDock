# dmgbuild settings, used by scripts/make-dmg.sh:
#   dmgbuild -s dmg/settings.py -D app=path/StockDock.app "StockDock" StockDock.dmg
import os.path

app = defines["app"]  # noqa: F821 (injected by dmgbuild)
here = os.path.abspath("dmg")  # dmgbuild execs this file without __file__; make-dmg.sh runs from the repo root

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents/Resources/AppIcon.icns")
badge_icon = None

background = os.path.join(here, "background.tiff")
window_rect = ((200, 120), (660, 428))  # +28 pt title bar, so the whole 660x400 background shows
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {
    os.path.basename(app): (170, 190),
    "Applications": (490, 190),
}
