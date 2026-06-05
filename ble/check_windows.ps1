<#
check_windows.ps1 — can THIS Windows machine run the BLE booth tooling?

Run in PowerShell (no admin needed):
    powershell -ExecutionPolicy Bypass -File ble\check_windows.ps1

Prints PASS/WARN/FAIL for: Windows version, Bluetooth radio, BLE central-role
support, Python, and bleak. The definitive test is still `python ble\scan.py`.
#>

function Say($status, $msg) {
    $color = @{ PASS = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; INFO = 'Cyan' }[$status]
    Write-Host ("[{0}] {1}" -f $status, $msg) -ForegroundColor $color
}

Write-Host "`n=== Windows BLE capability check ===`n"

# 1. Windows version (need build >= 16299 for WinRT BLE)
$v = [Environment]::OSVersion.Version
$name = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName
if ($v.Build -ge 16299) { Say PASS "Windows: $name (build $($v.Build)) - OK for BLE" }
else { Say FAIL "Windows build $($v.Build) too old; need >= 16299 (Win10 1709)" }

# 2. Bluetooth radio present?
$bt = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
      Where-Object { $_.FriendlyName -and $_.FriendlyName -notlike '*Enumerator*' }
if ($bt) {
    foreach ($d in $bt) { Say INFO "Bluetooth device: $($d.FriendlyName) [$($d.Status)]" }
    $okRadio = $bt | Where-Object Status -eq 'OK'
    if ($okRadio) { Say PASS "Bluetooth radio present and OK" }
    else { Say WARN "Bluetooth device found but not in 'OK' state - check drivers / turn BT on" }
} else {
    Say FAIL "No Bluetooth radio found. Need a built-in adapter or a USB BT 4.0+ dongle."
}

# 3. BLE central-role support (best-effort property read)
try {
    $radio = ($bt | Where-Object Status -eq 'OK' | Select-Object -First 1)
    if ($radio) {
        $props = Get-PnpDeviceProperty -InstanceId $radio.InstanceId -ErrorAction SilentlyContinue
        $le = $props | Where-Object { $_.KeyName -match 'LowEnergy' -or $_.KeyName -match 'CentralRole' }
        if ($le) { Say PASS "Reports Low Energy / central-role support" }
        else { Say WARN "Could not confirm LE central role via PnP - the scan test below is definitive" }
    }
} catch { Say WARN "LE property read skipped - the scan test below is definitive" }

# 4. Python
$py = (Get-Command python -ErrorAction SilentlyContinue)
if ($py) { Say PASS "Python: $(python --version 2>&1)" }
else { Say FAIL "Python not on PATH. Install 3.12 from python.org (check 'Add to PATH')." }

# 5. bleak
if ($py) {
    $hasBleak = (python -c "import importlib.metadata as m; print(m.version('bleak'))" 2>$null)
    if ($hasBleak) { Say PASS "bleak installed: $hasBleak" }
    else { Say WARN "bleak not installed. Run: pip install bleak" }
}

Write-Host "`n=== Verdict ==="
Write-Host "If Windows + Bluetooth radio + Python all PASS, this box can run it."
Write-Host "Definitive proof: power the booth, then run:  python ble\scan.py 15"
Write-Host "Seeing '360 Controller-8132' in that list = you're good to go.`n"
