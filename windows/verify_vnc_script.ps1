# ====================================================================
# VERIFY VNC SETUP - HomeBridge v1.1
# Diagnostic complet de l'installation et configuration VNC
# Usage: .\Verify-VNC.ps1
# ====================================================================

$allGood = $true
$warnings = @()
$errors = @()

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DIAGNOSTIC VNC - HomeBridge v1.1" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ====================================================================
# [1/7] Installation TigerVNC
# ====================================================================
Write-Host "[1/7] Installation TigerVNC" -ForegroundColor Yellow

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
    Write-Host "  [OK] WinVNC trouvé: $winvncPath" -ForegroundColor Green
    
    # Detect version if possible
    try {
        $versionInfo = (Get-Item $winvncPath).VersionInfo
        if ($versionInfo.ProductVersion) {
            Write-Host "  [OK] Version: $($versionInfo.ProductVersion)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [INFO] Version non détectable" -ForegroundColor Gray
    }
} else {
    Write-Host "  [FAIL] WinVNC non trouvé" -ForegroundColor Red
    Write-Host "         Installez depuis: http://tigervnc.bphinz.com/nightly/" -ForegroundColor Gray
    Write-Host "         Ou exécutez: .\setup-windows-vnc.ps1" -ForegroundColor Gray
    $allGood = $false
    $errors += "TigerVNC non installé"
}

# ====================================================================
# [2/7] Processus VNC
# ====================================================================
Write-Host "`n[2/7] Processus VNC" -ForegroundColor Yellow

$vncProcess = Get-Process winvnc4 -ErrorAction SilentlyContinue

if ($vncProcess) {
    $uptime = (Get-Date) - $vncProcess.StartTime
    $uptimeStr = "{0:hh\:mm\:ss}" -f $uptime
    Write-Host "  [OK] winvnc4.exe actif (PID: $($vncProcess.Id))" -ForegroundColor Green
    Write-Host "  [OK] Uptime: $uptimeStr" -ForegroundColor Green
    
    # Check port listening
    $port = Get-NetTCPConnection -LocalPort 5900 -State Listen -ErrorAction SilentlyContinue
    if ($port) {
        Write-Host "  [OK] Port 5900 en écoute" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Port 5900 n'écoute pas" -ForegroundColor Yellow
        Write-Host "         Le processus VNC est actif mais le port n'est pas ouvert" -ForegroundColor Gray
        $warnings += "Port 5900 non en écoute"
    }
} else {
    Write-Host "  [INFO] winvnc4.exe non actif" -ForegroundColor Gray
    Write-Host "         Pour démarrer: Double-clic 'Start VNC Server' (bureau)" -ForegroundColor Gray
    Write-Host "         Ou exécutez: .\Start-VNC.ps1" -ForegroundColor Gray
}

# ====================================================================
# [3/7] Tâches planifiées
# ====================================================================
Write-Host "`n[3/7] Tâches planifiées" -ForegroundColor Yellow

# SSH Tunnel task
$tunnelTask = Get-ScheduledTask -TaskName "SSH-Reverse-Tunnel-VNC" -ErrorAction SilentlyContinue
if ($tunnelTask) {
    $state = $tunnelTask.State
    $stateColor = if ($state -eq "Running") { "Green" } else { "Yellow" }
    Write-Host "  [OK] SSH-Reverse-Tunnel-VNC: $state" -ForegroundColor $stateColor
    
    if ($state -ne "Running") {
        Write-Host "         Démarrez avec: Start-ScheduledTask -TaskName 'SSH-Reverse-Tunnel-VNC'" -ForegroundColor Gray
        $warnings += "Tunnel SSH non actif"
    }
    
    # Check last run
    $taskInfo = Get-ScheduledTaskInfo -TaskName "SSH-Reverse-Tunnel-VNC" -ErrorAction SilentlyContinue
    if ($taskInfo.LastRunTime) {
        Write-Host "  [INFO] Dernière exécution: $($taskInfo.LastRunTime)" -ForegroundColor Gray
    }
} else {
    Write-Host "  [FAIL] SSH-Reverse-Tunnel-VNC non trouvé" -ForegroundColor Red
    Write-Host "         Créez avec: .\setup-windows-vnc.ps1" -ForegroundColor Gray
    $allGood = $false
    $errors += "Tâche tunnel SSH manquante"
}

# ====================================================================
# [4/7] Tunnel SSH
# ====================================================================
Write-Host "`n[4/7] Tunnel SSH" -ForegroundColor Yellow

# Check SSH process
$sshProcess = Get-Process ssh -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -like "*15900:127.0.0.1:5900*"
}

if ($sshProcess) {
    Write-Host "  [OK] Processus ssh.exe actif (PID: $($sshProcess.Id))" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Processus ssh.exe non détecté" -ForegroundColor Yellow
    Write-Host "         Le tunnel peut ne pas être établi" -ForegroundColor Gray
    $warnings += "Processus SSH tunnel non détecté"
}

# Check SSH key
$systemKeyPath = "C:\Windows\System32\config\systemprofile\.ssh\id_rsa"
if (Test-Path $systemKeyPath) {
    Write-Host "  [OK] Clé SSH SYSTEM existe" -ForegroundColor Green
    
    $pubKeyPath = "$systemKeyPath.pub"
    if (Test-Path $pubKeyPath) {
        Write-Host "  [OK] Clé publique existe" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Clé publique manquante" -ForegroundColor Yellow
        $warnings += "Clé publique SSH manquante"
    }
} else {
    Write-Host "  [FAIL] Clé SSH SYSTEM non trouvée" -ForegroundColor Red
    Write-Host "         Générez avec: ssh-keygen -t rsa -b 4096" -ForegroundColor Gray
    $allGood = $false
    $errors += "Clé SSH manquante"
}

# Test relay connection (non-blocking)
Write-Host "  [INFO] Test connexion relay..." -ForegroundColor Gray
try {
    $testJob = Start-Job -ScriptBlock {
        param($key, $relay)
        & ssh -i $key -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no tunnel@$relay "echo OK" 2>$null
    } -ArgumentList $systemKeyPath, "172.234.175.48"
    
    $testResult = Wait-Job $testJob -Timeout 10 | Receive-Job
    Remove-Job $testJob -Force
    
    if ($testResult -match "OK") {
        Write-Host "  [OK] Connexion relay réussie" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Connexion relay échouée" -ForegroundColor Yellow
        Write-Host "         Vérifiez que la clé est autorisée sur le relay" -ForegroundColor Gray
        $warnings += "Connexion relay échouée"
    }
} catch {
    Write-Host "  [WARN] Test relay timeout" -ForegroundColor Yellow
    $warnings += "Test relay timeout"
}

# ====================================================================
# [5/7] Port distant (Relay)
# ====================================================================
Write-Host "`n[5/7] Port distant (Relay)" -ForegroundColor Yellow

Write-Host "  [INFO] Vérification port 15900 sur relay..." -ForegroundColor Gray
try {
    $relayJob = Start-Job -ScriptBlock {
        param($key, $relay)
        & ssh -i $key -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no tunnel@$relay "ss -tlnp | grep 15900" 2>$null
    } -ArgumentList $systemKeyPath, "172.234.175.48"
    
    $relayResult = Wait-Job $relayJob -Timeout 10 | Receive-Job
    Remove-Job $relayJob -Force
    
    if ($relayResult -match "15900") {
        Write-Host "  [OK] Port 15900 en écoute sur relay" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Port 15900 non détecté sur relay" -ForegroundColor Yellow
        Write-Host "         Le tunnel reverse peut ne pas être établi" -ForegroundColor Gray
        $warnings += "Port 15900 non ouvert sur relay"
    }
} catch {
    Write-Host "  [WARN] Impossible de vérifier le relay" -ForegroundColor Yellow
    Write-Host "         Ceci peut être normal si le relay est inaccessible" -ForegroundColor Gray
}

# ====================================================================
# [6/7] Firewall
# ====================================================================
Write-Host "`n[6/7] Firewall Windows" -ForegroundColor Yellow

$firewallRule = Get-NetFirewallRule -Name "HomeBridge-VNC-In" -ErrorAction SilentlyContinue

if ($firewallRule) {
    $enabled = $firewallRule.Enabled
    $enabledColor = if ($enabled -eq "True") { "Green" } else { "Yellow" }
    Write-Host "  [OK] Règle HomeBridge-VNC-In: $enabled" -ForegroundColor $enabledColor
    
    # Check rule details
    $addressFilter = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $firewallRule
    if ($addressFilter.LocalAddress -contains "127.0.0.1") {
        Write-Host "  [OK] Configuration: Localhost only (sécurisé)" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Configuration: Non limité à localhost" -ForegroundColor Yellow
        $warnings += "Règle firewall non limitée à localhost"
    }
} else {
    Write-Host "  [WARN] Règle firewall non trouvée" -ForegroundColor Yellow
    Write-Host "         Ceci est acceptable si VNC est uniquement sur localhost" -ForegroundColor Gray
}

# ====================================================================
# [7/7] Logs récents
# ====================================================================
Write-Host "`n[7/7] Logs récents" -ForegroundColor Yellow

$logsDir = "C:\HomeBridge\logs"
$logFiles = @{
    "Session" = "$logsDir\vnc-session.log"
    "Tunnel" = "$logsDir\vnc-tunnel.log"
}

foreach ($logType in $logFiles.GetEnumerator()) {
    if (Test-Path $logType.Value) {
        $lastLines = Get-Content $logType.Value -Tail 3 -ErrorAction SilentlyContinue
        if ($lastLines) {
            Write-Host "  [INFO] $($logType.Key) (dernières lignes):" -ForegroundColor Gray
            $lastLines | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            
            # Check for errors
            $recentErrors = Get-Content $logType.Value -Tail 20 | Select-String -Pattern "ERROR|ERREUR|FAIL"
            if ($recentErrors) {
                Write-Host "  [WARN] Erreurs détectées dans $($logType.Key)" -ForegroundColor Yellow
                $warnings += "Erreurs dans log $($logType.Key)"
            }
        }
    } else {
        Write-Host "  [INFO] Log $($logType.Key) non trouvé (normal si jamais démarré)" -ForegroundColor Gray
    }
}

# ====================================================================
# RÉSUMÉ GLOBAL
# ====================================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RÉSUMÉ DU DIAGNOSTIC" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($allGood -and $warnings.Count -eq 0) {
    Write-Host "✅ TOUS LES CHECKS OK" -ForegroundColor Green
    Write-Host "" -ForegroundColor Green
    Write-Host "Votre installation VNC est opérationnelle." -ForegroundColor Green
    Write-Host "" -ForegroundColor Green
    Write-Host "UTILISATION:" -ForegroundColor Yellow
    Write-Host "  Windows: Double-clic 'Start VNC Server' (bureau)" -ForegroundColor White
    Write-Host "  Linux: ./vnc.sh" -ForegroundColor White
    
} elseif ($errors.Count -gt 0) {
    Write-Host "❌ ERREURS CRITIQUES DÉTECTÉES" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "Problèmes trouvés:" -ForegroundColor Yellow
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "" -ForegroundColor Red
    Write-Host "ACTIONS REQUISES:" -ForegroundColor Yellow
    Write-Host "  1. Corrigez les erreurs ci-dessus" -ForegroundColor White
    Write-Host "  2. Relancez: .\setup-windows-vnc.ps1" -ForegroundColor White
    Write-Host "  3. Relancez ce diagnostic: .\Verify-VNC.ps1" -ForegroundColor White
    
} else {
    Write-Host "⚠️ AVERTISSEMENTS DÉTECTÉS" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Yellow
    Write-Host "Avertissements:" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host "" -ForegroundColor Yellow
    Write-Host "L'installation fonctionne mais pourrait avoir des problèmes." -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Yellow
    Write-Host "ACTIONS SUGGÉRÉES:" -ForegroundColor Yellow
    Write-Host "  1. Vérifiez les avertissements ci-dessus" -ForegroundColor White
    Write-Host "  2. Si VNC ne fonctionne pas, consultez:" -ForegroundColor White
    Write-Host "     - $logsDir\vnc-session.log" -ForegroundColor White
    Write-Host "     - $logsDir\vnc-tunnel.log" -ForegroundColor White
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Return exit code
if ($allGood -and $warnings.Count -eq 0) {
    exit 0
} elseif ($errors.Count -gt 0) {
    exit 2
} else {
    exit 1
}
