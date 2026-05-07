# Ubuntu Terminal Applicatif

ISO Ubuntu Server 24.04 personnalisée pour transformer une machine en terminal applicatif (kiosque) avec XFCE minimal et Chromium en plein écran.

## Architecture

- **Base** : Ubuntu Server 24.04 (minimal)
- **Bureau** : XFCE via `xubuntu-core` (~400 Mo, sans LibreOffice/Thunderbird/etc.)
- **Display Manager** : LightDM avec auto-login
- **Application** : Chromium en mode `--kiosk` sur l'URL de ton choix
- **Admin** : SSH activé, mises à jour sécurité automatiques

## Prérequis (sur ta machine de build)

### Sur Linux (Ubuntu/Debian)

- ~5 Go d'espace libre
- Connexion internet (pour télécharger l'ISO Ubuntu de base, ~3 Go)
- Droits sudo

→ Utilise `build-iso.sh`

### Sur Windows 10/11

- ~5 Go d'espace libre
- Connexion internet
- **WSL avec Ubuntu installé** (pour `xorriso`)
  - Installation : ouvre PowerShell en admin et lance `wsl --install -d Ubuntu`
  - Redémarre, configure ton utilisateur Ubuntu WSL
- Le script installe automatiquement 7-Zip si absent (via Chocolatey)

→ Double-clique sur `build-iso.bat` (ou exécute `build-iso.ps1` en PowerShell)

**Pourquoi WSL ?** `xorriso` (l'outil qui reconstruit l'ISO bootable BIOS+UEFI) n'a pas de port Windows natif maintenu. WSL fournit le binaire Linux nativement et c'est largement la solution la plus stable. Le script PowerShell délègue uniquement la phase xorriso à WSL — tout le reste (téléchargement, extraction, injection des configs) tourne en PowerShell pur.

## Workflow en 4 étapes

### 1. Génère le hash de ton mot de passe

**Sur Linux :**
```bash
sudo apt install whois
mkpasswd -m sha-512
```

**Sur Windows** (au choix) :
```powershell
# Option A : via WSL (recommandé)
wsl mkpasswd -m sha-512

# Option B : via Git Bash (déjà inclus avec Git for Windows)
openssl passwd -6

# Option C : via Docker Desktop
docker run --rm -it alpine sh -c "apk add --no-cache whois && mkpasswd -m sha-512"
```

Saisis le mot de passe que tu veux pour l'utilisateur `kiosk`. Tu obtiens un hash du genre :
```
$6$rounds=656000$xxxxxxxx$yyyyyyyy...
```

### 2. Personnalise `user-data`

Édite le fichier `user-data` :

```bash
nano user-data
```

À adapter :
- **Ligne `password:`** → colle ton hash (entre guillemets)
- **`hostname:`** → nom de la machine (ex: `terminal-magasin-01`)
- **`username:`** → nom de l'utilisateur (par défaut `kiosk`)
- **Variable `KIOSK_URL`** dans le script `start-kiosk.sh` → URL de ton appli

### 3. Lance la génération de l'ISO

**Sur Linux :**
```bash
chmod +x build-iso.sh
./build-iso.sh
```

**Sur Windows :**
- Double-clique sur `build-iso.bat`
- Ou en PowerShell : `powershell -ExecutionPolicy Bypass -File .\build-iso.ps1`

Le script :
1. Installe les dépendances nécessaires (`xorriso`, `7z`, etc.)
2. Télécharge l'ISO Ubuntu Server officielle (mise en cache, le téléchargement n'est fait qu'une fois)
3. Extrait le contenu, injecte ta config autoinstall
4. Reconstruit une ISO bootable BIOS + UEFI

Résultat : `ubuntu-terminal-applicatif-24.04.1.iso`

### 4. Flashe et installe

**Sur clé USB :**
```bash
sudo dd if=ubuntu-terminal-applicatif-24.04.1.iso of=/dev/sdX bs=4M status=progress oflag=sync
```
(remplace `/dev/sdX` — `lsblk` pour identifier ta clé)

Ou utilise [Ventoy](https://www.ventoy.net/) (recommandé, multi-ISO), Rufus (Windows), balenaEtcher.

**Sur la machine cible :**
1. Boot sur la clé USB
2. Sélectionne le 1er menu GRUB (autoinstall)
3. ⚠️ **L'install efface tout le disque automatiquement** sans confirmation
4. ~10-15 minutes plus tard, reboot
5. La machine boote, fait son auto-login, et lance Chromium en plein écran

## Configuration avancée

### Changer l'URL kiosque après installation

```bash
ssh kiosk@terminal-01
sudo vim /usr/local/bin/start-kiosk.sh
# Modifier la variable KIOSK_URL
sudo reboot
```

### Sortir du mode kiosque (pour debug)

⚠️ Le verrouillage est strict : `Ctrl+Alt+Fx`, `Ctrl+Alt+Backspace` sont **désactivés**.
Le seul moyen d'admin est le **SSH depuis une autre machine**.

```bash
ssh kiosk@terminal-01
pkill chromium-browser    # tue Chromium (il redémarre seul)
sudo systemctl stop lightdm   # quitte complètement la session graphique
sudo systemctl start lightdm  # la relance
```

Si tu veux temporairement réactiver l'accès tty pour debug en local :
```bash
sudo rm /etc/X11/xorg.conf.d/99-kiosk-lockdown.conf
sudo systemctl restart lightdm
# Ctrl+Alt+F2 fonctionne à nouveau
```

## Ce qui est verrouillé (récap exhaustif)

**Au niveau Chromium (via policies entreprise) :**
- ✅ Pas de barre d'URL, pas de menu, pas d'onglets (mode `--kiosk`)
- ✅ DevTools (`F12`, `Ctrl+Shift+I`) : **désactivés**
- ✅ Mode incognito : **désactivé**
- ✅ Téléchargements : **bloqués**
- ✅ Impression (`Ctrl+P`) : **désactivée**
- ✅ Navigation hors `iris.albk.fr` : **bloquée** (URL allowlist)
- ✅ `chrome://`, `file://`, `about:` : **bloqués**
- ✅ Extensions : installation **bloquée**
- ✅ Gestionnaire de mots de passe : **désactivé**
- ✅ Notifications, géoloc, popups : **bloqués**
- ✅ Auto-complétion, historique, sync : **désactivés**

**Au niveau système :**
- ✅ `Ctrl+Alt+Fx` (switch tty) : **désactivé**
- ✅ `Ctrl+Alt+Backspace` (kill X) : **désactivé**
- ✅ Raccourcis XFCE (Alt+F2 lanceur, Ctrl+Alt+T terminal…) : **vidés**
- ✅ Curseur masqué après 1s d'inactivité

**Ce qui reste accessible (et qu'on peut couper si besoin) :**
- `Ctrl+W`, `Ctrl+Q`, `Alt+F4` → ferme Chromium, mais la boucle `while` le relance immédiatement (3s)
- Clic droit → ouvre le menu contextuel Chromium (réduit en mode kiosque mais présent). Pour le supprimer totalement, ajoute dans `start-kiosk.sh` :
  ```bash
  --disable-features=ContextMenu
  ```

## Personnaliser les policies Chromium

Le fichier de policies est en `/etc/chromium-browser/policies/managed/kiosk-policy.json` après installation. Tu peux le modifier en SSH puis redémarrer Chromium.

Liste complète des policies disponibles : https://chromeenterprise.google/policies/

Exemples utiles :
- `"URLAllowlist": ["https://iris.albk.fr/*", "https://*.albk.fr/*"]` → autorise plusieurs sous-domaines
- `"DownloadDirectory": "/home/kiosk/Downloads"` + `"DownloadRestrictions": 0` → si tu veux autoriser les téléchargements
- `"PrintingEnabled": true` → si impression nécessaire

### Ajouter des paquets

Dans `user-data`, section `packages:`, ajoute ce qu'il te faut. Exemples utiles :
- `network-manager` + `network-manager-gnome` → si Wi-Fi nécessaire
- `cups` → si impression
- `tigervnc-scraping-server` → pour assistance à distance graphique

### Plusieurs machines avec configs différentes

Duplique le projet et change juste `hostname` + `KIOSK_URL` :
```
terminaux/
├── magasin-01/user-data
├── magasin-02/user-data
└── salle-attente/user-data
```

### Mode kiosque "vraiment" verrouillé

Pour empêcher complètement l'utilisateur de sortir de Chromium, ajoute en `late-commands` :
```yaml
- |
  curtin in-target -- bash -c 'cat > /etc/X11/xorg.conf.d/99-no-tty-switch.conf <<EOF
  Section "ServerFlags"
      Option "DontVTSwitch" "true"
      Option "DontZap" "true"
  EndSection
  EOF'
```

⚠️ Garde toujours un accès SSH sinon tu te bloques toi-même.

### Filesystem en lecture seule (overlay)

Pour qu'un reboot remette tout à zéro (utile en environnement public) :
```bash
sudo apt install overlayroot
sudo vim /etc/overlayroot.conf
# Mettre : overlayroot="tmpfs"
```

## Dépannage

**L'install ne démarre pas en autoinstall** : vérifie que dans le menu GRUB tu choisis bien la 1ère entrée. Si tu boot en mode UEFI, le menu peut être différent — l'autoinstall est quand même chargé via `ds=nocloud`.

**Écran noir après install** : connecte-toi en SSH (`ssh kiosk@<ip>`), vérifie `systemctl status lightdm` et les logs `/var/log/lightdm/`.

**Chromium ne se lance pas** : `journalctl --user -u xfce4-session` côté kiosk, ou regarde `~/.xsession-errors`.

**Modifier la config sans tout réinstaller** : Ansible est ton ami. Tu peux te connecter en SSH et automatiser les changements sur N machines.

## Versionning

Tout ce projet est versionnable dans Git. Les fichiers à commiter :
- `user-data` (sans le vrai hash de prod — utilise un placeholder)
- `meta-data`
- `build-iso.sh`
- `README.md`

À ne PAS commiter :
- L'ISO source Ubuntu (~3 Go)
- L'ISO générée
- `iso-build/` (généré par le script)

`.gitignore` recommandé :
```
*.iso
iso-build/
BOOT/
```
