Set-StrictMode -Version 2.0

. "$PSScriptRoot\libs\pyenv-lib.ps1"
. "$PSScriptRoot\libs\pyenv-install-lib.ps1"

function Show-LatestHelp {
    param([int]$ExitCode)

    Write-Output 'Usage: pyenv latest [-k|--known] [-q|--quiet] <prefix>'
    Write-Output ''
    Write-Output '  -k/--known      Select from all known versions instead of installed'
    Write-Output '  -q/--quiet      Do not print an error message on resolution failure'
    Write-Output ''
    exit $ExitCode
}

$optKnown = $false
$optQuiet = $false
$optPrefix = ''

foreach ($arg in $args) {
    switch ($arg) {
        '--help' { Show-LatestHelp -ExitCode 0 }
        '-k' { $optKnown = $true }
        '--known' { $optKnown = $true }
        '-q' { $optQuiet = $true }
        '--quiet' { $optQuiet = $true }
        default { $optPrefix = $arg }
    }
}

if ($args.Count -eq 0 -and -not $optQuiet) {
    Show-LatestHelp -ExitCode 1
}

if ($optPrefix -eq '') {
    if (-not $optQuiet) {
        Write-Output 'pyenv-latest: missing <prefix> argument'
    }
    exit 1
}

$latest = Find-LatestVersion -Prefix $optPrefix -Known:$optKnown
if ($latest -ne '') {
    Write-Output $latest
    exit 0
}

if (-not $optQuiet) {
    if ($optKnown) {
        Write-Output "pyenv-latest: no known versions match the prefix '$optPrefix'."
    } else {
        Write-Output "pyenv-latest: no installed versions match the prefix '$optPrefix'."
    }
}

exit 1
