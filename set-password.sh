#!/bin/bash
# Génère le hash SHA-512 du mot de passe kiosk et l'injecte dans user-data
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_DATA="$SCRIPT_DIR/user-data"

[ -f "$USER_DATA" ] || { echo "[X] user-data introuvable : $USER_DATA"; exit 1; }

# Installe mkpasswd si absent
if ! command -v mkpasswd &>/dev/null; then
    echo "[i] Installation de mkpasswd (paquet whois)..."
    sudo apt-get install -y whois
fi

# Saisie mot de passe (double vérification)
while true; do
    read -rsp "Mot de passe kiosk : " PASSWORD; echo
    read -rsp "Confirmer           : " PASSWORD2; echo
    [ "$PASSWORD" = "$PASSWORD2" ] && break
    echo "[!] Les mots de passe ne correspondent pas, recommence."
done

[ -z "$PASSWORD" ] && { echo "[X] Mot de passe vide interdit."; exit 1; }

# Génération hash SHA-512
HASH=$(mkpasswd -m sha-512 "$PASSWORD")

# Injection dans user-data (remplace la ligne password:)
sed -i "s|^    password: .*|    password: \"$HASH\"|" "$USER_DATA"

echo "[OK] Hash injecté dans user-data."
echo "[i]  Lance ./build-iso.sh pour rebuilder l'ISO."
