$game = 'Dungeons-WinGDK-Shipping'
$dll = 'SpicewoodLibrary.dll'
$log = "$PSScriptRoot\exit-log.csv"

$codes = @{
    '0x00000000' = 'Normal exit'
    '0x00000001' = 'TerminateProcess(1) - task manager end task or something killed it'
    '0xC0000005' = 'Access violation (crash)'
    '0xC000013A' = 'Ctrl+C / console closed'
    '0xC0000409' = 'Fail fast / stack buffer overrun'
    '0xC0000374' = 'Heap corruption'
    '0xC00000FD' = 'Stack overflow'
    '0xC000001D' = 'Illegal instruction'
    '0x80000003' = 'Breakpoint with no debugger'
    '0x40010004' = 'Killed by debugger'
}

function say($s) { Write-Host "[$(Get-Date -f HH:mm:ss)] $s" }

function dur($t) {
    if (!$t) { return 'n/a' }
    '{0:00}:{1:00}:{2:00}' -f [int]$t.TotalHours, $t.Minutes, $t.Seconds
}

if (!(Test-Path $log)) {
    'GameStarted,DllLoadedAt,GameExited,SecondsAlive,SecondsAfterDll,ExitCodeHex,Meaning' | Out-File $log -Encoding utf8
}

say "watching for $game.exe, logging to $log"

$last = $null

while (1) {
    $p = $null
    while (!$p) {
        $p = Get-Process $game -ea 0 | ? { $_.Id -ne $last -and $_.Threads.Count -gt 0 } | select -First 1
        if (!$p) { sleep -m 500 }
    }

    try { $null = $p.Handle }
    catch {
        say "cant open handle to game, run as admin ($_)"
        sleep 5
        continue
    }

    $start = $p.StartTime
    if (!$start) {
        $w = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ea 0
        if ($w.CreationDate) { $start = $w.CreationDate } else { $start = Get-Date }
    }
    say "game up, pid $($p.Id) started $($start.ToString('HH:mm:ss'))"

    $injected = $null
    $look = $true
    while (!$p.HasExited) {
        if ($look -and !$injected) {
            try {
                $p.Refresh()
                $m = @($p.Modules)
                if ($m.Count -eq 0) { throw 'no modules' }
                if ($m | ? { $_.ModuleName -eq $dll }) {
                    $injected = Get-Date
                    say "$dll loaded"
                }
            } catch {
                if (!$p.HasExited) {
                    $look = $false
                    say "cant read module list, run as admin. write down inject time yourself"
                }
            }
        }
        sleep 1
    }

    $end = Get-Date
    try { $hex = '0x{0:X8}' -f $p.ExitCode } catch { $hex = 'unknown' }

    if ($codes[$hex]) { $why = $codes[$hex] }
    elseif ($hex -match '^0x0000[0-9A-F]{4}$') { $why = 'Small code, game picked it itself (not a crash)' }
    else { $why = 'Unknown, google it + NTSTATUS' }

    $alive = $end - $start
    $after = $null
    if ($injected) { $after = $end - $injected }

    say "game closed $hex - $why"
    say "  alive $(dur $alive), after dll $(dur $after)"

    $a = ''; $b = ''
    if ($injected) { $a = $injected.ToString('s'); $b = [int]$after.TotalSeconds }
    "$($start.ToString('s')),$a,$($end.ToString('s')),$([int]$alive.TotalSeconds),$b,$hex,`"$why`"" | Out-File $log -Append -Encoding utf8

    $last = $p.Id
    $p.Dispose()

    say "waiting for next launch"
}
