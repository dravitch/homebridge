# ====================================================================
# SETUP WINDOWS VNC - HomeBridge v1.1
# Installation complète : TigerVNC + Tunnel + Tâches + Raccourcis
# Usage: .\setup-windows-vnc.ps1 -RelayServer "172.234.175.48"
# ====================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$RelayServer = "172.234.175.48",
    
    [Parameter(Mandatory=$false)]
    [string]$RelayUser = "tunnel",
    
    [Parameter(Mandatory=$false)]
    [int]$ReversePort = 15900
)

$ErrorActionPreference = "Stop"

Write-Host @"
========================================
SETUP WINDOWS VNC - HomeBridge v1.1
Configuration: TigerVNC + Tunnel SSH
========================================
"@ -ForegroundColor Cyan

# ====================================================================
# ÉTAPE 1/8: VÉRIFICATION PRÉREQUIS
# ====================================================================
Write-Host "`n[1/8] Vérification des prérequis..." -ForegroundColor Yellow

# Check admin privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  [ERREUR] Privilèges administrateur requis!" -ForegroundColor Red
    Write-Host "  Exécutez ce script avec 'Exécuter en tant qu'administrateur'" -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] Privilèges administrateur" -ForegroundColor Green

# Directories
$homebridgeDir = "C:\HomeBridge"
$vncDir = "$homebridgeDir\vnc"
$logsDir = "$homebridgeDir\logs"
$scriptsDir = "$homebridgeDir\scripts"

# Create directories
@($homebridgeDir, $vncDir, $logsDir, $scriptsDir) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }
}
Write-Host "  [OK] Répertoires créés" -ForegroundColor Green

# Check OpenSSH
$sshInstalled = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'
if ($sshInstalled.State -ne "Installed") {
    Write-Host "  Installation OpenSSH Client..." -ForegroundColor Gray
    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 | Out-Null
}
Write-Host "  [OK] OpenSSH Client présent" -ForegroundColor Green

# SSH key paths
$systemProfileDir = "C:\Windows\System32\config\systemprofile"
$systemSshDir = "$systemProfileDir\.ssh"
$systemKeyPath = "$systemSshDir\id_rsa"

# Verify or reuse existing SSH key
if (-not (Test-Path $systemKeyPath)) {
    Write-Host "  [INFO] Clé SSH SYSTEM non trouvée, création..." -ForegroundColor Gray
    if (-not (Test-Path $systemSshDir)) {
        New-Item -Path $systemSshDir -ItemType Directory -Force | Out-Null
    }
    & ssh-keygen -t rsa -b 4096 -C "windows-homebridge-tunnel" -f "$systemKeyPath" -N '""' | Out-Null
    Write-Host "  [OK] Clé SSH SYSTEM créée" -ForegroundColor Green
} else {
    Write-Host "  [OK] Clé SSH SYSTEM existante réutilisée (partagée RDP/VNC)" -ForegroundColor Green
}

# ====================================================================
# ÉTAPE 2/8: INSTALLATION TIGERVNC SERVER
# ====================================================================
Write-Host "`n[2/8] Installation TigerVNC Server..." -ForegroundColor Yellow

# Check if already installed
$winvncPath = $null
$possiblePaths = @(
    "C:\Program Files\TigerVNC Server\winvnc4.exe",
    "C:\Program Files (x86)\TigerVNC Server\winvnc4.exe"
)

foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $winvncPath = $path
        break
    }
}

if ($winvncPath) {
    Write-Host "  [OK] TigerVNC déjà installé: $winvncPath" -ForegroundColor Green
} else {
    Write-Host "  Téléchargement TigerVNC WinVNC build..." -ForegroundColor Gray
    
    # Use nightly WinVNC build (includes server component)
    $vncUrl = "http://tigervnc.bphinz.com/nightly/windows/tigervnc64-winvnc-1.16.80.exe"
    $vncInstaller = "$env:TEMP\tigervnc-installer.exe"
    
    try {
        Invoke-WebRequest -Uri $vncUrl -OutFile $vncInstaller -UseBasicParsing -ErrorAction Stop
        Write-Host "  Téléchargement réussi" -ForegroundColor Gray
        
        # Silent install with WinVNC components
        Write-Host "  Installation en cours..." -ForegroundColor Gray
        Start-Process -FilePath $vncInstaller -ArgumentList "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /COMPONENTS=winvnc" -Wait -NoNewWindow
        Remove-Item $vncInstaller -Force -ErrorAction SilentlyContinue
        
        # Verify installation
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                $winvncPath = $path
                break
            }
        }
        
        if ($winvncPath) {
            Write-Host "  [OK] TigerVNC installé: $winvncPath" -ForegroundColor Green
        } else {
            throw "Installation failed - winvnc4.exe not found"
        }
        
    } catch {
        Write-Host "  [ERREUR] Échec téléchargement/installation automatique" -ForegroundColor Red
        Write-Host "" -ForegroundColor Red
        Write-Host "  INSTALLATION MANUELLE REQUISE:" -ForegroundColor Yellow
        Write-Host "  1. Téléchargez: http://tigervnc.bphinz.com/nightly/" -ForegroundColor White
        Write-Host "  2. Installez: tigervnc64-winvnc-<version>.exe" -ForegroundColor White
        Write-Host "  3. Sélectionnez les composants WinVNC" -ForegroundColor White
        Write-Host "  4. Relancez ce script" -ForegroundColor White
        Write-Host "" -ForegroundColor Red
        exit 1
    }
}

# ====================================================================
# ÉTAPE 3/8: CONFIGURATION VNC
# ====================================================================
Write-Host "`n[3/8] Configuration VNC..." -ForegroundColor Yellow

# Set directory permissions
icacls.exe "$vncDir" /inheritance:r 2>&1 | Out-Null
icacls.exe "$vncDir" /grant "SYSTEM:(OI)(CI)F" 2>&1 | Out-Null
icacls.exe "$vncDir" /grant "Administrators:(OI)(CI)F" 2>&1 | Out-Null
icacls.exe "$vncDir" /grant "Users:(OI)(CI)RX" 2>&1 | Out-Null

Write-Host "  [OK] Permissions répertoire configurées" -ForegroundColor Green
Write-Host "  [INFO] VNC utilisera SecurityTypes None (pas de mot de passe)" -ForegroundColor Gray
Write-Host "  [INFO] Sécurité assurée par tunnel SSH (localhost only)" -ForegroundColor Gray

# ====================================================================
# ÉTAPE 4/8: SCRIPTS OPÉRATIONNELS (Start/Stop)
# ====================================================================
Write-Host "`n[4/8] Création des scripts opérationnels..." -ForegroundColor Yellow

# Start-VNC.ps1
$startVncScript = @"
# ====================================================================
# START VNC SERVER - HomeBridge v1.1
# Lance WinVNC sous compte utilisateur avec SecurityTypes None
# ====================================================================

`$winvncExe = "$winvncPath"
`$logFile = "$logsDir\vnc-session.log"

function Write-Log {
    param(`$Message)
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "`$timestamp - `$Message" | Out-File -Append `$logFile
}

Write-Host "Démarrage VNC Server..." -ForegroundColor Cyan

# Vérification TigerVNC
if (-not (Test-Path `$winvncExe)) {
    Write-Host "ERREUR: WinVNC non trouvé: `$winvncExe" -ForegroundColor Red
    Write-Log "ERREUR: WinVNC non trouvé"
    pause
    exit 1
}

# Vérification tunnel SSH
`$tunnelTask = Get-ScheduledTask -TaskName "SSH-Reverse-Tunnel-VNC" -ErrorAction SilentlyContinue
if (`$tunnelTask) {
    if (`$tunnelTask.State -ne "Running") {
        Write-Host "Démarrage du tunnel SSH..." -ForegroundColor Yellow
        Start-ScheduledTask -TaskName "SSH-Reverse-Tunnel-VNC"
        Start-Sleep -Seconds 5
    }
} else {
    Write-Host "ATTENTION: Tunnel SSH non configuré" -ForegroundColor Yellow
    Write-Host "Le VNC sera accessible uniquement en local" -ForegroundColor Gray
}

# Arrêt des processus VNC existants
`$existing = Get-Process winvnc4 -ErrorAction SilentlyContinue
if (`$existing) {
    Write-Host "Arrêt des sessions VNC existantes..." -ForegroundColor Yellow
    `$existing | Stop-Process -Force
    Start-Sleep -Seconds 2
}

# Démarrage WinVNC
Write-Host "Démarrage WinVNC (SecurityTypes=None)..." -ForegroundColor Green
Write-Log "Démarrage WinVNC"

try {
    Start-Process -FilePath `$winvncExe -ArgumentList "-SecurityTypes None" -WindowStyle Hidden
    Start-Sleep -Seconds 3
    
    # Vérification démarrage
    `$process = Get-Process winvnc4 -ErrorAction SilentlyContinue
    if (`$process) {
        Write-Host "VNC Server démarré avec succès (PID: `$(`$process.Id))" -ForegroundColor Green
        Write-Host "Port 5900 disponible pour connexions" -ForegroundColor Green
        Write-Log "VNC démarré (PID: `$(`$process.Id))"
        
        # Vérification port
        Start-Sleep -Seconds 2
        `$port = Get-NetTCPConnection -LocalPort 5900 -State Listen -ErrorAction SilentlyContinue
        if (`$port) {
            Write-Host "Port 5900 en écoute - Prêt pour connexions" -ForegroundColor Green
        } else {
            Write-Host "ATTENTION: Port 5900 non détecté" -ForegroundColor Yellow
        }
    } else {
        Write-Host "ERREUR: Échec démarrage VNC" -ForegroundColor Red
        Write-Log "ERREUR: Échec démarrage VNC"
    }
} catch {
    Write-Host "ERREUR: `$(`$_.Exception.Message)" -ForegroundColor Red
    Write-Log "ERREUR: `$(`$_.Exception.Message)"
}

Write-Host "`nVNC Server actif en arrière-plan." -ForegroundColor Cyan
Write-Host "Pour arrêter: Exécutez Stop-VNC.ps1" -ForegroundColor Gray
Write-Host ""

pause
"@

Set-Content -Path "$scriptsDir\Start-VNC.ps1" -Value $startVncScript -Force
Write-Host "  [OK] Start-VNC.ps1 créé" -ForegroundColor Green

# Stop-VNC.ps1
$stopVncScript = @"
# ====================================================================
# STOP VNC SERVER - HomeBridge v1.1
# Arrête WinVNC proprement
# ====================================================================

Write-Host "Arrêt VNC Server..." -ForegroundColor Cyan

`$processes = Get-Process winvnc4 -ErrorAction SilentlyContinue

if (`$processes) {
    `$processes | Stop-Process -Force
    Start-Sleep -Seconds 1
    
    Write-Host "VNC Server arrêté" -ForegroundColor Green
} else {
    Write-Host "VNC Server n'est pas actif" -ForegroundColor Yellow
}

pause
"@

Set-Content -Path "$scriptsDir\Stop-VNC.ps1" -Value $stopVncScript -Force
Write-Host "  [OK] Stop-VNC.ps1 créé" -ForegroundColor Green

# ====================================================================
# ÉTAPE 5/8: TUNNEL SSH VNC
# ====================================================================
Write-Host "`n[5/8] Configuration du tunnel SSH VNC..." -ForegroundColor Yellow

# known_hosts
$knownHostsPath = "$systemSshDir\known_hosts"
if ($RelayServer -ne "RELAY_IP") {
    Write-Host "  Ajout du relay aux known_hosts..." -ForegroundColor Gray
    $serverKey = & ssh-keyscan -H $RelayServer 2>$null
    if ($serverKey) {
        $existingKeys = if (Test-Path $knownHostsPath) { Get-Content $knownHostsPath } else { @() }
        $serverKeyStr = [string]$serverKey
        if ($existingKeys -notcontains $serverKeyStr) {
            Add-Content -Path $knownHostsPath -Value $serverKey
        }
    }
}

# Tunnel script
$tunnelScriptPath = "$systemProfileDir\ssh-reverse-tunnel-vnc.ps1"
$tunnelScriptContent = @"
# ====================================================================
# SSH REVERSE TUNNEL FOR VNC - HomeBridge v1.1
# Tunnel SSH inverse pour VNC (Windows:5900 → Relay:15900)
# ====================================================================

`$RELAY_SERVER = "$RelayServer"
`$RELAY_USER   = "$RelayUser"
`$REVERSE_PORT = $ReversePort
`$LOCAL_VNC_PORT = 5900
`$SSH_KEY_PATH = "$systemKeyPath"
`$logFile = "$logsDir\vnc-tunnel.log"

function Write-Log {
    param(`$Message)
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    `$logMessage = "[`$timestamp] `$Message"
    Write-Output `$logMessage | Out-File -FilePath `$logFile -Append -Encoding UTF8
}

# Arrêt des processus SSH existants pour VNC
Get-Process ssh -ErrorAction SilentlyContinue | Where-Object {
    `$_.CommandLine -like "*`${REVERSE_PORT}:127.0.0.1:*"
} | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

while (`$true) {
    Write-Log "Établissement tunnel SSH reverse vers `$RELAY_SERVER..."
    Write-Log "  Port VNC local: `$LOCAL_VNC_PORT"
    Write-Log "  Port relay distant: `$REVERSE_PORT"
    
    `$sshArgs = @(
        "-i", `$SSH_KEY_PATH,
        "-N",
        "-T",
        "-R", "`${REVERSE_PORT}:127.0.0.1:`${LOCAL_VNC_PORT}",
        "-o", "ServerAliveInterval=60",
        "-o", "ServerAliveCountMax=3",
        "-o", "ExitOnForwardFailure=yes",
        "-o", "StrictHostKeyChecking=no",
        "`${RELAY_USER}@`${RELAY_SERVER}"
    )
    
    try {
        Write-Log "Démarrage processus tunnel SSH..."
        `$process = Start-Process -FilePath "ssh" -ArgumentList `$sshArgs -NoNewWindow -PassThru -Wait
        `$exitCode = `$process.ExitCode
        Write-Log "Tunnel SSH terminé (code: `$exitCode)"
    } catch {
        Write-Log "ERREUR: Tunnel SSH échoué - `$(`$_.Exception.Message)"
    }
    
    Write-Log "Reconnexion dans 10 secondes..."
    Start-Sleep -Seconds 10
}
"@

Set-Content -Path $tunnelScriptPath -Value $tunnelScriptContent -Force

# Permissions
icacls.exe "$systemKeyPath" /inheritance:r 2>&1 | Out-Null
icacls.exe "$systemKeyPath" /grant "SYSTEM:(F)" 2>&1 | Out-Null
icacls.exe "$tunnelScriptPath" /grant "SYSTEM:(R)" 2>&1 | Out-Null

# Create SSH tunnel scheduled task
$taskName = "SSH-Reverse-Tunnel-VNC"
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tunnelScriptPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 999

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

Write-Host "  [OK] Tâche tunnel SSH VNC créée" -ForegroundColor Green

# Start tunnel task
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 3
Write-Host "  [OK] Tunnel SSH VNC démarré" -ForegroundColor Green

# ====================================================================
# ÉTAPE 6/8: CONFIGURATION FIREWALL
# ====================================================================
Write-Host "`n[6/8] Configuration du firewall..." -ForegroundColor Yellow

# Remove old rules if exist
Remove-NetFirewallRule -Name "HomeBridge-VNC-In" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "*HomeBridge*VNC*" -ErrorAction SilentlyContinue

# Allow port 5900 on localhost only
New-NetFirewallRule -Name "HomeBridge-VNC-In" `
    -DisplayName "HomeBridge VNC (localhost only)" `
    -Enabled True `
    -Direction Inbound `
    -Protocol TCP `
    -Action Allow `
    -LocalPort 5900 `
    -LocalAddress 127.0.0.1 `
    -ErrorAction SilentlyContinue | Out-Null

Write-Host "  [OK] Règle firewall créée (localhost only)" -ForegroundColor Green

# ====================================================================
# ÉTAPE 7/8: CRÉATION RACCOURCIS BUREAU
# ====================================================================
Write-Host "`n[7/8] Création des raccourcis bureau..." -ForegroundColor Yellow

$publicDesktop = "C:\Users\Public\Desktop"

# Create WScript.Shell COM object
$WshShell = New-Object -ComObject WScript.Shell

# Start VNC shortcut
$startShortcut = $WshShell.CreateShortcut("$publicDesktop\Start VNC Server.lnk")
$startShortcut.TargetPath = "powershell.exe"
$startShortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptsDir\Start-VNC.ps1`""
$startShortcut.WorkingDirectory = $scriptsDir
$startShortcut.IconLocation = "powershell.exe,0"
$startShortcut.Description = "Démarre le serveur VNC"
$startShortcut.Save()

# Stop VNC shortcut
$stopShortcut = $WshShell.CreateShortcut("$publicDesktop\Stop VNC Server.lnk")
$stopShortcut.TargetPath = "powershell.exe"
$stopShortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptsDir\Stop-VNC.ps1`""
$stopShortcut.WorkingDirectory = $scriptsDir
$stopShortcut.IconLocation = "powershell.exe,0"
$stopShortcut.Description = "Arrête le serveur VNC"
$stopShortcut.Save()

Write-Host "  [OK] Raccourcis créés sur bureau public" -ForegroundColor Green
Write-Host "    - Start VNC Server.lnk" -ForegroundColor Gray
Write-Host "    - Stop VNC Server.lnk" -ForegroundColor Gray

# ====================================================================
# ÉTAPE 8/8: VÉRIFICATION FINALE
# ====================================================================
Write-Host "`n[8/8] Vérification finale..." -ForegroundColor Yellow

Start-Sleep -Seconds 5

$diagnostics = @{
    "TigerVNC installé" = Test-Path $winvncPath
    "Tunnel SSH (tâche)" = $null -ne (Get-ScheduledTask -TaskName "SSH-Reverse-Tunnel-VNC" -ErrorAction SilentlyContinue)
    "Tunnel SSH (actif)" = $null -ne (Get-Process ssh -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$ReversePort*" })
    "Scripts créés" = (Test-Path "$scriptsDir\Start-VNC.ps1") -and (Test-Path "$scriptsDir\Stop-VNC.ps1")
    "Raccourcis créés" = (Test-Path "$publicDesktop\Start VNC Server.lnk") -and (Test-Path "$publicDesktop\Stop VNC Server.lnk")
}

foreach ($check in $diagnostics.GetEnumerator() | Sort-Object Name) {
    $status = if ($check.Value) { "[OK]" } else { "[ATTENTION]" }
    $color = if ($check.Value) { "Green" } else { "Yellow" }
    Write-Host "  $status $($check.Key)" -ForegroundColor $color
}

# ====================================================================
# RÉSUMÉ FINAL
# ====================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "INSTALLATION VNC TERMINÉE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nCOMPOSANTS INSTALLÉS:" -ForegroundColor Yellow
Write-Host "  ✅ TigerVNC Server" -ForegroundColor Green
Write-Host "  ✅ Tunnel SSH VNC (tâche planifiée)" -ForegroundColor Green
Write-Host "  ✅ Scripts opérationnels (Start/Stop)" -ForegroundColor Green
Write-Host "  ✅ Raccourcis bureau" -ForegroundColor Green
Write-Host "  ✅ Règles firewall (localhost only)" -ForegroundColor Green

Write-Host "`nCLÉ SSH PUBLIQUE À AJOUTER SUR RELAY:" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Gray
Get-Content "$systemKeyPath.pub"
Write-Host "========================================" -ForegroundColor Gray

Write-Host "`nPROCHAINES ÉTAPES:" -ForegroundColor Yellow
Write-Host "1. Sur relay: ./setup-relay-vnc.sh (coller clé ci-dessus)" -ForegroundColor White
Write-Host "2. Sur Windows: Double-clic 'Start VNC Server' (bureau)" -ForegroundColor White
Write-Host "3. Sur Linux: ./vnc.sh" -ForegroundColor White

Write-Host "`nPORTS VNC:" -ForegroundColor Yellow
Write-Host "  Local: 5900 (localhost only)" -ForegroundColor White
Write-Host "  Relay tunnel: $ReversePort" -ForegroundColor White

Write-Host "`nVÉRIFICATIONS RECOMMANDÉES:" -ForegroundColor Yellow
Write-Host "  Get-ScheduledTask -TaskName 'SSH-Reverse-Tunnel-VNC' | Select State" -ForegroundColor White
Write-Host "  Get-Content '$logsDir\vnc-tunnel.log' -Tail 20" -ForegroundColor White

Write-Host "`nLOGS:" -ForegroundColor Yellow
Write-Host "  Setup: $logsDir\vnc-setup.log" -ForegroundColor White
Write-Host "  Tunnel: $logsDir\vnc-tunnel.log" -ForegroundColor White
Write-Host "  Session: $logsDir\vnc-session.log" -ForegroundColor White

Write-Host "`n========================================`n" -ForegroundColor Cyan

# Log setup completion
$setupLog = "$logsDir\vnc-setup.log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"[$timestamp] VNC setup completed successfully" | Out-File -FilePath $setupLog -Append

Write-Host "Installation terminée avec succès!" -ForegroundColor Green
Write-Host ""
