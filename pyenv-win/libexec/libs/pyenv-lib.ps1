Set-StrictMode -Version 2.0

$script:PyenvCurrent = (Get-Location).ProviderPath
$script:PyenvHome = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:PyenvParent = Split-Path -Parent $script:PyenvHome
$script:DirCache = Join-Path $script:PyenvHome 'install_cache'
$script:DirVers = Join-Path $script:PyenvHome 'versions'
$script:DirLibs = Join-Path $script:PyenvHome 'libexec'
$script:DirShims = Join-Path $script:PyenvHome 'shims'
$script:DirWiX = Join-Path $script:PyenvHome 'bin\WiX'
$script:DBFile = Join-Path $script:PyenvHome '.versions_cache.xml'
$script:VerFile = '.python-version'

function Get-PyenvProcessArch {
    if ($env:PYENV_FORCE_ARCH) {
        return $env:PYENV_FORCE_ARCH
    }

    return $env:PROCESSOR_ARCHITECTURE
}

function Get-CurrentVersionsFromFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $versions = @()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $Path) {
            if ($line -ne '') {
                $versions += [pscustomobject]@{
                    Version = $line
                    Source = $Path
                }
            }
        }
    }

    return @($versions)
}

function Get-CurrentVersionsGlobal {
    return @(Get-CurrentVersionsFromFile -Path (Join-Path $script:PyenvHome 'version'))
}

function Get-FirstVersionGlobal {
    $versions = @(Get-CurrentVersionsGlobal)
    if ($versions.Count -eq 0) {
        return $null
    }

    return $versions[0]
}

function Get-CurrentVersionsLocal {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $currentPath = [System.IO.Path]::GetFullPath($Path)
    while ($currentPath) {
        $versionFile = Join-Path $currentPath $script:VerFile
        if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
            return @(Get-CurrentVersionsFromFile -Path $versionFile)
        }

        $parent = Split-Path -Parent $currentPath
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $currentPath) {
            break
        }

        $currentPath = $parent
    }

    return @()
}

function Get-FirstVersionLocal {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $versions = @(Get-CurrentVersionsLocal -Path $Path)
    if ($versions.Count -eq 0) {
        return $null
    }

    return $versions[0]
}

function Get-CurrentVersionsShell {
    $versions = @()
    if ($env:PYENV_VERSION) {
        foreach ($version in ($env:PYENV_VERSION -split '\s+')) {
            if ($version -ne '') {
                $versions += [pscustomobject]@{
                    Version = $version
                    Source = '%PYENV_VERSION%'
                }
            }
        }
    }

    return @($versions)
}

function Get-FirstVersionShell {
    $versions = @(Get-CurrentVersionsShell)
    if ($versions.Count -eq 0) {
        return $null
    }

    return $versions[0]
}

function Write-NoCurrentVersionError {
    Write-Output 'No global/local python version has been set yet. Please set the global/local version by typing:'
    Write-Output 'pyenv global <python-version>'
    Write-Output 'pyenv global 3.7.4'
    Write-Output 'pyenv local <python-version>'
    Write-Output 'pyenv local 3.7.4'
}

function Get-CurrentVersion {
    $version = Get-CurrentVersionNoError
    if ($null -eq $version) {
        Write-NoCurrentVersionError
        exit 1
    }

    return $version
}

function Get-CurrentVersionNoError {
    $version = Get-FirstVersionShell
    if ($null -eq $version) {
        $version = Get-FirstVersionLocal -Path $script:PyenvCurrent
    }
    if ($null -eq $version) {
        $version = Get-FirstVersionGlobal
    }

    return $version
}

function Get-CurrentVersionsNoError {
    $versions = [ordered]@{}

    $selected = @(Get-CurrentVersionsShell)
    if ($selected.Count -gt 0) {
        foreach ($version in $selected) {
            $versions[$version.Version] = $version.Source
        }

        return $versions
    }

    $selected = @(Get-CurrentVersionsLocal -Path $script:PyenvCurrent)
    if ($selected.Count -gt 0) {
        foreach ($version in $selected) {
            $versions[(Resolve-PyenvVersion -Prefix $version.Version -Known:$false)] = $version.Source
        }

        return $versions
    }

    $selected = @(Get-CurrentVersionsGlobal)
    if ($selected.Count -gt 0) {
        foreach ($version in $selected) {
            $versions[(Resolve-PyenvVersion -Prefix $version.Version -Known:$false)] = $version.Source
        }
    }

    return $versions
}

function Get-CurrentVersions {
    $versions = Get-CurrentVersionsNoError
    if ($versions.Count -eq 0) {
        Write-NoCurrentVersionError
        exit 1
    }

    return $versions
}

function Get-InstalledVersions {
    if (-not (Test-Path -LiteralPath $script:DirVers -PathType Container)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $script:DirVers -Directory | ForEach-Object { $_.Name })
}

function Test-PyenvVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Version
    )

    return $Version -match '^[a-zA-Z_0-9-.]+$'
}

function Get-BinDir {
    param(
        [Parameter(Mandatory = $true)][string]$Version
    )

    $binDir = Join-Path $script:DirVers $Version
    if (-not ((Test-PyenvVersion -Version $Version) -and (Test-Path -LiteralPath $binDir -PathType Container))) {
        Write-Output "pyenv specific python requisite didn't meet. Project is using different version of python."
        Write-Output "Install python '$Version' by typing: 'pyenv install $Version'"
        exit 1
    }

    return $binDir
}

function Get-Extensions {
    param(
        [bool]$AddPy
    )

    $extensions = ";$env:PATHEXT;"
    if ($AddPy) {
        if ($extensions -notmatch '(?i);\.PY;') {
            $extensions += '.PY;'
        }
        if ($extensions -notmatch '(?i);\.PYW;') {
            $extensions += '.PYW;'
        }
    }
    if ($extensions -notmatch '(?i);\.PS1;') {
        $extensions += '.PS1;'
    }

    while ($extensions.Contains(';;')) {
        $extensions = $extensions.Replace(';;', ';')
    }

    $result = [ordered]@{}
    foreach ($extension in $extensions.Trim(';').Split(';')) {
        if ($extension -ne '') {
            $result[$extension] = $true
        }
    }

    return $result
}

function Get-ExtensionsNoPeriod {
    param(
        [bool]$AddPy
    )

    $result = [ordered]@{}
    foreach ($extension in (Get-Extensions -AddPy:$AddPy).Keys) {
        $key = $extension
        if ($key.StartsWith('.')) {
            $key = $key.Substring(1)
        }
        $result[$key.ToLowerInvariant()] = $true
    }

    return $result
}

function New-PyenvShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$BaseName,
        [Parameter(Mandatory = $true)][string]$Target
    )

    $link = Join-Path $script:DirShims "$BaseName.lnk"
    if (Test-Path -LiteralPath $link -PathType Leaf) {
        return
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($link)
    $shortcut.TargetPath = $Target
    $shortcut.Description = $BaseName
    $shortcut.IconLocation = "$Target, 2"
    $shortcut.WindowStyle = 1
    $shortcut.WorkingDirectory = Split-Path -Parent $Target
    $shortcut.Save()
}

function Write-WinScript {
    param(
        [Parameter(Mandatory = $true)][string]$BaseName
    )

    $filePath = Join-Path $script:DirShims "$BaseName.bat"
    if (Test-Path -LiteralPath $filePath -PathType Leaf) {
        return
    }

    $lines = @(
        '@echo off',
        'chcp 1250 > NUL',
        'call pyenv exec %~n0 %*'
    )
    if ($BaseName.StartsWith('pip')) {
        $lines += 'call pyenv rehash'
    }

    Set-Content -LiteralPath $filePath -Value $lines -Encoding ASCII
}

function Write-LinuxScript {
    param(
        [Parameter(Mandatory = $true)][string]$BaseName
    )

    $filePath = Join-Path $script:DirShims $BaseName
    if (Test-Path -LiteralPath $filePath -PathType Leaf) {
        return
    }

    $lines = @(
        '#!/bin/sh',
        'pyenv exec $(basename "$0") "$@"'
    )
    if ($BaseName.StartsWith('pip')) {
        $lines += 'pyenv rehash'
    }

    Set-Content -LiteralPath $filePath -Value $lines -Encoding ASCII
}

function Invoke-RehashForFile {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)]$Extensions,
        [bool]$CreateScriptsForNonExe
    )

    $extension = $File.Extension.TrimStart('.').ToLowerInvariant()
    if (-not $Extensions.Contains($extension)) {
        return
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    if ($extension -ne 'exe') {
        New-PyenvShortcut -BaseName $baseName -Target $File.FullName
        if ($CreateScriptsForNonExe) {
            Write-WinScript -BaseName $baseName
            Write-LinuxScript -BaseName $baseName
        }
    } else {
        Write-WinScript -BaseName $baseName
        Write-LinuxScript -BaseName $baseName
    }
}

function Invoke-PyenvRehash {
    if (-not (Test-Path -LiteralPath $script:DirShims -PathType Container)) {
        New-Item -ItemType Directory -Path $script:DirShims -Force | Out-Null
    }

    Get-ChildItem -LiteralPath $script:DirShims -File -ErrorAction SilentlyContinue |
        Remove-Item -Force

    foreach ($version in Get-InstalledVersions) {
        $winBinDir = Join-Path $script:DirVers $version
        if (-not (Test-Path -LiteralPath $winBinDir -PathType Container)) {
            continue
        }

        $extensions = Get-ExtensionsNoPeriod -AddPy:$true
        Get-ChildItem -LiteralPath $winBinDir -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                Invoke-RehashForFile -File $_ -Extensions $extensions -CreateScriptsForNonExe:$true
            }

        foreach ($subDir in @('Scripts', 'bin')) {
            $path = Join-Path $winBinDir $subDir
            if (Test-Path -LiteralPath $path -PathType Container) {
                Get-ChildItem -LiteralPath $path -File -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        Invoke-RehashForFile -File $_ -Extensions $extensions -CreateScriptsForNonExe:$false
                    }
            }
        }
    }
}

function Get-ArchPostfix {
    $arch = Get-PyenvProcessArch
    if ($null -eq $arch) {
        return ''
    }

    switch ($arch.ToUpperInvariant()) {
        'AMD64' { return '' }
        'X86' { return '-win32' }
        'ARM64' { return '-arm64' }
        default { return '' }
    }
}

function Test-Is32Bit {
    $arch = Get-PyenvProcessArch
    if ($null -eq $arch) {
        return $false
    }

    return $arch.ToUpperInvariant() -eq 'X86'
}

function Resolve-32BitVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Version
    )

    if ((Test-Is32Bit) -and (-not $Version.ToLowerInvariant().EndsWith('-win32'))) {
        return "$Version-win32"
    }

    return $Version
}
