Set-StrictMode -Version 2.0

. "$PSScriptRoot\libs\pyenv-lib.ps1"

function Show-UninstallHelp {
    Write-Output 'Usage: pyenv uninstall [-f|--force] <version> [<version> ...]'
    Write-Output '       pyenv uninstall [-f|--force] [-a|--all]'
    Write-Output ''
    Write-Output '   -f/--force  Attempt to remove the specified version without prompting'
    Write-Output '               for confirmation. If the version does not exist, do not'
    Write-Output '               display an error message.'
    Write-Output ''
    Write-Output '   -a/--all    *Caution* Attempt to remove all installed versions.'
    Write-Output ''
    Write-Output 'See `pyenv versions` for a complete list of installed versions.'
    Write-Output ''
    exit 0
}

function Unregister-PyenvVersion {
    param([Parameter(Mandatory = $true)][string]$Version)

    $key = "HKCU:\SOFTWARE\Python\PythonCore\$Version"
    Remove-Item -LiteralPath (Join-Path $key 'InstallPath') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $key 'InstalledFeatures') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $key 'PythonPath') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue
}

if ($args.Count -eq 0) {
    Show-UninstallHelp
}

$optForce = $false
$optAll = $false
$uninstallVersions = [ordered]@{}

foreach ($arg in $args) {
    switch ($arg) {
        '--help' { Show-UninstallHelp }
        '-f' { $optForce = $true }
        '--force' { $optForce = $true }
        '-a' { $optAll = $true }
        '--all' { $optAll = $true }
        default {
            if (-not (Test-PyenvVersion -Version $arg)) {
                Write-Output "pyenv: Unrecognized python version: $arg"
                exit 1
            }
            $uninstallVersions[$arg] = $true
        }
    }
}

if ((-not (Test-Path -LiteralPath $script:DirVers -PathType Container)) -or
    ((Get-ChildItem -LiteralPath $script:DirVers -Directory -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0)) {
    Write-Output 'pyenv: No valid versions of python installed.'
    exit 1
}

$delError = 0

if ($optAll) {
    if ($optForce) {
        $confirm = 'y'
    } else {
        $confirm = 'maybe'
        while ($confirm -ne 'n' -and $confirm -ne 'y') {
            [Console]::Write('pyenv: Confirm uninstall all? (Y/N): ')
            $line = [Console]::ReadLine()
            $confirm = $line.Trim().ToLowerInvariant()
            if ($confirm.Length -gt 0) {
                $confirm = $confirm.Substring(0, 1)
            } else {
                exit 0
            }
        }
    }
    if ($confirm -ne 'y') {
        exit 0
    }

    $uninstallVersions.Clear()
    foreach ($folder in Get-ChildItem -LiteralPath $script:DirVers -Directory) {
        if (Test-PyenvVersion -Version $folder.Name) {
            $uninstallVersions[$folder.Name] = $true
        }
    }
}

if ($uninstallVersions.Count -eq 1) {
    $folder = Resolve-32BitVersion -Version @($uninstallVersions.Keys)[0]
    if (-not (Test-Path -LiteralPath (Join-Path $script:DirVers $folder) -PathType Container)) {
        Write-Output "pyenv: version '$folder' not installed"
        exit 0
    }
}

$uninstalled = [ordered]@{}
foreach ($folderKey in $uninstallVersions.Keys) {
    $folder = Resolve-32BitVersion -Version $folderKey
    if ($uninstalled.Contains($folder)) {
        continue
    }

    $uninstallPath = Join-Path $script:DirVers $folder
    if ((Test-PyenvVersion -Version $folder) -and (Test-Path -LiteralPath $uninstallPath -PathType Container)) {
        try {
            Remove-Item -LiteralPath $uninstallPath -Recurse -Force:$optForce
            Unregister-PyenvVersion -Version $folder
            Write-Output "pyenv: Successfully uninstalled $folder"
            $uninstalled[$folder] = $true
        } catch {
            Write-Output "pyenv: Error uninstalling version $folder`: $($_.Exception.Message)"
            $delError = 1
        }
    }
}

if ($delError -eq 0) {
    Invoke-PyenvRehash
}

exit $delError
