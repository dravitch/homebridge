# ====================================================================
# VNC Prerequisites Check
# Vérifie que tout est en place pour VNC
# ====================================================================

$allGood = $true

Write-Host "`n=== VNC Prerequisites Check ===" -ForegroundColor Cyan
Write-Host ""

# 1. WinVNC executable
Write-Host "[1/5] WinVNC Installation" -ForegroundColor Yellow
$winvncPath = "C:\Program Files\TigerVNC Server\winvnc4.exe"
if (Test-Path $winvncPath) {
    Write-Host "  [OK] WinVNC found: $winvncPath" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] WinVNC not found" -ForegroundColor Red
    Write-Host "         Install from: http://tigervnc.bphinz.com/nightly/" -ForegroundColor Gray
    $allGood = $false
}

# 2. SSH Tunnel Task
Write-Host "`n[2/5] SSH Reverse Tunnel" -ForegroundColor Yellow
$tunnelTask = Get-ScheduledTask -TaskName "SSH-Reverse-Tunnel-VNC" -ErrorAction SilentlyContinue
if ($tunnelTask) {
    Write-Host "  [OK] SSH tunnel task exists" -ForegroundColor Green
    if ($tunnelTask.State -eq "Running") {
        Write-Host "  [OK] SSH tunnel is running" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] SSH tunnel not running" -ForegroundColor Yellow
        Write-Host "         Start with: Start-ScheduledTask -TaskName 'SSH-Reverse-Tunnel-VNC'" -ForegroundColor Gray
    }
} else {
    Write-Host "  [FAIL] SSH tunnel task not found" -ForegroundColor Red
    Write-Host "         Create with: .\create-ssh-tunnel-task.ps1" -ForegroundColor Gray
    $allGood = $false
}

# 3. SSH Key
Write-Host "`n[3/5] SSH Key (RDP tunnel reused)" -ForegroundColor Yellow
$userSshKey = "$env:USERPROFILE\.ssh\id_rsa"
if (Test-Path $userSshKey) {
    Write-Host "  [OK] SSH key exists: $userSshKey" -ForegroundColor Green
    
    # Check public key exists
    $userSshPubKey = "$userSshKey.pub"
    if (Test-Path $userSshPubKey) {
        Write-Host "  [OK] Public key exists: $userSshPubKey" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Public key missing (generate with ssh-keygen)" -ForegroundColor Yellow
    }
    
    # Try to test relay connection (non-blocking)
    Write-Host "  [INFO] Testing relay connection..." -ForegroundColor Gray
    try {
        $testJob = Start-Job -ScriptBlock {
            param($key, $relay)
            & ssh -i $key -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no tunnel@$relay "echo OK" 2>$null
        } -ArgumentList $userSshKey, "172.234.175.48"
        
        $testResult = Wait-Job $testJob -Timeout 10 | Receive-Job
        Remove-Job $testJob -Force
        
        if ($testResult -match "OK") {
            Write-Host "  [OK] SSH key authorized on relay" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] Could not verify relay authorization" -ForegroundColor Yellow
            Write-Host "         This may be normal if relay is unreachable" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  [WARN] Relay test failed (connection timeout)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [FAIL] SSH key not found" -ForegroundColor Red
    Write-Host "         Generate with: ssh-keygen -t rsa -b 4096" -ForegroundColor Gray
    $allGood = $false
}

# 4. Firewall
Write-Host "`n[4/5] Windows Firewall" -ForegroundColor Yellow
$firewallRule = Get-NetFirewallRule -DisplayName "*HomeBridge*VNC*" -ErrorAction SilentlyContinue
if ($firewallRule) {
    Write-Host "  [OK] Firewall rule exists" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Firewall rule not found" -ForegroundColor Yellow
    Write-Host "         This is OK if VNC only on localhost" -ForegroundColor Gray
}

# 5. Network connectivity
Write-Host "`n[5/5] Network Connectivity" -ForegroundColor Yellow
Write-Host "  Testing relay..." -ForegroundColor Gray
$pingResult = Test-Connection -ComputerName 172.234.175.48 -Count 1 -Quiet 2>$null
if ($pingResult) {
    Write-Host "  [OK] Relay reachable (172.234.175.48)" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Relay not reachable" -ForegroundColor Yellow
    Write-Host "         Check network connection" -ForegroundColor Gray
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
if ($allGood) {
    Write-Host "All prerequisites OK - Ready to use VNC" -ForegroundColor Green
    Write-Host ""
    Write-Host "To start VNC session:" -ForegroundColor Yellow
    Write-Host "  1. Run: Start-VNC-Session.ps1" -ForegroundColor White
    Write-Host "  2. From Linux: ./vnc.sh" -ForegroundColor White
} else {
    Write-Host "Some prerequisites missing - Fix issues above" -ForegroundColor Yellow
}

Write-Host ""