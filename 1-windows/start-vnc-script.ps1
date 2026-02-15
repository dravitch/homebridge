# ====================================================================
# START VNC SERVER - HomeBridge v1.1
# Lance WinVNC sous compte utilisateur avec SecurityTypes None
# Usage: Double-clic sur raccourci bureau OU .\Start-VNC.ps1
# ====================================================================

$winvncExe = "C:\Program Files\TigerVNC Server\winvnc4.exe"
$logsDir = "C:\HomeBridge\logs"
$logFile = "$logsDir\vnc-session.log"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -Append $logFile -ErrorAction SilentlyContinue
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DÉMARRAGE VNC SERVER" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ====================================================================
# VÉRIFICATION 1/3: TigerVNC installé
# ====================================================================
Write-Host "[1/3] Vérification TigerVNC..." -ForegroundColor Yellow

if (-not (Test-Path $winvncExe)) {
    Write-Host "  [ERREUR] WinVNC non trouvé: $winvncExe" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "  TigerVNC n'est pas installé ou chemin incorrect." -ForegroundColor Yellow
    Write-Host "  Téléchargez depuis: http://tigervnc.bphinz.com/nightly/" -ForegroundColor White
    Write-Host "  Ou exécutez: .\setup-windows-vnc.ps1" -ForegroundColor White
    Write-Host "" -ForegroundColor Red
    Write-Log "ERREUR: WinVNC non trouvé"
    pause
    exit 1
}

Write-Host "  [OK] TigerVNC présent" -ForegroundColor Green
Write-Log "TigerVNC trouvé: $winvncExe"

# ====================================================================
# VÉRIFICATION 2/3: Tunnel SSH
# ====================================================================
Write-Host "`n[2/3] Vérification tunnel SSH..." -ForegroundColor Yellow

$tunnelTask = Get-ScheduledTask -TaskName "SSH-Reverse-Tunnel-VNC" -ErrorAction SilentlyContinue

if ($tunnelTask) {
    if ($tunnelTask.State -eq "Running") {
        Write-Host "  [OK] Tunnel SSH actif" -ForegroundColor Green
        Write-Log "Tunnel SSH actif"
    } else {
        Write-Host "  [INFO] Démarrage du tunnel SSH..." -ForegroundColor Cyan
        Start-ScheduledTask -TaskName "SSH-Reverse-Tunnel-VNC"
        Start-Sleep -Seconds 5
        
        $tunnelTask = Get-ScheduledTask -TaskName "SSH-Reverse-Tunnel-VNC" -ErrorAction SilentlyContinue
        if ($tunnelTask.State -eq "Running") {
            Write-Host "  [OK] Tunnel SSH démarré" -ForegroundColor Green
            Write-Log "Tunnel SSH démarré"
        } else {
            Write-Host "  [ATTENTION] Tunnel SSH non actif" -ForegroundColor Yellow
            Write-Host "  Le VNC sera accessible uniquement en local" -ForegroundColor Gray
            Write-Log "ATTENTION: Tunnel SSH non actif"
        }
    }
} else {
    Write-Host "  [ATTENTION] Tunnel SSH non configuré" -ForegroundColor Yellow
    Write-Host "  Le VNC sera accessible uniquement en local" -ForegroundColor Gray
    Write-Host "  Pour configurer: .\setup-windows-vnc.ps1" -ForegroundColor White
    Write-Log "ATTENTION: Tunnel SSH non configuré"
}

# ====================================================================
# VÉRIFICATION 3/3: Port 5900
# ====================================================================
Write-Host "`n[3/3] Vérification port 5900..." -ForegroundColor Yellow

$portInUse = Get-NetTCPConnection -LocalPort 5900 -State Listen -ErrorAction SilentlyContinue

if ($portInUse) {
    Write-Host "  [INFO] Port 5900 déjà utilisé, nettoyage..." -ForegroundColor Cyan
    
    # Arrêt des processus VNC existants
    $existing = Get-Process winvnc4 -ErrorAction SilentlyContinue
    if ($existing) {
        $existing | Stop-Process -Force
        Start-Sleep -Seconds 2
        Write-Host "  [OK] Processus VNC existants arrêtés" -ForegroundColor Green
        Write-Log "Processus VNC existants arrêtés"
    }
} else {
    Write-Host "  [OK] Port 5900 disponible" -ForegroundColor Green
}

# ====================================================================
# DÉMARRAGE VNC
# ====================================================================
Write-Host "`n[DÉMARRAGE] Lancement WinVNC..." -ForegroundColor Yellow
Write-Host "  Configuration: SecurityTypes=None (tunnel SSH)" -ForegroundColor Gray
Write-Log "Démarrage WinVNC (SecurityTypes=None)"

try {
    Start-Process -FilePath $winvncExe -ArgumentList "-SecurityTypes None" -WindowStyle Hidden
    Start-Sleep -Seconds 3
    
    # Vérification démarrage
    $process = Get-Process winvnc4 -ErrorAction SilentlyContinue
    
    if ($process) {
        Write-Host "" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "✅ VNC SERVER DÉMARRÉ AVEC SUCCÈS" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "" -ForegroundColor Green
        Write-Host "  PID: $($process.Id)" -ForegroundColor White
        Write-Host "  Port: 5900 (localhost)" -ForegroundColor White
        Write-Log "VNC démarré avec succès (PID: $($process.Id))"
        
        # Vérification port écoute
        Start-Sleep -Seconds 2
        $port = Get-NetTCPConnection -LocalPort 5900 -State Listen -ErrorAction SilentlyContinue
        
        if ($port) {
            Write-Host "  État: En écoute ✓" -ForegroundColor Green
            Write-Host "" -ForegroundColor Green
            Write-Host "Le serveur VNC est prêt pour les connexions." -ForegroundColor Cyan
            Write-Host "Depuis Linux: ./vnc.sh" -ForegroundColor White
        } else {
            Write-Host "  État: Démarré mais port non détecté" -ForegroundColor Yellow
            Write-Host "" -ForegroundColor Yellow
            Write-Host "Le processus VNC est actif mais le port n'est pas encore en écoute." -ForegroundColor Yellow
            Write-Host "Attendez 10 secondes et vérifiez:" -ForegroundColor Gray
            Write-Host "  Get-NetTCPConnection -LocalPort 5900 -State Listen" -ForegroundColor White
            Write-Log "ATTENTION: Port 5900 non détecté immédiatement"
        }
        
    } else {
        Write-Host "" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "❌ ÉCHEC DÉMARRAGE VNC" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "" -ForegroundColor Red
        Write-Host "Le processus WinVNC n'a pas démarré." -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
        Write-Host "VÉRIFICATIONS:" -ForegroundColor Yellow
        Write-Host "  1. Vérifier les logs: $logsDir\vnc-session.log" -ForegroundColor White
        Write-Host "  2. Tester manuellement:" -ForegroundColor White
        Write-Host "     & '$winvncExe' -SecurityTypes None" -ForegroundColor White
        Write-Host "  3. Exécuter diagnostic:" -ForegroundColor White
        Write-Host "     .\Verify-VNC.ps1" -ForegroundColor White
        Write-Host "" -ForegroundColor Red
        Write-Log "ERREUR: Échec démarrage VNC"
    }
    
} catch {
    Write-Host "" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "❌ ERREUR CRITIQUE" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Red
    Write-Host "Consultez les logs: $logsDir\vnc-session.log" -ForegroundColor White
    Write-Host "" -ForegroundColor Red
    Write-Log "ERREUR CRITIQUE: $($_.Exception.Message)"
}

Write-Host "" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Gray
Write-Host "Pour arrêter VNC: Double-clic 'Stop VNC Server'" -ForegroundColor Gray
Write-Host "Ou exécutez: .\Stop-VNC.ps1" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Gray
Write-Host ""

pause
