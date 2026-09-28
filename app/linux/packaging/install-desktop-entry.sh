#!/bin/sh
# Adds Lich Repo Browser to your applications menu (current user only),
# pointing at the folder this script is in. Run it again if you move the
# folder; delete the two files it prints to remove it.
set -e
here=$(cd "$(dirname "$0")" && pwd)
id=com.lillymara.lich_repo_browser
share="${XDG_DATA_HOME:-$HOME/.local/share}"
icon="$share/icons/hicolor/256x256/apps/$id.png"
entry="$share/applications/$id.desktop"
mkdir -p "$(dirname "$icon")" "$(dirname "$entry")"
cp "$here/data/app_icon.png" "$icon"
cat > "$entry" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Lich Repo Browser
Comment=Browse and download Lich scripts
Exec="$here/lich_repo_browser"
Icon=$id
Terminal=false
Categories=Utility;
StartupWMClass=lich_repo_browser
DESKTOP
update-desktop-database "$(dirname "$entry")" 2>/dev/null || true
echo "Added Lich Repo Browser to your applications menu:"
echo "  $entry"
echo "  $icon"
