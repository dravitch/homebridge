# ====================================================================
# HomeBridge - Windows Health Check Script v1.1
# Diagnostique complet de l'installation Windows
# Usage: .\windows-health-check.ps1
# Sauvegarde: windows/windows-health-check.ps1
# ====================================================================

param(
    [switch]$AutoFix = $false,
    [switch]$Verbose = $false
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host @"
===========================================
🏥 HomeBridge - Windows Health Check v1.1
===========================================
"@ -ForegroundColor Cyan

if ($AutoFix) {
    Write-Host "⚙️  Mode AutoFix activé - Corrections automatiques" -ForegroundColor Yellow
}

Write-Host ""

$script:issueCount = 0
$script:fixedCount = 0
$script:criticalIssues = @()

# ====================================================================
# FONCTIONS UTILITAIRES
# ====================================================================

function Write-Check {
    param(
        [string]$Name,
        [bool]$Status,
        [string]$Details = "",
        [string]$Fix = "",
        [bool]$Critical = $false
    )
    
    $checkNum = $script:checkNumber++
    Write-Host "[$checkNum/10] $Name..." -NoNewline
    
    if ($Status) {
        Write-Host " ✅" -ForegroundColor Green
        if ($Details) {
            Write-Host "        $Details" -ForegroundColor Gray
        }
    } else {
        Write-Host " ❌" -ForegroundColor Red
        $script:issueCount++
        
        if ($Critical) {
            $script:criticalIssues += $Name
        }
        
        if ($Details) {
            Write-Host "        ⚠️  $Details" -ForegroundColor Yellow
        }
        
        if ($Fix -and $AutoFix) {
            Write-Host "        🔧 Tentative de correction..." -ForegroundColor Cyan
            try {
                Invoke-Expression $Fix
                $script:fixedCount++
                Write-Host "        ✅ Corrigé" -ForegroundColor Green
            } catch {
                Write-Host "        ❌ Échec: $($_.Exception.Message)" -ForegroundColor Red
            }
        } elseif ($Fix) {
            Write-Host "        💡 Correction possible: $Fix" -ForegroundColor Cyan
        }
    }
}

$script:checkNumber = 1

# ====================================================================
# VÉRIFICATIONS
# ====================================================================

# 1. Service OpenSSH Server
Write-Host ""
Write-Host "🔍 Services SSH" -ForegroundColor Yellow
Write-Host "---------------" -ForegroundColor Yellow
$sshdService = Get-Service sshd
$sshdRunning = $sshdService.Status -eq 'Running'
Write-Check `
    -Name "Service OpenSSH Server" `
    -Status $sshdRunning `
    -Details $(if ($sshdRunning) { "Status: Running" } else { "Status: $($sshdService.Status)" }) `
    -Fix "Start-Service sshd; Set-Service sshd -StartupType Automatic" `
    -Critical $true

# 2. Port SSH 22
$sshPort = Get-NetTCPConnection -LocalPort 22 -State Listen
$sshPortListening = $null -ne $sshPort
Write-Check `
    -Name "Port SSH (22)" `
    -Status $sshPortListening `
    -Details $(if ($sshPortListening) { "En écoute" } else { "Pas en écoute" }) `
    -Critical $true

# 3. Firewall SSH
$firewallRule = Get-NetFirewallRule -DisplayName "*OpenSSH*" | Where-Object { $_.Enabled -eq $true }
$firewallOk = $null -ne $firewallRule
Write-Check `
    -Name "Règle firewall SSH" `
    -Status $firewallOk `
    -Details $(if ($firewallOk) { "Activée" } else { "Désactivée ou absente" }) `
    -Fix "New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22"

# ====================================================================
Write-Host ""
Write-Host "🔄 Tunnel Reverse" -ForegroundColor Yellow
Write-Host "-----------------" -ForegroundColor Yellow

# 4. Tâche planifiée tunnel
$tunnelTask = Get-ScheduledTask -TaskName "SSH-Reverse-Tunnel"
$taskExists = $null -ne $tunnelTask
if ($taskExists) {
    $taskInfo = Get-ScheduledTaskInfo -TaskName "SSH-Reverse-Tunnel"
    $taskOk = $taskInfo.LastTaskResult -eq 0
    $lastRun = $taskInfo.LastRunTime
    $nextRun = $taskInfo.NextRunTime
    
    Write-Check `
        -Name "Tâche planifiée tunnel" `
        -Status $taskOk `
        -Details $(if ($taskOk) { "Dernière exécution: $lastRun" } else { "Code erreur: $($taskInfo.LastTaskResult)" }) `
        -Fix "Start-ScheduledTask -TaskName 'SSH-Reverse-Tunnel'" `
        -Critical $true
} else {
    Write-Check `
        -Name "Tâche planifiée tunnel" `
        -Status $false `
        -Details "Tâche non trouvée" `
        -Critical $true
}

# 5. Processus SSH du tunnel
$sshProcesses = Get-Process ssh
$sshRunning = $null -ne $sshProcesses
$processCount = if ($sshProcesses) { $sshProcesses.Count } else { 0 }
Write-Check `
    -Name "Processus tunnel SSH" `
    -Status $sshRunning `
    -Details $(if ($sshRunning) { "$processCount processus actif(s)" } else { "Aucun processus SSH" }) `
    -Fix "Start-ScheduledTask -TaskName 'SSH-Reverse-Tunnel'"

# 6. Clé SSH SYSTEM
$systemSshKey = "C:\Windows\System32\config\systemprofile\.ssh\id_rsa"
$systemKeyExists = Test-Path $systemSshKey
Write-Check `
    -Name "Clé SSH SYSTEM" `
    -Status $systemKeyExists `
    -Details $(if ($systemKeyExists) { "Présente" } else { "Manquante" }) `
    -Critical $true

if ($systemKeyExists) {
    # Vérifier les permissions de la clé SYSTEM
    $systemKeyAcl = Get-Acl $systemSshKey
    $systemKeySecure = $systemKeyAcl.Access | Where-Object { 
        $_.IdentityReference -eq "NT AUTHORITY\SYSTEM" -and $_.FileSystemRights -match "FullControl"
    }
    Write-Check `
        -Name "Permissions clé SYSTEM" `
        -Status ($null -ne $systemKeySecure) `
        -Details $(if ($systemKeySecure) { "Sécurisées" } else { "À corriger" }) `
        -Fix "icacls.exe '$systemSshKey' /inheritance:r; icacls.exe '$systemSshKey' /grant 'SYSTEM:(F)'"
}

# ====================================================================
Write-Host ""
Write-Host "🔑 Authentification Utilisateur" -ForegroundColor Yellow
Write-Host "--------------------------------" -ForegroundColor Yellow

# 7. Clé autorisée utilisateur
$authorizedKeys = "$env:USERPROFILE\.ssh\authorized_keys"
$authKeysExist = Test-Path $authorizedKeys

if ($authKeysExist) {
    $keyCount = (Get-Content $authorizedKeys | Where-Object { $_ -match "^ssh-" }).Count
    $keysOk = $keyCount -gt 0
    
    Write-Check `
        -Name "Fichier authorized_keys" `
        -Status $keysOk `
        -Details $(if ($keysOk) { "$keyCount clé(s) configurée(s)" } else { "Fichier vide" })
    
    if ($keysOk) {
        # Vérifier les permissions
        $authKeysAcl = Get-Acl $authorizedKeys
        $inheritanceDisabled = $authKeysAcl.AreAccessRulesProtected
        
        Write-Check `
            -Name "Permissions authorized_keys" `
            -Status $inheritanceDisabled `
            -Details $(if ($inheritanceDisabled) { "Sécurisées (héritage désactivé)" } else { "Héritage activé (PROBLÈME)" }) `
            -Fix "icacls.exe '$authorizedKeys' /inheritance:r; icacls.exe '$authorizedKeys' /grant '${env:USERNAME}:(F)'; icacls.exe '$authorizedKeys' /grant 'SYSTEM:(F)'; Restart-Service sshd" `
            -Critical $true
    }
} else {
    Write-Check `
        -Name "Fichier authorized_keys" `
        -Status $false `
        -Details "Fichier manquant" `
        -Fix "New-Item -Path '$env:USERPROFILE\.ssh' -ItemType Directory -Force; New-Item -Path '$authorizedKeys' -ItemType File" `
        -Critical $true
}

# ====================================================================
Write-Host ""
Write-Host "🖥️  Services RDP/VNC" -ForegroundColor Yellow
Write-Host "--------------------" -ForegroundColor Yellow

# 8. Service RDP
$rdpService = Get-Service TermService
$rdpRunning = $rdpService.Status -eq 'Running'
Write-Check `
    -Name "Service RDP (TermService)" `
    -Status $rdpRunning `
    -Details $(if ($rdpRunning) { "Actif" } else { "Statut: $($rdpService.Status)" })

# 9. Port RDP 3389
$rdpPort = Get-NetTCPConnection -LocalPort 3389 -State Listen
$rdpPortOk = ($null -ne $rdpPort) -and $rdpRunning
Write-Check `
    -Name "Port RDP (3389)" `
    -Status $rdpPortOk `
    -Details $(if ($rdpPortOk) { "En écoute" } else { "Pas en écoute" })

# Détecter RDP Wrapper (Windows HOME)
$rdpWrapperPath = "C:\Program Files\RDP Wrapper\RDPWInst.exe"
if (Test-Path $rdpWrapperPath) {
    Write-Host "        ℹ️  RDP Wrapper détecté (Windows HOME)" -ForegroundColor Cyan
    if (-not $rdpPortOk) {
        Write-Host "        💡 Redémarrage Windows peut être nécessaire après installation RDP Wrapper" -ForegroundColor Yellow
    }
}

# 10. VNC (TightVNC) - optionnel
$vncService = Get-Service "tvnserver"
if ($null -ne $vncService) {
    $vncRunning = $vncService.Status -eq 'Running'
    Write-Check `
        -Name "Service VNC (TightVNC)" `
        -Status $vncRunning `
        -Details $(if ($vncRunning) { "Actif" } else { "Statut: $($vncService.Status)" })
    
    # Port VNC 5900
    $vncPort = Get-NetTCPConnection -LocalPort 5900 -State Listen
    $vncPortOk = $null -ne $vncPort
    Write-Check `
        -Name "Port VNC (5900)" `
        -Status $vncPortOk `
        -Details $(if ($vncPortOk) { "En écoute" } else { "Pas en écoute" })
} else {
    Write-Host "[10/10] Service VNC (TightVNC)... ℹ️  Non installé" -ForegroundColor Gray
}

# ====================================================================
# RÉSUMÉ
# ====================================================================
Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "📊 RÉSUMÉ DU DIAGNOSTIC" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

if ($script:issueCount -eq 0) {
    Write-Host "✅ TOUS LES COMPOSANTS SONT OPÉRATIONNELS" -ForegroundColor Green
    Write-Host ""
    Write-Host "Vous pouvez utiliser HomeBridge normalement." -ForegroundColor Green
} else {
    Write-Host "⚠️  $($script:issueCount) problème(s) détecté(s)" -ForegroundColor Yellow
    
    if ($script:criticalIssues.Count -gt 0) {
        Write-Host ""
        Write-Host "🚨 Problèmes CRITIQUES:" -ForegroundColor Red
        $script:criticalIssues | ForEach-Object {
            Write-Host "   • $_" -ForegroundColor Red
        }
    }
    
    if ($AutoFix) {
        Write-Host ""
        Write-Host "✅ $($script:fixedCount) problème(s) corrigé(s) automatiquement" -ForegroundColor Green
        Write-Host "⚠️  $($script:issueCount - $script:fixedCount) problème(s) nécessitent une intervention manuelle" -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "💡 Pour tenter des corrections automatiques:" -ForegroundColor Cyan
        Write-Host "   .\windows-health-check.ps1 -AutoFix" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "📋 Actions recommandées:" -ForegroundColor Yellow
    Write-Host "   1. Corriger les problèmes critiques en priorité" -ForegroundColor White
    Write-Host "   2. Redémarrer les services concernés" -ForegroundColor White
    Write-Host "   3. Relancer ce script pour vérifier" -ForegroundColor White
    Write-Host "   4. Si problèmes persistent: .\setup-windows.ps1" -ForegroundColor White
}

# ====================================================================
# LOG
# ====================================================================
$logDir = "$env:USERPROFILE\Documents\HomeBridge"
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

$logPath = "$logDir\health-check-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$logContent = @"
HomeBridge Health Check
=======================
Date: $timestamp
Issues: $($script:issueCount)
Fixed: $($script:fixedCount)
Critical: $($script:criticalIssues.Count)

Critical Issues:
$($script:criticalIssues | ForEach-Object { "  - $_" })

Status: $(if ($script:issueCount -eq 0) { "OK" } else { "WARNINGS" })
"@

Set-Content -Path $logPath -Value $logContent

Write-Host ""
Write-Host "📄 Log sauvegardé: $logPath" -ForegroundColor Gray
Write-Host ""
Write-Host "💡 Conseil: Exécuter ce script après chaque redémarrage Windows" -ForegroundColor Cyan
Write-Host ""
