#!/bin/bash

sudo pacman -S --noconfirm sbsigntools sbctl efibootmgr

echo "Reinstalling Grub.."

sudo grub-install --target=x86_64-efi --efi-directory=esp --bootloader-id=GRUB --modules="tpm" --disable-shim-lock | exit 1

sh update-grub.sh

echo "Reinstalled Grub.."

echo "Creating and enrolling keys"
sudo sbctl create-keys
sudo sbctl enroll-keys -m

echo "Signing keys.."
sudo sbctl verify

