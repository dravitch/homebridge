# ====================================================================
# SETUP WINDOWS COMPLET
# Configuration SSH, Tunnel Reverse, RDP et Diagnostic
# ====================================================================
# Variables à personnaliser (charger depuis config.env si disponible)

param(
    [string]$RelayServer = "RELAY_IP",
    [string]$RelayUser = "tunnel",
    [int]$ReversePort = 2222
)

Write-Host @"
========================================
SETUP WINDOWS COMPLET
Configuration: SSH + Tunnel + RDP
========================================
"@ -ForegroundColor Cyan

# Vérifier privilèges admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERREUR] Privilèges administrateur requis!" -ForegroundColor Red
    exit 1
}

$systemProfileDir = "C:\Windows\System32\config\systemprofile"
$systemSshDir = "$systemProfileDir\.ssh"
$systemKeyPath = "$systemSshDir\id_rsa"
$systemScriptPath = "$systemProfileDir\ssh-reverse-tunnel.ps1"
$taskName = "SSH-Reverse-Tunnel"

# ====================================================================
# PARTIE 1/4 : CONFIGURATION SSH
# ====================================================================
Write-Host "`n[1/4] Configuration OpenSSH..." -ForegroundColor Yellow

# Installer OpenSSH si nécessaire
$sshInstalled = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'
if ($sshInstalled.State -ne "Installed") {
    Write-Host "  Installation OpenSSH Client..." -ForegroundColor Gray
    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
}

$sshdInstalled = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($sshdInstalled.State -ne "Installed") {
    Write-Host "  Installation OpenSSH Server..." -ForegroundColor Gray
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}

# Démarrer et configurer le service SSH
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

# Configurer le pare-feu
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue

Write-Host "  [OK] OpenSSH configuré" -ForegroundColor Green

# ====================================================================
# PARTIE 2/4 : CONFIGURATION TUNNEL REVERSE SOUS SYSTEM
# ====================================================================
Write-Host "`n[2/4] Configuration du tunnel reverse (SYSTEM)..." -ForegroundColor Yellow

# Créer le répertoire SSH pour SYSTEM
if (-not (Test-Path $systemSshDir)) {
    New-Item -Path $systemSshDir -ItemType Directory -Force | Out-Null
}

# Copier ou générer la clé SSH pour SYSTEM
$userKeyPath = "$env:USERPROFILE\.ssh\id_rsa"
if (Test-Path $userKeyPath) {
    Copy-Item "$userKeyPath" "$systemKeyPath" -Force
    Copy-Item "$userKeyPath.pub" "$systemKeyPath.pub" -Force
} else {
    & ssh-keygen -t rsa -b 4096 -C "windows-to-relay" -f "$systemKeyPath" -N '""' | Out-Null
}

# Configurer known_hosts
$knownHostsPath = "$systemSshDir\known_hosts"
$serverKey = & ssh-keyscan -H $RelayServer 2>$null
if ($serverKey) {
    Set-Content -Path $knownHostsPath -Value $serverKey
}

# Créer le script de tunnel
$tunnelScript = @"
`$RELAY_SERVER = "$RelayServer"
`$RELAY_USER   = "$RelayUser"
`$REVERSE_PORT = $ReversePort
`$LOCAL_SSH_PORT = 22
`$SSH_KEY_PATH = "$systemKeyPath"

Stop-Process -Name ssh -Force -ErrorAction SilentlyContinue

while (`$true) {
    Write-Host "[`$(Get-Date)] Tunnel SSH vers `$RELAY_SERVER..." -ForegroundColor Yellow
    
    ssh -i "`$SSH_KEY_PATH" -N -T ``
        -R `${REVERSE_PORT}:127.0.0.1:`${LOCAL_SSH_PORT} ``
        -o ServerAliveInterval=60 ``
        -o ServerAliveCountMax=3 ``
        -o ExitOnForwardFailure=yes ``
        -o StrictHostKeyChecking=no ``
        `${RELAY_USER}@`${RELAY_SERVER}
    
    Write-Host "[`$(Get-Date)] Tunnel interrompu, reconnexion dans 10s..." -ForegroundColor Red
    Start-Sleep -Seconds 10
}
"@

Set-Content -Path $systemScriptPath -Value $tunnelScript

# Permissions
icacls.exe "$systemKeyPath" /inheritance:r | Out-Null
icacls.exe "$systemKeyPath" /grant "SYSTEM:(F)" | Out-Null
icacls.exe "$systemScriptPath" /grant "SYSTEM:(R)" | Out-Null

# Créer la tâche planifiée
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$systemScriptPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 999

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

# Démarrer le tunnel
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 3

Write-Host "  [OK] Tunnel configuré et démarré" -ForegroundColor Green

# ====================================================================
# PARTIE 3/4 : CONFIGURATION RDP
# ====================================================================
Write-Host "`n[3/4] Configuration RDP..." -ForegroundColor Yellow

# Détecter la version de Windows
$osVersion = (Get-WmiObject -Class Win32_OperatingSystem).Caption

if ($osVersion -match "Home") {
    Write-Host "  Windows HOME détecté, installation RDP Wrapper..." -ForegroundColor Gray
    
    # Télécharger et installer RDP Wrapper
    $rdpWrapUrl = "https://github.com/stascorp/rdpwrap/releases/download/v1.6.2/RDPWrap-v1.6.2.zip"
    $rdpWrapZip = "$env:TEMP\RDPWrap.zip"
    $rdpWrapDir = "$env:TEMP\RDPWrap"
    
    try {
        Invoke-WebRequest -Uri $rdpWrapUrl -OutFile $rdpWrapZip -UseBasicParsing
        Expand-Archive -Path $rdpWrapZip -DestinationPath $rdpWrapDir -Force
        
        Stop-Service -Name TermService -Force -ErrorAction SilentlyContinue
        
        $installBat = Join-Path $rdpWrapDir "install.bat"
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$installBat`"" -Wait -NoNewWindow
        
        # Mettre à jour rdpwrap.ini pour Windows 11
        $iniUrl = "https://raw.githubusercontent.com/sebaxakerhtc/rdpwrap.ini/master/rdpwrap.ini"
        $iniPath = "$env:ProgramFiles\RDP Wrapper\rdpwrap.ini"
        Invoke-WebRequest -Uri $iniUrl -OutFile $iniPath -UseBasicParsing -ErrorAction SilentlyContinue
        
        Restart-Service -Name TermService -ErrorAction SilentlyContinue
        
        Write-Host "  [OK] RDP Wrapper installé (redémarrage recommandé)" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Échec installation RDP Wrapper, installation manuelle nécessaire" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Windows PRO/Enterprise détecté, activation RDP native..." -ForegroundColor Gray
    
    # Activer RDP
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Bureau à distance" -ErrorAction SilentlyContinue
    
    Write-Host "  [OK] RDP activé" -ForegroundColor Green
}

# ====================================================================
# PARTIE 4/4 : DIAGNOSTIC ET VERIFICATION
# ====================================================================
Write-Host "`n[4/4] Vérification finale..." -ForegroundColor Yellow

$diagnostics = @{
    "SSH Server" = (Get-Service sshd).Status -eq 'Running'
    "SSH Port 22" = $null -ne (Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue)
    "Tunnel Task" = $null -ne (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
    "SSH Process" = $null -ne (Get-Process ssh -ErrorAction SilentlyContinue)
    "RDP Service" = (Get-Service TermService).Status -eq 'Running'
    "RDP Port 3389" = $null -ne (Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue)
}

Write-Host "`n  Statut des services:" -ForegroundColor Cyan
foreach ($check in $diagnostics.GetEnumerator()) {
    $status = if ($check.Value) { "[OK]" } else { "[ERREUR]" }
    $color = if ($check.Value) { "Green" } else { "Red" }
    Write-Host "    $status $($check.Key)" -ForegroundColor $color
}

# ====================================================================
# AFFICHAGE DES INSTRUCTIONS FINALES
# ====================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "CONFIGURATION TERMINÉE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nCLÉ PUBLIQUE À AJOUTER SUR LE RELAY:" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Gray
Get-Content "$systemKeyPath.pub"
Write-Host "========================================" -ForegroundColor Gray

Write-Host "`nPROCHAINES ÉTAPES:" -ForegroundColor Yellow
Write-Host "1. Copier la clé publique ci-dessus" -ForegroundColor White
Write-Host "2. Sur le relay, exécuter: ./setup-relay.sh" -ForegroundColor White
Write-Host "3. Coller la clé quand demandé" -ForegroundColor White
Write-Host "4. Sur le client, exécuter: ./setup-client.sh" -ForegroundColor White

if ($osVersion -match "Home" -and -not $diagnostics["RDP Port 3389"]) {
    Write-Host "`n[INFO] RDP Wrapper installé, redémarrage Windows recommandé:" -ForegroundColor Yellow
    Write-Host "  Restart-Computer -Force" -ForegroundColor White
}

Write-Host "`n========================================`n" -ForegroundColor Cyan