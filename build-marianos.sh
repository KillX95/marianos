#!/usr/bin/env bash
# MarianOS : Linux 7.2.12 + COSMIC (Terminal, Files, Settings) + Firefox
# À lancer sur une machine Arch Linux, en utilisateur NORMAL (pas root) avec sudo.
# NON TESTÉ : lis chaque étape, et adapte si une erreur apparaît.
set -euo pipefail

KVER="7.2.12"
USER_NAME="marian"
USER_PASS="marian"          # mot de passe de la session live : à changer
BASE="$HOME/marianos"

echo "==> 1/6 Dépendances"
sudo pacman -Syu --needed --noconfirm archiso base-devel bc cpio pahole libelf \
  perl python tar xz git openssl

mkdir -p "$BASE/kernel" "$BASE/repo"

echo "==> 2/6 PKGBUILD du noyau $KVER"
cat > "$BASE/kernel/PKGBUILD" <<EOF
pkgname=linux-marian
pkgver=$KVER
pkgrel=1
pkgdesc='Linux $KVER pour MarianOS'
url='https://www.kernel.org'
arch=(x86_64)
license=(GPL-2.0-only)
depends=(coreutils kmod initramfs)
makedepends=(bc cpio gettext libelf pahole perl python tar xz)
options=(!strip !debug)
source=("https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-\$pkgver.tar.xz"
        linux-marian.preset)
sha256sums=('SKIP' 'SKIP')   # TODO : remplace SKIP par le vrai sha256 (sha256sums.asc sur kernel.org)

prepare() {
  cd linux-\$pkgver
  # Config de départ : celle du noyau Arch de la machine de build
  zcat /proc/config.gz > .config
  echo "-marian" > localversion.20-pkgname
  make olddefconfig
  make -s kernelrelease > version
}

build() {
  cd linux-\$pkgver
  make -j"\$(nproc)" all
}

package() {
  cd linux-\$pkgver
  local kver; kver="\$(<version)"
  local moddir="\$pkgdir/usr/lib/modules/\$kver"
  install -Dm644 "\$(make -s image_name)" "\$moddir/vmlinuz"
  echo "linux-marian" | install -Dm644 /dev/stdin "\$moddir/pkgbase"
  echo "\$kver" | install -Dm644 /dev/stdin "\$moddir/kernelbase"
  make INSTALL_MOD_PATH="\$pkgdir/usr" INSTALL_MOD_STRIP=1 DEPMOD=/doesnt/exist modules_install
  rm -f "\$moddir"/{source,build}
  depmod -b "\$pkgdir/usr" -F System.map "\$kver"
  install -Dm644 "\$srcdir/linux-marian.preset" "\$pkgdir/etc/mkinitcpio.d/linux-marian.preset"
}
EOF

cat > "$BASE/kernel/linux-marian.preset" <<'EOF'
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux-marian"
PRESETS=('default')
default_image="/boot/initramfs-linux-marian.img"
EOF

echo "==> 3/6 Compilation du noyau (long : 20 min à plusieurs heures)"
( cd "$BASE/kernel" && makepkg -sf --noconfirm --skippgpcheck )
cp "$BASE"/kernel/linux-marian-*.pkg.tar.zst "$BASE/repo/"
( cd "$BASE/repo" && repo-add marianos.db.tar.gz ./*.pkg.tar.zst )

echo "==> 4/6 Profil archiso"
rm -rf "$BASE/profile"
cp -r /usr/share/archiso/configs/releng "$BASE/profile"
P="$BASE/profile"

# Dépôt local avec notre noyau
cat >> "$P/pacman.conf" <<EOF

[marianos]
SigLevel = Optional TrustAll
Server = file://$BASE/repo
EOF

# Paquets : on retire le noyau Arch standard, on ajoute le nôtre + COSMIC + Firefox
sed -i '/^linux$/d; /^broadcom-wl$/d' "$P/packages.x86_64"
cat >> "$P/packages.x86_64" <<'EOF'
linux-marian
networkmanager
sudo
# --- COSMIC (minimal : pas de Store, Edit, Player, etc.) ---
cosmic-session
cosmic-greeter
cosmic-comp
cosmic-panel
cosmic-applets
cosmic-launcher
cosmic-app-library
cosmic-bg
cosmic-osd
cosmic-notifications
cosmic-workspaces
cosmic-idle
cosmic-settings
cosmic-settings-daemon
xdg-desktop-portal-cosmic
# --- Les 4 applications ---
cosmic-terminal
cosmic-files
firefox
# --- Base graphique / son / polices ---
xorg-xwayland
mesa
pipewire
pipewire-pulse
wireplumber
noto-fonts
xdg-user-dirs
EOF

echo "==> 5/6 Branding, utilisateur, services"
sed -i 's/^iso_name=.*/iso_name="marianos"/;
        s/^iso_label=.*/iso_label="MARIANOS_$(date +%Y%m)"/;
        s/^iso_publisher=.*/iso_publisher="MarianOS"/;
        s/^iso_application=.*/iso_application="MarianOS Live\/Rescue"/' "$P/profiledef.sh"

# Entrées de boot : noyau renommé + nom du système
grep -rl 'vmlinuz-linux\|Arch Linux' "$P/grub" "$P/syslinux" "$P/efiboot" 2>/dev/null | while read -r f; do
  sed -i 's/vmlinuz-linux/vmlinuz-linux-marian/g;
          s/initramfs-linux\.img/initramfs-linux-marian.img/g;
          s/Arch Linux/MarianOS/g' "$f"
done

# Preset mkinitcpio archiso pour notre noyau
rm -f "$P/airootfs/etc/mkinitcpio.d/linux.preset"
mkdir -p "$P/airootfs/etc/mkinitcpio.d"
cat > "$P/airootfs/etc/mkinitcpio.d/linux-marian.preset" <<'EOF'
ALL_kver='/boot/vmlinuz-linux-marian'
PRESETS=('archiso')
archiso_config='/etc/mkinitcpio.conf.d/archiso.conf'
archiso_image="/boot/initramfs-linux-marian.img"
EOF

# Identité du système
cat > "$P/airootfs/etc/os-release" <<'EOF'
NAME="MarianOS"
PRETTY_NAME="MarianOS"
ID=marianos
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;23;147;209"
EOF
echo "marianos" > "$P/airootfs/etc/hostname"

# Utilisateur live
HASH="$(openssl passwd -6 "$USER_PASS")"
echo "$USER_NAME:x:1000:1000::/home/$USER_NAME:/bin/bash" >> "$P/airootfs/etc/passwd"
echo "$USER_NAME:x:1000:" >> "$P/airootfs/etc/group"
echo "$USER_NAME:$HASH:19000::::::" >> "$P/airootfs/etc/shadow"
echo "$USER_NAME:!::" >> "$P/airootfs/etc/gshadow"
sed -i "s/^wheel:x:998:.*/&/" "$P/airootfs/etc/group" || true
echo "%wheel ALL=(ALL:ALL) ALL" > "$P/airootfs/etc/sudoers.d/wheel" 2>/dev/null || {
  mkdir -p "$P/airootfs/etc/sudoers.d"
  echo "%wheel ALL=(ALL:ALL) ALL" > "$P/airootfs/etc/sudoers.d/wheel"
}
echo "wheel:x:998:$USER_NAME" >> "$P/airootfs/etc/group"
cat >> "$P/profiledef.sh" <<EOF
file_permissions+=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d/wheel"]="0:0:440"
)
EOF

# Services : COSMIC Greeter + réseau + démarrage graphique
mkdir -p "$P/airootfs/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/cosmic-greeter.service "$P/airootfs/etc/systemd/system/display-manager.service"
ln -sf /usr/lib/systemd/system/NetworkManager.service "$P/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
ln -sf /usr/lib/systemd/system/graphical.target "$P/airootfs/etc/systemd/system/default.target"

echo "==> 6/6 Génération de l'ISO"
sudo mkarchiso -v -w "$BASE/work" -o "$BASE/out" "$P"
echo "Terminé : $BASE/out/"
ls -lh "$BASE/out/"
