# ====================================================================
# STOP VNC SERVER - HomeBridge v1.1
# Arrête WinVNC proprement
# Usage: Double-clic sur raccourci bureau OU .\Stop-VNC.ps1
# ====================================================================

$logsDir = "C:\HomeBridge\logs"
$logFile = "$logsDir\vnc-session.log"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -Append $logFile -ErrorAction SilentlyContinue
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ARRÊT VNC SERVER" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Recherche des processus VNC..." -ForegroundColor Yellow

$processes = Get-Process winvnc4 -ErrorAction SilentlyContinue

if ($processes) {
    Write-Host "  Trouvé: $($processes.Count) processus VNC" -ForegroundColor Gray
    
    foreach ($proc in $processes) {
        Write-Host "  - PID $($proc.Id)" -ForegroundColor Gray
    }
    
    Write-Host "`nArrêt en cours..." -ForegroundColor Yellow
    $processes | Stop-Process -Force
    Start-Sleep -Seconds 1
    
    # Vérification arrêt
    $remaining = Get-Process winvnc4 -ErrorAction SilentlyContinue
    
    if (-not $remaining) {
        Write-Host "" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "✅ VNC SERVER ARRÊTÉ" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "" -ForegroundColor Green
        Write-Log "VNC Server arrêté"
    } else {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "⚠️ ARRÊT PARTIEL" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
        Write-Host "Certains processus VNC sont toujours actifs:" -ForegroundColor Yellow
        $remaining | ForEach-Object { Write-Host "  - PID $($_.Id)" -ForegroundColor Gray }
        Write-Host "" -ForegroundColor Yellow
        Write-Host "Tentez d'arrêter manuellement:" -ForegroundColor Gray
        Write-Host "  Get-Process winvnc4 | Stop-Process -Force" -ForegroundColor White
        Write-Host "" -ForegroundColor Yellow
        Write-Log "ATTENTION: Arrêt partiel VNC"
    }
    
} else {
    Write-Host "" -ForegroundColor Gray
    Write-Host "========================================" -ForegroundColor Gray
    Write-Host "ℹ️ VNC SERVER NON ACTIF" -ForegroundColor Gray
    Write-Host "========================================" -ForegroundColor Gray
    Write-Host "" -ForegroundColor Gray
    Write-Host "Aucun processus VNC n'est actuellement en cours d'exécution." -ForegroundColor Gray
    Write-Host "" -ForegroundColor Gray
    Write-Log "VNC Server n'était pas actif"
}

Write-Host ""
pause
