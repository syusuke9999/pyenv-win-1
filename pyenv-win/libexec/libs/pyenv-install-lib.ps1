Set-StrictMode -Version 2.0

$script:Mirrors = @($env:PYTHON_BUILD_MIRROR_URL)
if ([string]::IsNullOrEmpty($script:Mirrors[0])) {
    $script:Mirrors = @(
        'https://www.python.org/ftp/python',
        'https://downloads.python.org/pypy/versions.json',
        'https://api.github.com/repos/oracle/graalpython/releases'
    )
}

$script:SFV_FileName = 0
$script:SFV_URL = 1
$script:SFV_Version = 2

$script:VRX_Major = 0
$script:VRX_Minor = 1
$script:VRX_Patch = 2
$script:VRX_Release = 3
$script:VRX_RelNumber = 4
$script:VRX_x64 = 5
$script:VRX_ARM = 6
$script:VRX_Web = 7
$script:VRX_Ext = 8
$script:VRX_Arch = 5
$script:VRX_ZipRoot = 9

$script:LV_Code = 0
$script:LV_FileName = 1
$script:LV_URL = 2
$script:LV_x64 = 3
$script:LV_Web = 4
$script:LV_MSI = 5
$script:LV_ZipRootDir = 6

$script:IP_InstallPath = 7
$script:IP_InstallFile = 8
$script:IP_Quiet = 9
$script:IP_Dev = 10

$script:RegexVer = [regex]'^(?<major>\d+)(?:\.(?<minor>\d+))?(?:\.(?<patch>\d+))?(?:(?<release>[a-z]+)(?<relnum>\d*))?$'
$script:RegexVerArch = [regex]'^(?<major>\d+)(?:\.(?<minor>\d+))?(?:\.(?<patch>\d+))?(?:(?<release>[a-z]+)(?<relnum>\d*))?(?<arch>[\.-](?:amd64|arm64|win32))?$'
$script:RegexFile = [regex]'(?i)^python-(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:([a-z]+)(\d*))?([\.-]amd64)?([\.-]arm64)?(-webinstall)?\.(exe|msi)$'
$script:RegexJsonUrl = [regex]'(?i)download_url": ?"(https://[^\s"]+/(((?:pypy\d+\.\d+-v|graalpy-)(\d+)(?:\.(\d+))?(?:\.(\d+))?-(win64|windows-amd64)?(windows-aarch64)?).zip))"'

function Get-RegexSubMatches {
    param(
        [Parameter(Mandatory = $true)][System.Text.RegularExpressions.Match]$Match
    )

    $pieces = @()
    for ($index = 1; $index -lt $Match.Groups.Count; $index++) {
        $pieces += $Match.Groups[$index].Value
    }

    return ,$pieces
}

function Join-Win32String {
    param(
        [Parameter(Mandatory = $true)]$Pieces
    )

    $result = ''
    if ($Pieces[$script:VRX_Major]) { $result += $Pieces[$script:VRX_Major] }
    if ($Pieces[$script:VRX_Minor]) { $result += ".$($Pieces[$script:VRX_Minor])" }
    if ($Pieces[$script:VRX_Patch]) { $result += ".$($Pieces[$script:VRX_Patch])" }
    if ($Pieces[$script:VRX_Release]) { $result += $Pieces[$script:VRX_Release] }
    if ($Pieces[$script:VRX_RelNumber]) { $result += $Pieces[$script:VRX_RelNumber] }
    if ($Pieces[$script:VRX_ARM]) {
        $result += '-arm'
    } elseif (-not $Pieces[$script:VRX_x64]) {
        $result += '-win32'
    }

    return $result
}

function Join-InstallString {
    param(
        [Parameter(Mandatory = $true)]$Pieces
    )

    $result = ''
    if ($Pieces[$script:VRX_Major]) { $result += $Pieces[$script:VRX_Major] }
    if ($Pieces[$script:VRX_Minor]) { $result += ".$($Pieces[$script:VRX_Minor])" }
    if ($Pieces[$script:VRX_Patch]) { $result += ".$($Pieces[$script:VRX_Patch])" }
    if ($Pieces[$script:VRX_Release]) { $result += $Pieces[$script:VRX_Release] }
    if ($Pieces[$script:VRX_RelNumber]) { $result += $Pieces[$script:VRX_RelNumber] }
    if ($Pieces[$script:VRX_x64]) { $result += $Pieces[$script:VRX_x64] }
    if ($Pieces[$script:VRX_ARM]) { $result += $Pieces[$script:VRX_ARM] }
    if ($Pieces[$script:VRX_Web]) { $result += $Pieces[$script:VRX_Web] }
    if ($Pieces[$script:VRX_Ext]) { $result += ".$($Pieces[$script:VRX_Ext])" }

    return $result
}

function Save-DownloadedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$File
    )

    $webClient = $null
    try {
        $parent = Split-Path -Parent $File
        if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($Url, $File)
    } catch {
        Write-Output ":: [ERROR] :: $($_.Exception.Message)"
        exit 1
    } finally {
        if ($null -ne $webClient) {
            $webClient.Dispose()
        }
    }
}

function Clear-InstallArtifacts {
    param(
        [Parameter(Mandatory = $true)]$Params
    )

    if (Test-Path -LiteralPath $Params[$script:IP_InstallPath]) {
        Remove-Item -LiteralPath $Params[$script:IP_InstallPath] -Recurse -Force
    }
    if (Test-Path -LiteralPath $Params[$script:IP_InstallFile]) {
        Remove-Item -LiteralPath $Params[$script:IP_InstallFile] -Force
    }

    foreach ($cachePath in @(
        (Join-Path $script:DirCache $Params[$script:LV_Code]),
        (Join-Path $script:DirCache "$($Params[$script:LV_Code])-webinstall")
    )) {
        if (Test-Path -LiteralPath $cachePath) {
            Remove-Item -LiteralPath $cachePath -Recurse -Force
        }
    }
}

function ConvertTo-PyenvBool {
    param(
        $Value,
        [bool]$Default
    )

    if ($null -eq $Value -or "$Value" -eq '') {
        return $Default
    }

    return "$Value" -ieq 'true'
}

function Load-VersionsXml {
    param(
        [Parameter(Mandatory = $true)][string]$XmlPath
    )

    $versions = [ordered]@{}
    if (-not (Test-Path -LiteralPath $XmlPath -PathType Leaf)) {
        return $versions
    }

    try {
        [xml]$doc = Get-Content -LiteralPath $XmlPath -Raw
    } catch {
        Write-Output "Validation error in DB cache: $($_.Exception.Message)"
        exit 1
    }

    foreach ($version in $doc.versions.version) {
        $code = $version.SelectSingleNode('code').InnerText
        $zipRootDir = ''
        $zipRootDirElement = $version.SelectSingleNode('zipRootDir')
        if ($null -ne $zipRootDirElement) {
            $zipRootDir = $zipRootDirElement.InnerText
        }

        $versions[$code] = @(
            $code,
            $version.SelectSingleNode('file').InnerText,
            $version.SelectSingleNode('URL').InnerText,
            (ConvertTo-PyenvBool -Value $version.GetAttribute('x64') -Default:$false),
            (ConvertTo-PyenvBool -Value $version.GetAttribute('webInstall') -Default:$false),
            (ConvertTo-PyenvBool -Value $version.GetAttribute('msi') -Default:$true),
            $zipRootDir
        )
    }

    return $versions
}

function Save-VersionsXml {
    param(
        [Parameter(Mandatory = $true)][string]$XmlPath,
        [Parameter(Mandatory = $true)]$VersionsArray
    )

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.Indent = $true

    $writer = [System.Xml.XmlWriter]::Create($XmlPath, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('versions')

        foreach ($versionRow in $VersionsArray) {
            $pieces = $versionRow[$script:SFV_Version]
            $writer.WriteStartElement('version')
            $writer.WriteAttributeString('x64', ([bool]($pieces[$script:VRX_x64] -or $pieces[$script:VRX_ARM])).ToString().ToLowerInvariant())
            $writer.WriteAttributeString('webInstall', ([bool]$pieces[$script:VRX_Web]).ToString().ToLowerInvariant())
            $writer.WriteAttributeString('msi', (($pieces[$script:VRX_Ext].ToLowerInvariant()) -eq 'msi').ToString().ToLowerInvariant())

            if ($pieces[$script:VRX_Ext] -eq 'zip') {
                $writer.WriteElementString('code', $pieces[$script:VRX_ZipRoot])
            } else {
                $writer.WriteElementString('code', (Join-Win32String -Pieces $pieces))
            }
            $writer.WriteElementString('file', $versionRow[$script:SFV_FileName])
            $writer.WriteElementString('URL', $versionRow[$script:SFV_URL])
            if ($pieces[$script:VRX_Ext] -eq 'zip') {
                $writer.WriteElementString('zipRootDir', $pieces[$script:VRX_ZipRoot])
            }
            $writer.WriteEndElement()
        }

        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    } finally {
        $writer.Close()
    }
}

function Convert-VersionPartToLong {
    param($Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return [long]0
    }

    return [long]$Value
}

function Compare-VersionPiecesLess {
    param(
        [Parameter(Mandatory = $true)]$Version1,
        [Parameter(Mandatory = $true)]$Version2
    )

    foreach ($index in @($script:VRX_Major, $script:VRX_Minor, $script:VRX_Patch)) {
        $left = Convert-VersionPartToLong $Version1[$index]
        $right = Convert-VersionPartToLong $Version2[$index]
        if ($left -ne $right) {
            return $left -lt $right
        }
    }

    $leftRelease = $Version1[$script:VRX_Release]
    $rightRelease = $Version2[$script:VRX_Release]
    if ([string]::IsNullOrEmpty($leftRelease) -and -not [string]::IsNullOrEmpty($rightRelease)) {
        return $false
    }
    if (-not [string]::IsNullOrEmpty($leftRelease) -and [string]::IsNullOrEmpty($rightRelease)) {
        return $true
    }
    if ($leftRelease -ne $rightRelease) {
        return ([string]::Compare($leftRelease, $rightRelease, $true) -lt 0)
    }

    $leftRelNumber = Convert-VersionPartToLong $Version1[$script:VRX_RelNumber]
    $rightRelNumber = Convert-VersionPartToLong $Version2[$script:VRX_RelNumber]
    if ($leftRelNumber -ne $rightRelNumber) {
        return $leftRelNumber -lt $rightRelNumber
    }

    foreach ($index in @($script:VRX_x64, $script:VRX_ARM, $script:VRX_Web, $script:VRX_Ext)) {
        $left = [string]$Version1[$index]
        $right = [string]$Version2[$index]
        if ($left -ne $right) {
            return ([string]::Compare($left, $right, $true) -lt 0)
        }
    }

    return $false
}

function Sort-SemanticVersionRows {
    param(
        [Parameter(Mandatory = $true)]$Rows
    )

    $items = New-Object System.Collections.ArrayList
    foreach ($row in $Rows) {
        [void]$items.Add($row)
    }

    for ($i = 1; $i -lt $items.Count; $i++) {
        $value = $items[$i]
        $j = $i - 1
        while ($j -ge 0 -and (Compare-VersionPiecesLess -Version1 $value[$script:SFV_Version] -Version2 $items[$j][$script:SFV_Version])) {
            $items[$j + 1] = $items[$j]
            $j--
        }
        $items[$j + 1] = $value
    }

    return @($items.ToArray())
}

function Join-VersionString {
    param(
        [Parameter(Mandatory = $true)]$Pieces
    )

    $result = ''
    if ($Pieces[$script:VRX_Major]) { $result += $Pieces[$script:VRX_Major] }
    if ($Pieces[$script:VRX_Minor]) { $result += ".$($Pieces[$script:VRX_Minor])" }
    if ($Pieces[$script:VRX_Patch]) { $result += ".$($Pieces[$script:VRX_Patch])" }
    if ($Pieces[$script:VRX_Release]) { $result += $Pieces[$script:VRX_Release] }
    if ($Pieces[$script:VRX_RelNumber]) { $result += $Pieces[$script:VRX_RelNumber] }
    if ($Pieces[$script:VRX_Arch]) { $result += $Pieces[$script:VRX_Arch] }

    return $result
}

function Find-LatestVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Prefix,
        [bool]$Known
    )

    if ($Known) {
        $cachedVersions = Load-VersionsXml -XmlPath $script:DBFile
        $candidates = @($cachedVersions.Keys)
    } else {
        $candidates = @(Get-InstalledVersions)
    }

    $bestMatch = $null
    $arch = Get-ArchPostfix

    foreach ($candidate in $candidates) {
        if (-not $candidate.StartsWith($Prefix)) {
            continue
        }

        $nextChar = ''
        if ($candidate.Length -gt $Prefix.Length) {
            $nextChar = $candidate.Substring($Prefix.Length, 1)
        }
        if (($candidate -ne "$Prefix$arch") -and ($nextChar -ne '.')) {
            continue
        }

        $match = $script:RegexVerArch.Match($candidate)
        if (-not $match.Success) {
            continue
        }

        $pieces = Get-RegexSubMatches -Match $match
        if (($pieces[$script:VRX_Release] -eq '') -and ($pieces[$script:VRX_Arch] -eq $arch)) {
            if ($null -eq $bestMatch) {
                $bestMatch = $pieces
            } elseif (Compare-VersionPiecesLess -Version1 $bestMatch -Version2 $pieces) {
                $bestMatch = $pieces
            }
        }
    }

    if ($null -eq $bestMatch) {
        return ''
    }

    return Join-VersionString -Pieces $bestMatch
}

function Resolve-PyenvVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Prefix,
        [bool]$Known
    )

    $resolved = Find-LatestVersion -Prefix $Prefix -Known:$Known
    if ($resolved -eq '') {
        return $Prefix
    }

    return $resolved
}
