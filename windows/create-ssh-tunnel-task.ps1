# =====================================================================
# CREATE SSH-REVERSE-TUNNEL-VNC TASK - HomeBridge
# =====================================================================

Write-Host "=== CREATING SSH-REVERSE-TUNNEL-VNC TASK ===" -ForegroundColor Cyan

# Variables (adapter Ã  ton setup)
$RelayServer = "172.234.175.48"  # TON IP RELAY
$RelayUser = "tunnel"
$ReversePort = 15900

$systemProfileDir = "C:\Windows\System32\config\systemprofile"
$systemSshDir = "$systemProfileDir\.ssh"
$systemKeyPath = "$systemSshDir\id_rsa"
$systemScriptPath = "$systemProfileDir\ssh-reverse-tunnel-vnc.ps1"
$taskName = "SSH-Reverse-Tunnel-VNC"

# 1. VÃ©rifier clÃ© SSH existe
Write-Host "[1/4] Checking SSH key..." -ForegroundColor Yellow
if (-not (Test-Path $systemKeyPath)) {
    Write-Host "  Generating SYSTEM SSH key..." -ForegroundColor Gray
    New-Item -Path $systemSshDir -ItemType Directory -Force | Out-Null
    ssh-keygen -t rsa -b 4096 -C "windows-vnc-tunnel" -f "$systemKeyPath" -N '""'
    Write-Host "  [OK] Key generated" -ForegroundColor Green
    
    Write-Host "`n  PUBLIC KEY TO ADD ON RELAY:" -ForegroundColor Yellow
    Write-Host "  =====================================" -ForegroundColor Gray
    Get-Content "$systemKeyPath.pub"
    Write-Host "  =====================================" -ForegroundColor Gray
    Write-Host ""
    Read-Host "  Press Enter after adding key to relay"
} else {
    Write-Host "  [OK] SSH key exists" -ForegroundColor Green
}

# 2. known_hosts
Write-Host "`n[2/4] Updating known_hosts..." -ForegroundColor Yellow
$knownHostsPath = "$systemSshDir\known_hosts"
$serverKey = ssh-keyscan -H $RelayServer 2>$null
if ($serverKey) {
    $existingKeys = if (Test-Path $knownHostsPath) { Get-Content $knownHostsPath } else { @() }
    $serverKeyStr = [string]$serverKey
    if ($existingKeys -notcontains $serverKeyStr) {
        Add-Content -Path $knownHostsPath -Value $serverKey
        Write-Host "  [OK] Added relay to known_hosts" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Relay already in known_hosts" -ForegroundColor Green
    }
}

# 3. CrÃ©er script tunnel
Write-Host "`n[3/4] Creating tunnel script..." -ForegroundColor Yellow
$tunnelScript = @"
# SSH Reverse Tunnel for VNC
`$RELAY_SERVER = "$RelayServer"
`$RELAY_USER   = "$RelayUser"
`$REVERSE_PORT = $ReversePort
`$LOCAL_VNC_PORT = 5900
`$SSH_KEY_PATH = "$systemKeyPath"
`$logFile = "C:\HomeBridge\logs\vnc-tunnel.log"

function Write-Log {
    param(`$Message)
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    `$logMessage = "[`$timestamp] `$Message"
    Write-Output `$logMessage | Out-File -FilePath `$logFile -Append -Encoding UTF8
}

Get-Process ssh -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

while (`$true) {
    Write-Log "Establishing VNC SSH reverse tunnel to `$RELAY_SERVER..."
    Write-Log "  Local VNC port: `$LOCAL_VNC_PORT"
    Write-Log "  Remote relay port: `$REVERSE_PORT"

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
        Write-Log "Starting SSH tunnel process..."
        `$process = Start-Process -FilePath "ssh" -ArgumentList `$sshArgs -NoNewWindow -PassThru -Wait
        `$exitCode = `$process.ExitCode
        Write-Log "SSH tunnel exited with code: `$exitCode"
    } catch {
        Write-Log "ERROR: SSH tunnel failed - `$(`$_.Exception.Message)"
    }

    Write-Log "Tunnel interrupted, reconnecting in 10 seconds..."
    Start-Sleep -Seconds 10
}
"@

Set-Content -Path $systemScriptPath -Value $tunnelScript -Force

# Permissions
icacls.exe "$systemKeyPath" /inheritance:r 2>&1 | Out-Null
icacls.exe "$systemKeyPath" /grant "SYSTEM:(F)" 2>&1 | Out-Null
icacls.exe "$systemScriptPath" /grant "SYSTEM:(R)" 2>&1 | Out-Null

Write-Host "  [OK] Tunnel script created: $systemScriptPath" -ForegroundColor Green

# 4. CrÃ©er scheduled task
Write-Host "`n[4/4] Creating scheduled task..." -ForegroundColor Yellow

$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$systemScriptPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 999 -ExecutionTimeLimit (New-TimeSpan -Days 0)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

Write-Host "  [OK] Scheduled task created" -ForegroundColor Green

# 5. DÃ©marrer
Write-Host "`nStarting SSH tunnel..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 5

# 6. VÃ©rifier
$sshProcess = Get-Process ssh -ErrorAction SilentlyContinue
if ($sshProcess) {
    Write-Host "  [OK] SSH process running (PID: $($sshProcess.Id))" -ForegroundColor Green
} else {
    Write-Host "  [WARN] SSH process not detected yet (check logs)" -ForegroundColor Yellow
}

Write-Host "`n=== TUNNEL TASK CREATED ===" -ForegroundColor Green
Write-Host ""
Write-Host "Verify on relay in 10 seconds:" -ForegroundColor Yellow
Write-Host "  sudo ss -tlnp | grep 15900" -ForegroundColor Gray
Write-Host ""
Write-Host "Check tunnel logs:" -ForegroundColor Yellow
Write-Host "  Get-Content C:\HomeBridge\logs\vnc-tunnel.log -Tail 20" -ForegroundColor Gray
Write-Host ""
