#!/bin/bash
sudo pacman -Sy --noconfirm zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# install fzf
sudo pacman -S fzf
