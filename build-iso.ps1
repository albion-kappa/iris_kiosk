<#
.SYNOPSIS
    Génère une ISO Ubuntu Server custom avec autoinstall pour terminal applicatif.
    Version Windows PowerShell du script build-iso.sh.

.USAGE
    Clic droit sur le fichier > "Exécuter avec PowerShell"
    Ou : powershell -ExecutionPolicy Bypass -File .\build-iso.ps1
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$UbuntuVersion = "24.04.1",
    [switch]$SkipDependencyCheck
)

$ErrorActionPreference = "Stop"

# =============================================================================
# DÉTERMINATION DU RÉPERTOIRE DE TRAVAIL (robuste)
# =============================================================================
# Plusieurs fallbacks pour gérer tous les cas d'invocation
if ($PSScriptRoot -and (Test-Path $PSScriptRoot)) {
    $SCRIPT_DIR = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $SCRIPT_DIR = (Get-Location).Path
}

# On se positionne IMMÉDIATEMENT dans le bon dossier
Set-Location -LiteralPath $SCRIPT_DIR
[System.IO.Directory]::SetCurrentDirectory($SCRIPT_DIR)

# =============================================================================
# Configuration (TOUS les chemins sont absolus)
# =============================================================================
$ISO_URL     = "https://releases.ubuntu.com/$UbuntuVersion/ubuntu-$UbuntuVersion-live-server-amd64.iso"
$ISO_ORIG    = Join-Path $SCRIPT_DIR "ubuntu-$UbuntuVersion-live-server-amd64.iso"
$ISO_OUTPUT  = Join-Path $SCRIPT_DIR "ubuntu-terminal-applicatif-$UbuntuVersion.iso"
$WORK_DIR    = Join-Path $SCRIPT_DIR "iso-build"
$BOOT_DIR    = Join-Path $SCRIPT_DIR "BOOT"
$USER_DATA   = Join-Path $SCRIPT_DIR "user-data"
$META_DATA   = Join-Path $SCRIPT_DIR "meta-data"

# =============================================================================
# Helpers d'affichage
# =============================================================================
function Write-Log  { Write-Host "[OK] $args" -ForegroundColor Green }
function Write-Warn { Write-Host "[!]  $args" -ForegroundColor Yellow }
function Write-Err  { Write-Host "[X]  $args" -ForegroundColor Red; exit 1 }
function Write-Info { Write-Host "[i]  $args" -ForegroundColor Cyan }

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Ubuntu Terminal Applicatif - Build ISO (Windows)" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Info "Repertoire de travail : $SCRIPT_DIR"
Write-Info "Repertoire courant    : $((Get-Location).Path)"

# =============================================================================
# Vérification des fichiers requis
# =============================================================================
Write-Log "Verification des fichiers requis..."

if (-not (Test-Path -LiteralPath $USER_DATA)) {
    Write-Err "Fichier 'user-data' introuvable.`n  Attendu a : $USER_DATA"
}
if (-not (Test-Path -LiteralPath $META_DATA)) {
    Write-Err "Fichier 'meta-data' introuvable.`n  Attendu a : $META_DATA"
}

# Vérifie que le hash de mot de passe a été remplacé
$userDataContent = Get-Content -LiteralPath $USER_DATA -Raw
if ($userDataContent -match "REMPLACE_MOI") {
    Write-Err @"
Tu n'as pas remplace le hash de mot de passe dans user-data !

Genere-le sous Windows avec une de ces methodes :

  1) Avec WSL (recommande) :
     wsl mkpasswd -m sha-512

  2) Avec Git Bash (deja inclus avec Git for Windows) :
     openssl passwd -6

  3) Avec Docker Desktop :
     docker run --rm -it alpine sh -c "apk add --no-cache whois && mkpasswd -m sha-512"

Puis remplace la ligne 'password:' dans user-data.
"@
}

# =============================================================================
# Installation des dépendances
# =============================================================================
function Test-Command($cmd) {
    return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

function Install-Chocolatey {
    if (Test-Command "choco") { return }
    Write-Info "Installation de Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
        'https://community.chocolatey.org/install.ps1'))
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + `
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

if (-not $SkipDependencyCheck) {
    Write-Log "Verification des dependances..."

    # 7-Zip
    $7zPath = $null
    foreach ($p in @(
        "${env:ProgramFiles}\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    )) {
        if (Test-Path -LiteralPath $p) { $7zPath = $p; break }
    }

    if (-not $7zPath) {
        Write-Warn "7-Zip non trouve. Installation via Chocolatey..."
        Install-Chocolatey
        choco install -y 7zip
        $7zPath = "${env:ProgramFiles}\7-Zip\7z.exe"
    }
    Write-Log "7-Zip : $7zPath"

    # WSL + xorriso
    $useWSL = $false
    if (Test-Command "wsl") {
        try {
            $null = wsl --status 2>&1
            $wslHasXorriso = wsl -- bash -c "command -v xorriso" 2>$null
            if ($LASTEXITCODE -eq 0 -and $wslHasXorriso) {
                Write-Log "WSL + xorriso OK : $wslHasXorriso"
                $useWSL = $true
            } else {
                Write-Warn "WSL present mais xorriso manquant. Installation..."
                wsl -- sudo apt-get update
                wsl -- sudo apt-get install -y xorriso
                $useWSL = $true
                Write-Log "xorriso installe dans WSL"
            }
        } catch {
            Write-Warn "WSL non fonctionnel : $_"
        }
    }

    if (-not $useWSL) {
        Write-Err @"
WSL avec xorriso est requis pour reconstruire l'ISO.

Installation rapide :
  1) Ouvre PowerShell en administrateur
  2) Execute : wsl --install -d Ubuntu
  3) Redemarre, configure ton utilisateur Ubuntu
  4) Relance ce script
"@
    }
} else {
    Write-Warn "Verification des dependances ignoree"
    $7zPath = "${env:ProgramFiles}\7-Zip\7z.exe"
}

# =============================================================================
# Téléchargement de l'ISO Ubuntu
# =============================================================================
if (-not (Test-Path -LiteralPath $ISO_ORIG)) {
    Write-Log "Telechargement de l'ISO Ubuntu Server $UbuntuVersion (~3 Go)..."
    Write-Info "URL  : $ISO_URL"
    Write-Info "Dest : $ISO_ORIG"

    try {
        Start-BitsTransfer -Source $ISO_URL -Destination $ISO_ORIG -DisplayName "Ubuntu ISO"
    } catch {
        Write-Warn "BITS echoue, fallback sur Invoke-WebRequest..."
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $ISO_URL -OutFile $ISO_ORIG -UseBasicParsing
        $ProgressPreference = 'Continue'
    }
    Write-Log "Telechargement termine"
} else {
    $isoSize = [math]::Round((Get-Item -LiteralPath $ISO_ORIG).Length / 1GB, 2)
    Write-Log "ISO source deja presente ($isoSize Go)"
}

# =============================================================================
# Extraction de l'ISO
# =============================================================================
Write-Log "Extraction de l'ISO..."
if (Test-Path -LiteralPath $WORK_DIR) {
    Remove-Item -LiteralPath $WORK_DIR -Recurse -Force
}
New-Item -ItemType Directory -Path $WORK_DIR -Force | Out-Null

& $7zPath x -y $ISO_ORIG "-o$WORK_DIR" | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Err "Echec de l'extraction" }

# Le dossier [BOOT] créé par 7z contient les images de boot
$bootInWork = Join-Path $WORK_DIR "[BOOT]"
if (Test-Path -LiteralPath $bootInWork) {
    if (Test-Path -LiteralPath $BOOT_DIR) {
        Remove-Item -LiteralPath $BOOT_DIR -Recurse -Force
    }
    Move-Item -LiteralPath $bootInWork -Destination $BOOT_DIR
}

# =============================================================================
# Injection de l'autoinstall
# =============================================================================
Write-Log "Injection de la configuration autoinstall..."
$serverDir = Join-Path $WORK_DIR "server"
New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
Copy-Item -LiteralPath $USER_DATA -Destination $serverDir
Copy-Item -LiteralPath $META_DATA -Destination $serverDir

# =============================================================================
# Modification du GRUB (chemin absolu, dossier créé si manquant)
# =============================================================================
Write-Log "Configuration du bootloader GRUB..."

$grubConfig = @'
set timeout=10
loadfont unicode

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "* Install Ubuntu Terminal Applicatif (AUTOINSTALL)" {
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
'@

$grubDir  = Join-Path $WORK_DIR "boot\grub"
$grubPath = Join-Path $grubDir "grub.cfg"

# Sécurité : crée le dossier s'il n'existe pas (peut arriver si l'extraction
# a partiellement échoué ou si l'ISO est non standard)
if (-not (Test-Path -LiteralPath $grubDir)) {
    Write-Warn "Dossier boot/grub absent, creation..."
    New-Item -ItemType Directory -Path $grubDir -Force | Out-Null
}

# Écriture en UTF-8 SANS BOM (sinon GRUB ne lit pas le fichier)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($grubPath, $grubConfig, $utf8NoBom)

Write-Log "grub.cfg ecrit : $grubPath"

# =============================================================================
# Reconstruction de l'ISO via WSL
# =============================================================================
Write-Log "Reconstruction de l'ISO via WSL (peut prendre 2-5 minutes)..."

function ConvertTo-WslPath($winPath) {
    $abs = (Resolve-Path -LiteralPath $winPath -ErrorAction SilentlyContinue).Path
    if (-not $abs) { $abs = [System.IO.Path]::GetFullPath($winPath) }
    $drive = $abs.Substring(0, 1).ToLower()
    $rest  = $abs.Substring(2).Replace('\', '/')
    return "/mnt/$drive$rest"
}

$wslWorkDir   = ConvertTo-WslPath $WORK_DIR
$wslBootDir   = ConvertTo-WslPath $BOOT_DIR
$wslIsoOutput = ConvertTo-WslPath $ISO_OUTPUT

Write-Info "WSL work dir : $wslWorkDir"
Write-Info "WSL boot dir : $wslBootDir"
Write-Info "WSL output   : $wslIsoOutput"

$xorrisoCmd = @"
cd '$wslWorkDir' && xorriso -as mkisofs -r \
    -V 'Ubuntu-Terminal' \
    -J -joliet-long \
    -l \
    -iso-level 3 \
    -partition_offset 16 \
    --grub2-mbr '$wslBootDir/1-Boot-NoEmul.img' \
    --mbr-force-bootable \
    -append_partition 2 0xEF '$wslBootDir/2-Boot-NoEmul.img' \
    -appended_part_as_gpt \
    -c '/boot.catalog' \
    -b '/boot/grub/i386-pc/eltorito.img' \
    -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
    -eltorito-alt-boot \
    -e '--interval:appended_partition_2:::' \
    -no-emul-boot \
    -o '$wslIsoOutput' \
    .
"@

wsl -- bash -c $xorrisoCmd
if ($LASTEXITCODE -ne 0) { Write-Err "xorriso a echoue" }

# =============================================================================
# Nettoyage
# =============================================================================
Write-Log "Nettoyage des fichiers temporaires..."
Remove-Item -LiteralPath $WORK_DIR -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $BOOT_DIR -Recurse -Force -ErrorAction SilentlyContinue

# =============================================================================
# Résumé
# =============================================================================
$isoSize = [math]::Round((Get-Item -LiteralPath $ISO_OUTPUT).Length / 1MB, 0)
Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Log "ISO generee avec succes !"
Write-Host "=================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Fichier  : $(Split-Path -Leaf $ISO_OUTPUT)" -ForegroundColor White
Write-Host "  Taille   : $isoSize Mo" -ForegroundColor White
Write-Host "  Chemin   : $ISO_OUTPUT" -ForegroundColor White
Write-Host ""
Write-Host "  Pour flasher sur cle USB :" -ForegroundColor Cyan
Write-Host "    - Rufus        : https://rufus.ie/  (mode DD)" -ForegroundColor Gray
Write-Host "    - Ventoy       : https://www.ventoy.net/  (multi-ISO)" -ForegroundColor Gray
Write-Host "    - balenaEtcher : https://www.balena.io/etcher/" -ForegroundColor Gray
Write-Host ""
Write-Warn "L'installation EFFACE TOUT le disque cible automatiquement !"
Write-Host ""