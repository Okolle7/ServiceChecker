$Host.UI.RawUI.WindowTitle = "ErrorX ServiceCheck"

$services = "SysMain", "PcaSvc", "DPS", "EventLog", "Schedule", "WSearch", "DusmSvc", "Appinfo", "DiagTrack"
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$uptime = [int]((Get-Date) - $boot).TotalHours

$procStart = @{}
Get-CimInstance Win32_Process | ForEach-Object { $procStart[[int]$_.ProcessId] = $_.CreationDate }
$installed = @{}
Get-CimInstance Win32_Service | ForEach-Object { $installed[$_.Name] = $_ }

$row = "  {0,-10} {1,-9} {2,-16} {3,-17} {4,-11} {5}"

Write-Host ""
Write-Host "  boot $($boot.ToString('dd.MM.yyyy HH:mm:ss')), uptime ${uptime}h" -ForegroundColor Cyan
Write-Host ""
Write-Host ($row -f "service", "state", "start", "started", "after boot", "") -ForegroundColor DarkGray

foreach ($name in $services) {
    $svc = $installed[$name]
    if (-not $svc) {
        Write-Host ("  {0,-10} missing" -f $name) -ForegroundColor Red
        continue
    }

    $mode = $svc.StartMode
    if ($svc.DelayedAutoStart) { $mode += " (delayed)" }

    $started = $null
    if ($svc.ProcessId) { $started = $procStart[[int]$svc.ProcessId] }
    $startText = "-"
    $delayText = "-"
    if ($started) {
        $delay = $started - $boot
        $startText = $started.ToString("dd.MM. HH:mm:ss")
        $delayText = "+{0}:{1:00}:{2:00}" -f [int][math]::Floor($delay.TotalHours), $delay.Minutes, $delay.Seconds
    }

    $limit = if ($svc.DelayedAutoStart) { 10 } else { 3 }
    if ($svc.State -ne "Running") {
        $verdict, $color = "NOT RUNNING", "Red"
        if ($svc.StartMode -eq "Manual") { $verdict, $color = "stopped (manual)", "Yellow" }
    } elseif ($svc.StartMode -eq "Manual") {
        $verdict, $color = "manual", "Gray"
    } elseif ($started -and $delay.TotalMinutes -gt $limit) {
        $verdict, $color = "LATE START", "Red"
    } else {
        $verdict, $color = "OK", "Green"
    }
    if ($svc.StartMode -eq "Disabled") { $verdict += ", DISABLED"; $color = "Red" }

    Write-Host ($row -f $name, $svc.State, $mode, $startText, $delayText, $verdict) -ForegroundColor $color
}

Write-Host ""
foreach ($name in "bam", "dam") {
    $drv = Get-CimInstance Win32_SystemDriver -Filter "Name='$name'"
    if (-not $drv) {
        Write-Host ("  {0,-10} missing" -f $name) -ForegroundColor Red
        continue
    }
    $ok = $drv.State -eq "Running" -and $drv.StartMode -ne "Disabled"
    $color = if ($ok) { "Green" } else { "Red" }
    $verdict = if ($ok) { "OK" } else { "BAD" }
    Write-Host ($row -f $name, $drv.State, $drv.StartMode, "driver", "-", $verdict) -ForegroundColor $color
}

Write-Host ""
Write-Host "  start type changes (7040)" -ForegroundColor Cyan
$filter = @{ LogName = "System"; ProviderName = "Service Control Manager"; Id = 7040; StartTime = $boot }
$changes = Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue | Where-Object { $services -contains $_.Properties[3].Value }
if (-not $changes) { Write-Host "  none" -ForegroundColor Green }
foreach ($ev in $changes) {
    $p = $ev.Properties
    Write-Host ("  {0}  {1,-10} {2} -> {3}" -f $ev.TimeCreated.ToString("dd.MM. HH:mm:ss"), $p[3].Value, $p[1].Value, $p[2].Value) -ForegroundColor Red
}
Write-Host ""
