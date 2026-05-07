#!/bin/bash
# Injecte une clé SSH publique dans user-data (section ssh.authorized-keys)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_DATA="$SCRIPT_DIR/user-data"

[ -f "$USER_DATA" ] || { echo "[X] user-data introuvable : $USER_DATA"; exit 1; }

# --- Lecture de la clé ---
if [ $# -ge 1 ]; then
    # Argument = chemin vers un fichier .pub
    KEY_FILE="$1"
    [ -f "$KEY_FILE" ] || { echo "[X] Fichier introuvable : $KEY_FILE"; exit 1; }
    PUBKEY=$(cat "$KEY_FILE" | tr -d '\n\r')
else
    echo "Colle ta clé publique SSH (ssh-rsa / ssh-ed25519 / ecdsa...) puis Entrée :"
    read -r PUBKEY
fi

# Validation basique
if ! echo "$PUBKEY" | grep -qE '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp|sk-ssh-ed25519) [A-Za-z0-9+/=]+'; then
    echo "[X] Format de clé invalide. Attendu : ssh-rsa AAAA... ou ssh-ed25519 AAAA..."
    exit 1
fi

# Vérifie doublon
if grep -qF "$PUBKEY" "$USER_DATA"; then
    echo "[!] Clé déjà présente dans user-data, rien à faire."
    exit 0
fi

# Injecte la clé dans la section ssh
if grep -q "authorized-keys:" "$USER_DATA"; then
    # Section existe : ajoute une entrée à la liste
    sed -i "/authorized-keys:/a\\      - \"$PUBKEY\"" "$USER_DATA"
else
    # Section absente : crée-la après "allow-pw: true"
    sed -i "/allow-pw: true/a\\    authorized-keys:\n      - \"$PUBKEY\"" "$USER_DATA"
fi

echo "[OK] Clé SSH injectée dans user-data."
echo "[i]  Lance ./build-iso.sh pour rebuilder l'ISO."
