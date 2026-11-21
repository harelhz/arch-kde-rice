#!/usr/bin/env bash
# Installs this rice into the current user's home.
# Anything it would overwrite is backed up to ~/.rice-backup-<date>/ first.
#   ./install.sh            install configs + themes + wallpaper
#   ./install.sh --deps     also install the packages it needs (pacman + yay)
#   ./install.sh --sddm     also install the SDDM login theme config (needs sudo)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HOME/.rice-backup-$(date +%Y%m%d-%H%M%S)"
WITH_DEPS=0; WITH_SDDM=0
for a in "$@"; do
  case "$a" in
    --deps) WITH_DEPS=1 ;;
    --sddm) WITH_SDDM=1 ;;
    *) echo "unknown option: $a"; exit 1 ;;
  esac
done

if [ "$WITH_DEPS" = 1 ]; then
  sudo pacman -S --needed ghostty starship fastfetch btop cava eza bat grc \
    papirus-icon-theme inter-font ttf-jetbrains-mono ttf-jetbrains-mono-nerd kvantum
  if command -v yay >/dev/null; then
    yay -S --needed kwin-effect-rounded-corners sddm-silent-theme
  else
    echo "!! yay not found: install kwin-effect-rounded-corners and sddm-silent-theme from the AUR yourself"
  fi
fi

# copy SRC (file or dir) to DEST, backing up whatever is already there
put() {
  local src="$1" dest="$2"
  if [ -e "$dest" ]; then
    mkdir -p "$BACKUP/$(dirname "${dest#"$HOME"/}")"
    cp -a "$dest" "$BACKUP/${dest#"$HOME"/}"
  fi
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
}

echo ">> configs"
for item in ghostty fastfetch btop cava neofetch Kvantum gtk-3.0 gtk-4.0 starship.toml; do
  put "$REPO/config/$item" "$HOME/.config/$item"
done
for f in "$REPO"/config/kde/*; do
  put "$f" "$HOME/.config/$(basename "$f")"
done
put "$REPO/bash/rice.sh" "$HOME/.config/bash/rice.sh"

echo ">> themes, effects, scripts, icons"
for d in color-schemes aurorae; do
  mkdir -p "$HOME/.local/share/$d"; cp -a "$REPO/local/share/$d/." "$HOME/.local/share/$d/"
done
for d in plasma/desktoptheme plasma/look-and-feel kwin/effects kwin/scripts kwin/tabbox kwin-wayland/tabbox; do
  mkdir -p "$HOME/.local/share/$d"; cp -a "$REPO/local/share/$d/." "$HOME/.local/share/$d/"
done
mkdir -p "$HOME/.local/share/icons"; cp -a "$REPO"/local/share/icons/*.svg "$HOME/.local/share/icons/"

echo ">> wallpaper"
mkdir -p "$HOME/.local/share/wallpapers/arch-kde-rice"
cp -a "$REPO/wallpapers/wallpaper.jpg" "$HOME/.local/share/wallpapers/arch-kde-rice/"

# The configs were saved with my home path; point them at yours
for f in ghostty/config fastfetch/config.jsonc kscreenlockerrc plasma-org.kde.plasma.desktop-appletsrc; do
  sed -i "s|/home/harel|$HOME|g" "$HOME/.config/$f"
done

# Hook the bash prompt in once
if ! grep -q 'config/bash/rice.sh' "$HOME/.bashrc" 2>/dev/null; then
  printf '\n[ -f ~/.config/bash/rice.sh ] && . ~/.config/bash/rice.sh\n' >> "$HOME/.bashrc"
fi

if [ "$WITH_SDDM" = 1 ]; then
  echo ">> sddm"
  sudo install -Dm644 "$REPO/sddm/silent-theme.conf" /etc/sddm.conf.d/silent-theme.conf
fi

[ -d "$BACKUP" ] && echo ">> old files backed up to $BACKUP"
echo ">> done. Log out and back in (or reboot) to load the Plasma/KWin parts."
