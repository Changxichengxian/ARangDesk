Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-UnicodeEscapes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    [regex]::Replace(
        $Value,
        '\\u([0-9A-Fa-f]{4})',
        {
            param($Match)
            [string][char][Convert]::ToInt32($Match.Groups[1].Value, 16)
        }
    )
}

$scriptDir = Split-Path -Parent $PSCommandPath
$appName = 'ARangDesk'
$installDir = Join-Path $env:LOCALAPPDATA $appName
$shortcutBaseName = ConvertFrom-UnicodeEscapes '\u6574\u7406\u684C\u9762'
$launcherFileName = $shortcutBaseName + '.cmd'
$sourceLauncherPath = Join-Path $scriptDir $launcherFileName
$sourceCoreScriptPath = Join-Path $scriptDir 'organize_desktop.ps1'

if (-not (Test-Path -LiteralPath $sourceLauncherPath)) {
    throw "Cannot find launcher: $sourceLauncherPath"
}

if (-not (Test-Path -LiteralPath $sourceCoreScriptPath)) {
    throw "Cannot find core script: $sourceCoreScriptPath"
}

if (-not (Test-Path -LiteralPath $installDir)) {
    New-Item -ItemType Directory -Path $installDir | Out-Null
}

$launcherPath = Join-Path $installDir $launcherFileName
$coreScriptPath = Join-Path $installDir 'organize_desktop.ps1'

if ((Resolve-Path -LiteralPath $scriptDir).Path -ne (Resolve-Path -LiteralPath $installDir).Path) {
    Copy-Item -LiteralPath $sourceLauncherPath -Destination $launcherPath -Force
    Copy-Item -LiteralPath $sourceCoreScriptPath -Destination $coreScriptPath -Force
}

$desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
if ([string]::IsNullOrWhiteSpace($desktopPath)) {
    $shell = New-Object -ComObject WScript.Shell
    $desktopPath = $shell.SpecialFolders.Item('Desktop')
}

if ([string]::IsNullOrWhiteSpace($desktopPath)) {
    throw 'Cannot find the current user desktop folder.'
}

$shortcutPath = Join-Path $desktopPath ($shortcutBaseName + '.lnk')
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = (Resolve-Path -LiteralPath $launcherPath).Path
$shortcut.WorkingDirectory = (Resolve-Path -LiteralPath $installDir).Path
$shortcut.IconLocation = "$env:WINDIR\System32\shell32.dll,21"
$shortcut.Description = ConvertFrom-UnicodeEscapes '\u6574\u7406\u5F53\u524D\u684C\u9762\u56FE\u6807\uFF0C\u5B8C\u6210\u540E\u53EF\u6309\u7A7A\u683C\u6216 Enter \u53D6\u6D88\u672C\u6B21\u66F4\u6539\u3002'
$shortcut.Save()

Write-Host ("Installed to: " + $installDir)
Write-Host ((ConvertFrom-UnicodeEscapes '\u5DF2\u521B\u5EFA\u5FEB\u6377\u65B9\u5F0F\uFF1A') + $shortcutPath)
