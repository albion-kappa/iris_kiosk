#!/bin/bash
# =============================================================================
# build-iso.sh
# Génère une ISO Ubuntu Server custom avec autoinstall pour terminal applicatif
# =============================================================================
set -euo pipefail

# ---------- Configuration ----------
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04.1}"
ISO_URL="https://releases.ubuntu.com/${UBUNTU_VERSION}/ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
ISO_ORIG="ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
ISO_OUTPUT="ubuntu-terminal-applicatif-${UBUNTU_VERSION}.iso"
WORK_DIR="iso-build"

# ---------- Couleurs ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ---------- Vérifications préalables ----------
log "Vérification des fichiers requis..."
[ -f "user-data" ] || err "Fichier user-data introuvable dans le répertoire courant"
[ -f "meta-data" ] || err "Fichier meta-data introuvable dans le répertoire courant"

# Vérifie que le hash de mot de passe a bien été remplacé
if grep -q "REMPLACE_MOI" user-data; then
    err "Tu n'as pas remplacé le hash de mot de passe dans user-data !
    
    Génère-le avec : mkpasswd -m sha-512
    (paquet : sudo apt install whois)
    
    Puis remplace la ligne 'password:' dans user-data."
fi

# ---------- Installation des dépendances ----------
log "Installation des dépendances..."
if ! command -v xorriso &> /dev/null || ! command -v 7z &> /dev/null; then
    sudo apt update
    sudo apt install -y xorriso p7zip-full wget whois isolinux
fi

# ---------- Téléchargement de l'ISO Ubuntu ----------
if [ ! -f "$ISO_ORIG" ]; then
    log "Téléchargement de l'ISO Ubuntu Server $UBUNTU_VERSION..."
    wget -c "$ISO_URL" -O "$ISO_ORIG" || err "Échec du téléchargement"
else
    log "ISO source déjà présente : $ISO_ORIG"
fi

# ---------- Extraction de l'ISO ----------
log "Extraction de l'ISO..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
7z -y x "$ISO_ORIG" -o"$WORK_DIR" > /dev/null
# Le dossier [BOOT] créé par 7z doit être déplacé hors de l'ISO
[ -d "$WORK_DIR/[BOOT]" ] && mv "$WORK_DIR/[BOOT]" "$WORK_DIR/../BOOT"

# ---------- Injection de l'autoinstall ----------
log "Injection de la configuration autoinstall..."
mkdir -p "$WORK_DIR/server"
cp user-data meta-data "$WORK_DIR/server/"

# ---------- Modification du GRUB pour booter en autoinstall ----------
log "Configuration du bootloader GRUB..."
cat > "$WORK_DIR/boot/grub/grub.cfg" <<'EOF'
set timeout=30
set timeout_style=menu
loadfont unicode

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "★ Install Ubuntu Terminal Applicatif (AUTOINSTALL)" {
    set gfxpayload=keep
    linux /casper/vmlinuz quiet autoinstall ds=nocloud\;s=/cdrom/server/ ---
    initrd /casper/initrd
}

menuentry "Install Ubuntu Server (manuel - secours)" {
    set gfxpayload=keep
    linux /casper/vmlinuz quiet ---
    initrd /casper/initrd
}

menuentry "Test ISO sans installer" {
    set gfxpayload=keep
    linux /casper/vmlinuz quiet ---
    initrd /casper/initrd
}
EOF

# ---------- Reconstruction de l'ISO ----------
log "Reconstruction de l'ISO (peut prendre quelques minutes)..."
cd "$WORK_DIR"

xorriso -as mkisofs -r \
    -V "Ubuntu-Terminal" \
    -J -joliet-long \
    -l \
    -iso-level 3 \
    -partition_offset 16 \
    --grub2-mbr ../BOOT/1-Boot-NoEmul.img \
    --mbr-force-bootable \
    -append_partition 2 0xEF ../BOOT/2-Boot-NoEmul.img \
    -appended_part_as_gpt \
    -c '/boot.catalog' \
    -b '/boot/grub/i386-pc/eltorito.img' \
    -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
    -eltorito-alt-boot \
    -e '--interval:appended_partition_2:::' \
    -no-emul-boot \
    -o "../$ISO_OUTPUT" \
    .

cd ..

# ---------- Nettoyage ----------
log "Nettoyage des fichiers temporaires..."
rm -rf "$WORK_DIR" BOOT

# ---------- Résumé ----------
ISO_SIZE=$(du -h "$ISO_OUTPUT" | cut -f1)
log "ISO générée avec succès !"
echo ""
echo "  📀 Fichier  : $ISO_OUTPUT"
echo "  📏 Taille   : $ISO_SIZE"
echo ""
echo "  Pour flasher sur clé USB (remplace /dev/sdX par ton périphérique) :"
echo "    sudo dd if=$ISO_OUTPUT of=/dev/sdX bs=4M status=progress oflag=sync"
echo ""
echo "  Ou utilise Ventoy / Rufus / balenaEtcher."
echo ""
warn "L'installation EFFACE TOUT le disque cible automatiquement !"
