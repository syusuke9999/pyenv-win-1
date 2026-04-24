Set-StrictMode -Version 2.0

. "$PSScriptRoot\libs\pyenv-lib.ps1"
. "$PSScriptRoot\libs\pyenv-install-lib.ps1"

function Get-CommandList {
    $commands = [ordered]@{}
    $extensions = Get-ExtensionsNoPeriod -AddPy:$false
    $extensions['ps1'] = $true

    foreach ($file in Get-ChildItem -LiteralPath $script:DirLibs -File) {
        if ($file.Name -match '^pyenv-([a-zA-Z_0-9-]+)\.') {
            $extension = $file.Extension.TrimStart('.').ToLowerInvariant()
            if ($extensions.Contains($extension) -and -not $commands.Contains($Matches[1])) {
                $commands[$Matches[1]] = $file.FullName
            }
        }
    }

    return $commands
}

function Invoke-BatchHelp {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [int]$ExitCode = 0
    )

    & (Join-Path $script:DirLibs "$Command.bat") --help
    exit $ExitCode
}

function Invoke-BatchVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [int]$ExitCode = 0
    )

    & (Join-Path $script:DirLibs "$Command.bat")
    exit $ExitCode
}

function Show-PyenvHelp {
    $versionFile = Join-Path $script:PyenvParent '.version'
    $version = ''
    if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
        $version = Get-Content -LiteralPath $versionFile -Raw
    }

    Write-Output "pyenv $version"
    Write-Output 'Usage: pyenv <command> [<args>]'
    Write-Output ''
    Write-Output 'Some useful pyenv commands are:'
    Write-Output '   commands     List all available pyenv commands'
    Write-Output '   duplicate    Creates a duplicate python environment'
    Write-Output '   local        Set or show the local application-specific Python version'
    Write-Output '   latest       Print the latest installed or known version with the given prefix'
    Write-Output '   global       Set or show the global Python version'
    Write-Output '   shell        Set or show the shell-specific Python version'
    Write-Output '   install      Install a Python version using python-build'
    Write-Output '   uninstall    Uninstall a specific Python version'
    Write-Output '   update       Update the cached version DB'
    Write-Output '   rehash       Rehash pyenv shims (run this after installing executables)'
    Write-Output '   vname        Show the current Python version'
    Write-Output '   version      Show the current Python version and its origin'
    Write-Output '   version-name Show the current Python version'
    Write-Output '   versions     List all Python versions available to pyenv'
    Write-Output '   exec         Runs an executable by first preparing PATH so that the selected Python'
    Write-Output '   which        Display the full path to an executable'
    Write-Output '   whence       List all Python versions that contain the given executable'
    Write-Output ''
    Write-Output "See ``pyenv help <command>' for information on a specific command."
    Write-Output 'For full documentation, see: https://github.com/pyenv-win/pyenv-win#readme'
}

function Invoke-CommandScriptVersion {
    param([string[]]$Argv)

    if ($Argv.Count -eq 1) {
        $commands = Get-CommandList
        if ($commands.Contains($Argv[0])) {
            Invoke-BatchVersion -Command 'pyenv---version' -ExitCode 0
        } else {
            Write-Output "unknown pyenv command '$($Argv[0])'"
        }
    } else {
        Show-PyenvHelp
    }
}

function Invoke-CommandRehash {
    param([string[]]$Argv)

    if ($Argv.Count -ge 2 -and $Argv[1] -eq '--help') {
        Invoke-BatchHelp -Command 'pyenv-rehash' -ExitCode 0
    }

    $versions = @(Get-InstalledVersions)
    if ($versions.Count -eq 0) {
        Write-Output "No version installed. Please install one with 'pyenv install <version>'."
    } else {
        Invoke-PyenvRehash
    }
}

function Invoke-CommandGlobal {
    param([string[]]$Argv)

    if ($Argv.Count -lt 2) {
        $currentVersions = @(Get-CurrentVersionsGlobal)
        if ($currentVersions.Count -eq 0) {
            Write-Output 'no global version configured'
        } else {
            foreach ($version in $currentVersions) {
                Write-Output $version.Version
            }
        }
        return
    }

    $versionFile = Join-Path $script:PyenvHome 'version'
    if ($Argv[1] -eq '--unset') {
        Remove-Item -LiteralPath $versionFile -Force -ErrorAction SilentlyContinue
        return
    }

    $globalVersions = @()
    for ($index = 1; $index -lt $Argv.Count; $index++) {
        $globalVersions += $Argv[$index]
        [void](Get-BinDir -Version (Resolve-PyenvVersion -Prefix $Argv[$index] -Known:$false))
    }

    Set-Content -LiteralPath $versionFile -Value $globalVersions -Encoding ASCII
}

function Invoke-CommandLocal {
    param([string[]]$Argv)

    $versionFile = Join-Path $script:PyenvCurrent $script:VerFile
    if ($Argv.Count -lt 2) {
        $currentVersions = @(Get-CurrentVersionsLocal -Path $script:PyenvCurrent)
        if ($currentVersions.Count -eq 0) {
            Write-Output 'no local version configured for this directory'
        } else {
            foreach ($version in $currentVersions) {
                Write-Output $version.Version
            }
        }
        return
    }

    if ($Argv[1] -eq '--unset') {
        Remove-Item -LiteralPath $versionFile -Force -ErrorAction SilentlyContinue
        return
    }

    $localVersions = @()
    for ($index = 1; $index -lt $Argv.Count; $index++) {
        $localVersions += $Argv[$index]
        [void](Get-BinDir -Version (Resolve-PyenvVersion -Prefix $Argv[$index] -Known:$false))
    }

    Set-Content -LiteralPath $versionFile -Value $localVersions -Encoding ASCII
}

function Invoke-CommandShell {
    param([string[]]$Argv)

    if ($Argv.Count -lt 2) {
        Write-Output 'Not enough parameters passed to pyenv.ps1 shell'
        return
    }

    if ($Argv[1] -eq '--unset') {
        return
    }

    $shellVersions = @()
    for ($index = 1; $index -lt $Argv.Count; $index++) {
        $version = Resolve-32BitVersion -Version $Argv[$index]
        [void](Get-BinDir -Version $version)
        $shellVersions += $version
    }

    Write-Output ($shellVersions -join ' ')
}

function Invoke-CommandVersion {
    if (-not (Test-Path -LiteralPath $script:DirVers -PathType Container)) {
        New-Item -ItemType Directory -Path $script:DirVers -Force | Out-Null
    }

    $versions = Get-CurrentVersions
    foreach ($version in $versions.Keys) {
        Write-Output "$version (set by $($versions[$version]))"
    }
}

function Invoke-CommandVersionName {
    if (-not (Test-Path -LiteralPath $script:DirVers -PathType Container)) {
        New-Item -ItemType Directory -Path $script:DirVers -Force | Out-Null
    }

    $versions = Get-CurrentVersions
    foreach ($version in $versions.Keys) {
        Write-Output $version
    }
}

function Invoke-CommandVersions {
    param([string[]]$Argv)

    $isBare = ($Argv.Count -ge 2 -and $Argv[1] -eq '--bare')
    if (-not (Test-Path -LiteralPath $script:DirVers -PathType Container)) {
        New-Item -ItemType Directory -Path $script:DirVers -Force | Out-Null
    }

    $currentVersions = Get-CurrentVersionsNoError
    foreach ($dir in Get-ChildItem -LiteralPath $script:DirVers -Directory) {
        $version = $dir.Name
        if ($isBare) {
            Write-Output $version
        } elseif ($currentVersions.Contains($version)) {
            Write-Output "* $version (set by $($currentVersions[$version]))"
        } else {
            Write-Output "  $version"
        }
    }
}

function Invoke-CommandCommands {
    foreach ($command in (Get-CommandList).Keys) {
        Write-Output $command
    }
}

function Invoke-CommandShims {
    param([string[]]$Argv)

    if ($Argv.Count -lt 2) {
        Get-ChildItem -LiteralPath $script:DirShims -Recurse -File -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName }
    } elseif ($Argv[1] -eq '--short') {
        Get-ChildItem -LiteralPath $script:DirShims -File -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name }
    } else {
        Invoke-BatchHelp -Command 'pyenv-shims' -ExitCode 0
    }
}

function Find-PyenvExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$Program
    )

    $versionDir = Join-Path $script:DirVers $Version
    if (Test-Path -LiteralPath (Join-Path $versionDir $Program) -PathType Leaf) {
        return (Get-Item -LiteralPath (Join-Path $versionDir $Program)).FullName
    }

    foreach ($extension in (Get-Extensions -AddPy:$true).Keys) {
        $candidate = Join-Path $versionDir "$Program$extension"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Get-Item -LiteralPath $candidate).FullName
        }
    }

    foreach ($subDir in @('Scripts', 'bin')) {
        $path = Join-Path $versionDir $subDir
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            continue
        }

        if (Test-Path -LiteralPath (Join-Path $path $Program) -PathType Leaf) {
            return (Get-Item -LiteralPath (Join-Path $path $Program)).FullName
        }

        foreach ($extension in (Get-Extensions -AddPy:$true).Keys) {
            $candidate = Join-Path $path "$Program$extension"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Get-Item -LiteralPath $candidate).FullName
            }
        }
    }

    return $null
}

function Find-WhenceMatches {
    param(
        [Parameter(Mandatory = $true)][string]$Program,
        [bool]$Path
    )

    $results = @()
    if (-not (Test-Path -LiteralPath $script:DirVers -PathType Container)) {
        return @()
    }

    $extensions = Get-Extensions -AddPy:$true
    foreach ($dir in Get-ChildItem -LiteralPath $script:DirVers -Directory) {
        $found = $false

        $candidate = Join-Path $dir.FullName $Program
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $found = $true
            if ($Path) {
                $results += (Get-Item -LiteralPath $candidate).FullName
            } else {
                $results += $dir.Name
            }
        }

        if ((-not $found) -or $Path) {
            foreach ($extension in $extensions.Keys) {
                $candidate = Join-Path $dir.FullName "$Program$extension"
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    $found = $true
                    if ($Path) {
                        $results += (Get-Item -LiteralPath $candidate).FullName
                    } else {
                        $results += $dir.Name
                    }
                    break
                }
            }
        }

        foreach ($subDir in @('Scripts', 'bin')) {
            $subPath = Join-Path $dir.FullName $subDir
            if (((-not $found) -or $Path) -and (Test-Path -LiteralPath $subPath -PathType Container)) {
                $candidate = Join-Path $subPath $Program
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    $found = $true
                    if ($Path) {
                        $results += (Get-Item -LiteralPath $candidate).FullName
                    } else {
                        $results += $dir.Name
                    }
                }
            }

            if (((-not $found) -or $Path) -and (Test-Path -LiteralPath $subPath -PathType Container)) {
                foreach ($extension in $extensions.Keys) {
                    $candidate = Join-Path $subPath "$Program$extension"
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                        if ($Path) {
                            $results += (Get-Item -LiteralPath $candidate).FullName
                        } else {
                            $results += $dir.Name
                        }
                        break
                    }
                }
            }
        }
    }

    return @($results)
}

function Invoke-CommandWhich {
    param([string[]]$Argv)

    if ($Argv.Count -lt 2 -or $Argv[1] -eq '') {
        Invoke-BatchHelp -Command 'pyenv-which' -ExitCode 1
    }

    $program = $Argv[1]
    if ($program.EndsWith('.')) {
        $program = $program.Substring(0, $program.Length - 1)
    }

    $versions = Get-CurrentVersions
    foreach ($version in $versions.Keys) {
        $versionDir = Join-Path $script:DirVers $version
        if (-not (Test-Path -LiteralPath $versionDir -PathType Container)) {
            Write-Output "pyenv: version '$version' is not installed (set by $version)"
            exit 1
        }

        $found = Find-PyenvExecutable -Version $version -Program $program
        if ($null -ne $found) {
            Write-Output $found
            exit 0
        }
    }

    Write-Output "pyenv: $($Argv[1]): command not found"

    $matches = @(Find-WhenceMatches -Program $program -Path:$false)
    if ($matches.Count -gt 0) {
        Write-Output ''
        Write-Output "The '$($Argv[1])' command exists in these Python versions:"
        Write-Output "  $($matches -join "`r`n  ")"
        Write-Output '  '
    }

    exit 127
}

function Invoke-CommandWhence {
    param([string[]]$Argv)

    if ($Argv.Count -lt 2 -or $Argv[1] -eq '') {
        Invoke-BatchHelp -Command 'pyenv-whence' -ExitCode 1
    }

    $isPath = $false
    if ($Argv[1] -eq '--path') {
        if ($Argv.Count -lt 3) {
            Invoke-BatchHelp -Command 'pyenv-whence' -ExitCode 1
        }
        $isPath = $true
        $program = $Argv[2]
    } else {
        $program = $Argv[1]
    }

    if ($program -eq '') {
        Invoke-BatchHelp -Command 'pyenv-whence' -ExitCode 1
    }
    if ($program.EndsWith('.')) {
        $program = $program.Substring(0, $program.Length - 1)
    }

    $matches = @(Find-WhenceMatches -Program $program -Path:$isPath)
    foreach ($match in $matches) {
        Write-Output $match
    }

    if ($matches.Count -gt 0) {
        exit 0
    }

    exit 1
}

function Invoke-PyenvMain {
    param([string[]]$Argv)

    if ($Argv.Count -eq 0) {
        Show-PyenvHelp
        return
    }

    switch ($Argv[0]) {
        '--version' { Invoke-CommandScriptVersion -Argv $Argv }
        'rehash' { Invoke-CommandRehash -Argv $Argv }
        'global' { Invoke-CommandGlobal -Argv $Argv }
        'local' { Invoke-CommandLocal -Argv $Argv }
        'shell' { Invoke-CommandShell -Argv $Argv }
        'version' { Invoke-CommandVersion }
        'vname' { Invoke-CommandVersionName }
        'version-name' { Invoke-CommandVersionName }
        'versions' { Invoke-CommandVersions -Argv $Argv }
        'commands' { Invoke-CommandCommands }
        'shims' { Invoke-CommandShims -Argv $Argv }
        'which' { Invoke-CommandWhich -Argv $Argv }
        'whence' { Invoke-CommandWhence -Argv $Argv }
        'help' { Show-PyenvHelp }
        '--help' { Show-PyenvHelp }
    }
}

Invoke-PyenvMain -Argv $args
