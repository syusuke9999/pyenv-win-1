Set-StrictMode -Version 2.0

. "$PSScriptRoot\libs\pyenv-lib.ps1"
. "$PSScriptRoot\libs\pyenv-install-lib.ps1"

foreach ($mirror in $script:Mirrors) {
    Write-Output ":: [Info] ::  Mirror: $mirror"
}

function Show-InstallHelp {
    Write-Output 'Usage: pyenv install [-s] [-f] <version> [<version> ...] [-r|--register]'
    Write-Output '       pyenv install [-f] [--32only|--64only] -a|--all'
    Write-Output '       pyenv install [-f] -c|--clear'
    Write-Output '       pyenv install -l|--list'
    Write-Output ''
    Write-Output '  -l/--list              List all available versions'
    Write-Output '  -a/--all               Installs all known version from the local version DB cache'
    Write-Output '  -c/--clear             Removes downloaded installers from the cache to free space'
    Write-Output '  -f/--force             Install even if the version appears to be installed already'
    Write-Output '  -s/--skip-existing     Skip the installation if the version appears to be installed already'
    Write-Output '  -r/--register          Register version for py launcher'
    Write-Output '  -q/--quiet             Install using /quiet. This does not show the UI nor does it prompt for inputs'
    Write-Output '  --32only               Installs only 32bit Python using -a/--all switch, no effect on 32-bit windows.'
    Write-Output '  --64only               Installs only 64bit Python using -a/--all switch, no effect on 32-bit windows.'
    Write-Output '  --dev                  Installs precompiled standard libraries, debug symbols, and debug binaries (only applies to web installer).'
    Write-Output '  --help                 Help, list of options allowed on pyenv install'
    Write-Output ''
    exit 0
}

function Ensure-Folder {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Download-Installer {
    param([Parameter(Mandatory = $true)]$Params)

    Write-Output ":: [Downloading] ::  $($Params[$script:LV_Code]) ..."
    Write-Output ":: [Downloading] ::  From $($Params[$script:LV_URL])"
    Write-Output ":: [Downloading] ::  To   $($Params[$script:IP_InstallFile])"
    Save-DownloadedFile -Url $Params[$script:LV_URL] -File $Params[$script:IP_InstallFile]
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    & $FilePath @Arguments | Out-Null
    if ($null -eq $global:LASTEXITCODE) {
        return 0
    }

    return $global:LASTEXITCODE
}

function Test-InstalledVersion {
    param(
        [Parameter(Mandatory = $true)]$Params
    )

    $installPath = $Params[$script:IP_InstallPath]
    if (-not (Test-Path -LiteralPath $installPath -PathType Container)) {
        return $false
    }

    if ($Params[$script:LV_Code] -match '^\d+(?:\.\d+)+') {
        return (Test-Path -LiteralPath (Join-Path $installPath 'python.exe') -PathType Leaf)
    }

    return ((Get-ChildItem -LiteralPath $installPath -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
}

function Invoke-DeepExtract {
    param(
        [Parameter(Mandatory = $true)]$Params,
        [bool]$Web
    )

    $cachePath = Join-Path $script:DirCache $Params[$script:LV_Code]
    if ($Web) {
        $cachePath = "$cachePath-webinstall"
    }
    $installPath = $Params[$script:IP_InstallPath]
    $exitCode = -1

    if ((Test-Path -LiteralPath $cachePath -PathType Container) -and
        ((Get-ChildItem -LiteralPath $cachePath -Filter '*.msi' -File -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0)) {
        Remove-Item -LiteralPath $cachePath -Recurse -Force
    }

    if (-not (Test-Path -LiteralPath $cachePath -PathType Container)) {
        if ($Web) {
            $exitCode = Invoke-NativeCommand -FilePath $Params[$script:IP_InstallFile] -Arguments @('/quiet', '/layout', $cachePath)
            if ($exitCode -ne 0) {
                Write-Output ':: [Error] :: error extracting the web portion from the installer.'
                return $exitCode
            }
        } else {
            $dark = Join-Path $script:DirWiX 'dark.exe'
            $exitCode = Invoke-NativeCommand -FilePath $dark -Arguments @('-x', $cachePath, $Params[$script:IP_InstallFile])
            if ($exitCode -ne 0) {
                Write-Output ':: [Error] :: error extracting the embedded portion from the installer.'
                return $exitCode
            }

            try {
                Move-Item -Path (Join-Path $cachePath 'AttachedContainer\*.msi') -Destination $cachePath -Force
                $exitCode = 0
            } catch {
                Write-Output ':: [Error] :: error extracting the embedded portion from the installer.'
                return 1
            }
        }
    }

    foreach ($file in Get-ChildItem -LiteralPath $cachePath -File) {
        $baseName = $file.BaseName.ToLowerInvariant()
        if (($file.Extension.ToLowerInvariant() -ne '.msi') -or @('appendpath', 'launcher', 'path', 'pip').Contains($baseName)) {
            Remove-Item -LiteralPath $file.FullName -Force
        }
    }

    Get-ChildItem -LiteralPath $cachePath -Directory -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force

    $componentFiles = @(Get-ChildItem -LiteralPath $cachePath -Filter '*.msi' -File -ErrorAction SilentlyContinue)
    if ($componentFiles.Count -eq 0) {
        Write-Output ':: [Error] :: no component MSI files were found in the extracted installer.'
        return 1
    }

    foreach ($file in $componentFiles) {
        $baseName = $file.BaseName.ToLowerInvariant()
        $exitCode = Invoke-NativeCommand -FilePath 'msiexec' -Arguments @('/quiet', '/a', $file.FullName, "TargetDir=$installPath")
        if ($exitCode -ne 0) {
            Write-Output ":: [Error] :: error installing ""$baseName"" component MSI."
            return $exitCode
        }

        $msi = Join-Path $installPath $file.Name
        if (Test-Path -LiteralPath $msi -PathType Leaf) {
            Remove-Item -LiteralPath $msi -Force
        }
    }

    $ensurePip = Join-Path $installPath 'Lib\ensurepip'
    if (Test-Path -LiteralPath $ensurePip -PathType Container) {
        $python = Join-Path $installPath 'python.exe'
        $exitCode = Invoke-NativeCommand -FilePath $python -Arguments @('-E', '-s', '-m', 'ensurepip', '-U', '--default-pip')
        if ($exitCode -ne 0) {
            Write-Output ':: [Error] :: error installing pip.'
            return $exitCode
        }
    }

    $version = $Params[$script:LV_Code]
    $pythonExe = Join-Path $installPath 'python.exe'
    $pythonwExe = Join-Path $installPath 'pythonw.exe'
    if ((Test-Path -LiteralPath $pythonExe -PathType Leaf) -and (Test-Path -LiteralPath $pythonwExe -PathType Leaf) -and ($version -match '^(\d+)\.(\d+)')) {
        $major = $Matches[1]
        $minor = $Matches[2]
        $majorMinor = "$major$minor"
        $majorDotMinor = "$major.$minor"

        foreach ($suffix in @($major, $majorMinor, $majorDotMinor)) {
            Copy-Item -LiteralPath $pythonExe -Destination (Join-Path $installPath "python$suffix.exe") -Force
            Copy-Item -LiteralPath $pythonwExe -Destination (Join-Path $installPath "pythonw$suffix.exe") -Force
        }

        $venvLauncherExe = Join-Path $installPath 'Lib\venv\scripts\nt\python.exe'
        if (Test-Path -LiteralPath $venvLauncherExe -PathType Leaf) {
            foreach ($suffix in @($major, $majorMinor, $majorDotMinor)) {
                Copy-Item -LiteralPath $venvLauncherExe -Destination (Join-Path (Split-Path -Parent $venvLauncherExe) "python$suffix.exe") -Force
                Copy-Item -LiteralPath $venvLauncherExe -Destination (Join-Path (Split-Path -Parent $venvLauncherExe) "pythonw$suffix.exe") -Force
            }
        }
    }

    if (-not (Test-InstalledVersion -Params $Params)) {
        Write-Output ":: [Error] :: installer completed but '$installPath' was not created correctly."
        return 1
    }

    return 0
}

function Expand-PyenvZip {
    param(
        [Parameter(Mandatory = $true)][string]$InstallFile,
        [Parameter(Mandatory = $true)][string]$InstallPath,
        [string]$ZipRootDir
    )

    if (Test-Path -LiteralPath $InstallPath -PathType Container) {
        return 1
    }

    try {
        if ($ZipRootDir -eq '') {
            Ensure-Folder -Path $InstallPath
            Expand-Archive -LiteralPath $InstallFile -DestinationPath $InstallPath -Force
        } else {
            $parentDir = Split-Path -Parent $InstallPath
            Ensure-Folder -Path $parentDir
            Expand-Archive -LiteralPath $InstallFile -DestinationPath $parentDir -Force
            Move-Item -LiteralPath (Join-Path $parentDir $ZipRootDir) -Destination $InstallPath -Force
        }
    } catch {
        return 1
    }

    return 0
}

function Register-PyenvVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$InstallPath
    )

    if ((Get-PyenvProcessArch).ToLowerInvariant() -eq 'x86') {
        Write-Output 'Python registration not supported in 32 bits'
        return
    }

    if ($Version.Contains('pypy')) {
        Write-Output 'Registering pypy versions is not supported yet'
        return
    }

    $python = Join-Path $InstallPath 'python.exe'
    $fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($python).FileVersion
    $parts = $fileVersion.Split('.')
    $sysVersion = "$($parts[0]).$($parts[1])"
    $featureVersion = "$($parts[0]).$($parts[1]).$($parts[2]).0"

    $key = "HKCU:\SOFTWARE\Python\PythonCore\$Version"
    New-Item -Path $key -Force | Out-Null
    New-ItemProperty -Path $key -Name 'DiplayName' -Value "Python $sysVersion (64-bit)" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name 'SupportUrl' -Value 'https://github.com/pyenv-win/pyenv-win/issues' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name 'SysArchitecture' -Value '64bit' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name 'SysVersion' -Value $sysVersion -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name 'Version' -Value $Version -PropertyType String -Force | Out-Null

    $featuresKey = Join-Path $key 'InstalledFeatures'
    New-Item -Path $featuresKey -Force | Out-Null
    foreach ($feature in @('dev', 'exe', 'lib', 'pip', 'tools')) {
        New-ItemProperty -Path $featuresKey -Name $feature -Value $featureVersion -PropertyType String -Force | Out-Null
    }

    $installKey = Join-Path $key 'InstallPath'
    New-Item -Path $installKey -Force | Out-Null
    Set-ItemProperty -Path $installKey -Name '(default)' -Value "$InstallPath\"
    New-ItemProperty -Path $installKey -Name 'ExecutablePath' -Value (Join-Path $InstallPath 'python.exe') -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $installKey -Name 'WindowedExecutablePath' -Value (Join-Path $InstallPath 'pythonw.exe') -PropertyType String -Force | Out-Null

    $pythonPathKey = Join-Path $key 'PythonPath'
    New-Item -Path $pythonPathKey -Force | Out-Null
    Set-ItemProperty -Path $pythonPathKey -Name '(default)' -Value "$InstallPath\Lib\;$InstallPath\DLLs\"
}

function Install-Version {
    param(
        [Parameter(Mandatory = $true)]$Params,
        [bool]$Register
    )

    $installFile = $Params[$script:IP_InstallFile]
    $installFileFolder = Split-Path -Parent $installFile
    $installPath = $Params[$script:IP_InstallPath]
    $zipRootDir = $Params[$script:LV_ZipRootDir]

    Ensure-Folder -Path $installFileFolder
    Ensure-Folder -Path (Split-Path -Parent $installPath)

    if (Test-InstalledVersion -Params $Params) {
        return
    }

    if (-not (Test-Path -LiteralPath $installFile -PathType Leaf)) {
        Download-Installer -Params $Params
    }

    Write-Output ":: [Installing] ::  $($Params[$script:LV_Code]) ..."
    Push-Location $installFileFolder
    try {
        if ($Params[$script:LV_MSI]) {
            $exitCode = Invoke-NativeCommand -FilePath 'msiexec' -Arguments @('/quiet', '/a', $installFile, "TargetDir=$installPath")
            if ($exitCode -eq 0) {
                Get-ChildItem -LiteralPath $installPath -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension.ToLowerInvariant() -eq '.msi' } |
                    Remove-Item -Force

                $ensurePip = Join-Path $installPath 'Lib\ensurepip'
                if (Test-Path -LiteralPath $ensurePip -PathType Container) {
                    $python = Join-Path $installPath 'python.exe'
                    $exitCode = Invoke-NativeCommand -FilePath $python -Arguments @('-E', '-s', '-m', 'ensurepip', '-U', '--default-pip')
                    if ($exitCode -ne 0) {
                        Write-Output ':: [Error] :: error installing pip.'
                    }
                }
            }
        } elseif ($Params[$script:LV_Web]) {
            $exitCode = Invoke-DeepExtract -Params $Params -Web:$true
        } elseif ([System.IO.Path]::GetExtension($installFile).TrimStart('.').ToLowerInvariant() -eq 'zip') {
            $exitCode = Expand-PyenvZip -InstallFile $installFile -InstallPath $installPath -ZipRootDir $zipRootDir
        } else {
            $exitCode = Invoke-DeepExtract -Params $Params -Web:$false
        }
    } finally {
        Pop-Location
    }

    if (($exitCode -eq 0) -and (Test-InstalledVersion -Params $Params)) {
        Write-Output ":: [Info] :: completed! $($Params[$script:LV_Code])"
        if ($Register) {
            Register-PyenvVersion -Version $Params[$script:LV_Code] -InstallPath $installPath
        }
    } else {
        Write-Output ":: [Error] :: couldn't install $($Params[$script:LV_Code])"
    }
}

$optForce = $false
$optSkip = $false
$optList = $false
$optQuiet = $false
$optAll = $false
$opt32 = $false
$opt64 = $false
$optDev = $false
$optReg = $false
$optClear = $false
$installVersions = [ordered]@{}

foreach ($arg in $args) {
    switch ($arg) {
        '--help' { Show-InstallHelp }
        '-l' { $optList = $true }
        '--list' { $optList = $true }
        '-f' { $optForce = $true }
        '--force' { $optForce = $true }
        '-s' { $optSkip = $true }
        '--skip-existing' { $optSkip = $true }
        '-q' { $optQuiet = $true }
        '--quiet' { $optQuiet = $true }
        '-a' { $optAll = $true }
        '--all' { $optAll = $true }
        '-c' { $optClear = $true }
        '--clear' { $optClear = $true }
        '--32only' { $opt32 = $true }
        '--64only' { $opt64 = $true }
        '--dev' { $optDev = $true }
        '-r' { $optReg = $true }
        '--register' { $optReg = $true }
        default { $installVersions[(Resolve-PyenvVersion -Prefix $arg -Known:$true)] = $true }
    }
}

if (Test-Is32Bit) {
    $opt32 = $false
    $opt64 = $false
}
if ($opt32 -and $opt64) {
    Write-Output 'pyenv-install: only --32only or --64only may be specified, not both.'
    exit 1
}
if ($optReg) {
    if ($opt32) {
        Write-Output 'pyenv-install: --register not supported for 32 bits.'
        exit 1
    }
    if ($optAll) {
        Write-Output 'pyenv-install: --register not supported for all versions.'
        exit 1
    }
}

$versions = Load-VersionsXml -XmlPath $script:DBFile
if ($versions.Count -eq 0) {
    Write-Output 'pyenv-install: no definitions in local database'
    Write-Output ''
    Write-Output 'Please update the local database cache with `pyenv update''.'
    exit 1
}

if ($optList) {
    foreach ($version in $versions.Keys) {
        Write-Output $version
    }
    exit 0
} elseif ($optClear) {
    $delError = 0
    if (Test-Path -LiteralPath $script:DirCache -PathType Container) {
        foreach ($objCache in Get-ChildItem -LiteralPath $script:DirCache -Force) {
            try {
                Remove-Item -LiteralPath $objCache.FullName -Recurse -Force:$optForce
            } catch {
                $kind = if ($objCache.PSIsContainer) { 'folder' } else { 'file' }
                Write-Output "pyenv: Error deleting $kind $($objCache.Name): $($_.Exception.Message)"
                $delError = 1
            }
        }
    }
    exit $delError
}

if ($optAll) {
    $installVersions.Clear()
    foreach ($version in $versions.Keys) {
        $checkedVersion = Resolve-32BitVersion -Version $version
        if ($versions.Contains($checkedVersion)) {
            if ($opt64) {
                if ($versions[$checkedVersion][$script:LV_x64]) {
                    $installVersions[$checkedVersion] = $true
                }
            } elseif ($opt32) {
                if (-not $versions[$checkedVersion][$script:LV_x64]) {
                    $installVersions[$checkedVersion] = $true
                }
            } else {
                $installVersions[$checkedVersion] = $true
            }
        }
    }
} elseif ($installVersions.Count -eq 0) {
    $currentVersion = Get-CurrentVersionNoError
    if ($null -ne $currentVersion) {
        $installVersions[(Resolve-PyenvVersion -Prefix $currentVersion.Version -Known:$true)] = $true
    } else {
        Show-InstallHelp
    }
}

foreach ($version in $installVersions.Keys) {
    if (-not $versions.Contains($version)) {
        Write-Output "pyenv-install: definition not found: $version"
        Write-Output ''
        Write-Output 'See all available versions with `pyenv install --list`.'
        Write-Output 'Does the list seem out of date? Update it using `pyenv update`.'
        exit 1
    }
}

$installed = [ordered]@{}
foreach ($version in $installVersions.Keys) {
    if ($installed.Contains($version)) {
        continue
    }

    $verDef = $versions[$version]
    $installParams = @(
        $verDef[$script:LV_Code],
        $verDef[$script:LV_FileName],
        $verDef[$script:LV_URL],
        $verDef[$script:LV_x64],
        $verDef[$script:LV_Web],
        $verDef[$script:LV_MSI],
        $verDef[$script:LV_ZipRootDir],
        (Join-Path $script:DirVers $verDef[$script:LV_Code]),
        (Join-Path $script:DirCache $verDef[$script:LV_FileName]),
        $optQuiet,
        $optDev
    )
    if ($optForce) {
        Clear-InstallArtifacts -Params $installParams
    }
    Install-Version -Params $installParams -Register:$optReg
    $installed[$version] = $true
}

Invoke-PyenvRehash
