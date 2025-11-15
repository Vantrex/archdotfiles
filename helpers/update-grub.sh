#!/bin/bash

sudo mkdir -p /boot/efi
sudo mount /dev/nvme0n1p1 /boot/efi
sudo ls /boot/efi/EFI | exit 1

sudo grub-mkconfig -o /boot/grub/grub.cfg
