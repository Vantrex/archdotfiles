#!/bin/bash
sudo pacman -Sy --needed --noconfirm plymouth


set -euo pipefail

CONF="/etc/mkinitcpio.conf"

HOOK="plymouth"

# Make a backup
sudo cp "$CONF" "$CONF.$(date +%Y%m%d-%H%M%S).bak"

# Modify HOOKS line
sudo awk -v hook="$HOOK" '
/^[[:space:]]*HOOKS=/ {
    # Get the part inside parentheses: (base udev ... filesystems)
    if (match($0, /\(.*\)/, a)) {
        hooks_str = a[0]
        gsub(/^\(|\)$/, "", hooks_str)        # remove surrounding parentheses
        n = split(hooks_str, hooks, /[ \t]+/)

        # Check if hook already present
        for (i = 1; i <= n; i++) {
            if (hooks[i] == hook) {
                print $0
                next
            }
        }

        # Build new hook list: insert before "encrypt" if present
        out = ""
        inserted = 0
        for (i = 1; i <= n; i++) {
            if (!inserted && hooks[i] == "udev") {
                out = out hook " "
                inserted = 1
            }
            out = out hooks[i]
            if (i < n) out = out " "
        }

        # If "filesystems" wasn’t found, append hook at the end
        if (!inserted) {
            if (out != "") out = out " "
            out = out hook
        }

        # Replace old ( ... ) with new ( out )
        sub(/\(.*\)/, "(" out ")", $0)
        print $0
        next
    }
}
{ print }
' "$CONF" | sudo tee "$CONF.tmp" >/dev/null

sudo mv "$CONF.tmp" "$CONF"

echo "Hook \"$HOOK\" ensured in HOOKS=() in $CONF"

MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"

echo "Regenerating initframes.."
sudo mkinitcpio -P

sudo pacman -S --needed --noconfirm dracut
echo 'add_dracutmodules+=" plymouth "' | sudo tee /etc/dracut.conf.d/myflags.conf

sleep 5
echo "You might want to add the following modules in '/etc/mkinitcpio.conf' if you're running on nvidia: $MODULES" >> ~/IMPORTANT.txt 
sleep 20
