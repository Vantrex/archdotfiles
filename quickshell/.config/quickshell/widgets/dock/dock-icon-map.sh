#!/bin/sh

emit_desktop_entries() {
    dir=$1
    [ -d "$dir" ] || return

    find "$dir" -maxdepth 1 -type f -name '*.desktop' -print |
        while IFS= read -r file; do
            id=${file##*/}
            id=${id%.desktop}
            awk -F= -v id="$id" '
                /^\[Desktop Entry\]$/ {
                    in_entry = 1
                    next
                }
                /^\[/ {
                    if (in_entry) exit
                    next
                }
                in_entry && $1 == "StartupWMClass" && startup_class == "" {
                    startup_class = substr($0, index($0, "=") + 1)
                }
                in_entry && $1 == "Icon" && icon == "" {
                    icon = substr($0, index($0, "=") + 1)
                }
                END {
                    if (icon != "") printf "%s\t%s\t%s\n", id, startup_class, icon
                }
            ' "$file"
        done
}

emit_desktop_entries "$HOME/.local/share/applications"
emit_desktop_entries /usr/share/applications
