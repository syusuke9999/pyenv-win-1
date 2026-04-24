Set-StrictMode -Version 2.0

. "$PSScriptRoot\libs\pyenv-lib.ps1"
. "$PSScriptRoot\libs\pyenv-install-lib.ps1"

foreach ($mirror in $script:Mirrors) {
    Write-Output ":: [Info] ::  Mirror: $mirror"
}

function Show-UpdateHelp {
    Write-Output 'Usage: pyenv update [--ignore]'
    Write-Output ''
    Write-Output '  --ignore  Ignores any HTTP/PowerShell errors that occur during downloads.'
    Write-Output ''
    Write-Output "Updates the internal database of python installer URL's."
    Write-Output ''
    exit 0
}

function Copy-OrderedDictionary {
    param([Parameter(Mandatory = $true)]$Dictionary)

    $copy = [ordered]@{}
    foreach ($key in $Dictionary.Keys) {
        $copy[$key] = $Dictionary[$key]
    }
    return $copy
}

function Update-OrderedDictionary {
    param(
        [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)]$Source
    )

    foreach ($key in $Source.Keys) {
        $Target[$key] = $Source[$key]
    }
}

function Resolve-LinkUrl {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$Href
    )

    if (-not $BaseUrl.EndsWith('/')) {
        $BaseUrl = "$BaseUrl/"
    }

    return ([Uri]::new([Uri]$BaseUrl, $Href)).AbsoluteUri
}

function Get-UriLeafName {
    param([Parameter(Mandatory = $true)][string]$Url)

    $uri = [Uri]$Url
    $path = $uri.AbsolutePath.TrimEnd('/')
    return [System.IO.Path]::GetFileName($path)
}

function Get-HtmlLinks {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$BaseUrl
    )

    $links = @()
    $regex = [regex]'(?is)<a\b[^>]*\bhref\s*=\s*["''](?<href>[^"'']+)["''][^>]*>(?<text>.*?)</a>'
    foreach ($match in $regex.Matches($Content)) {
        $href = $match.Groups['href'].Value
        $text = [regex]::Replace($match.Groups['text'].Value, '<[^>]+>', '')
        $links += [pscustomobject]@{
            Href = Resolve-LinkUrl -BaseUrl $BaseUrl -Href $href
            Text = [System.Net.WebUtility]::HtmlDecode($text).Trim()
        }
    }

    return @($links)
}

function Get-WebText {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [bool]$Ignore,
        [Parameter(Mandatory = $true)][string]$Context
    )

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -ErrorAction Stop
        return [string]$response.Content
    } catch {
        Write-Output "HTTP Error downloading from $Context ""$Url"""
        Write-Output "Error: $($_.Exception.Message)"
        if ($Ignore) {
            return $null
        }
        exit 1
    }
}

function Scan-ForVersions {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [bool]$Ignore,
        [Parameter(Mandatory = $true)][ref]$PageCount
    )

    $result = [ordered]@{}
    $content = Get-WebText -Url $Url -Ignore:$Ignore -Context 'mirror page'
    if ($null -eq $content) {
        return $result
    }
    $PageCount.Value++

    foreach ($link in Get-HtmlLinks -Content $content -BaseUrl $Url) {
        $fileName = $link.Text.Trim()
        $match = $script:RegexFile.Match($fileName)
        if ($match.Success) {
            $result[$fileName] = @($fileName, $link.Href, (Get-RegexSubMatches -Match $match))
        }
    }

    return $result
}

$optIgnore = $false
if ($args.Count -ge 1) {
    if ($args[0] -eq '--help') {
        Show-UpdateHelp
    } elseif ($args[0] -eq '--ignore') {
        $optIgnore = $true
    }
}

$pageCount = 0
$installers1 = [ordered]@{}

foreach ($mirror in $script:Mirrors) {
    $content = Get-WebText -Url $mirror -Ignore:$optIgnore -Context 'mirror'
    if ($null -eq $content) {
        continue
    }
    $pageCount++

    $links = @(Get-HtmlLinks -Content $content -BaseUrl $mirror)
    if ($links.Count -eq 0) {
        foreach ($match in $script:RegexJsonUrl.Matches($content)) {
            $installers1[$match.Groups[2].Value] = @(
                $match.Groups[2].Value,
                $match.Groups[1].Value,
                @(
                    $match.Groups[4].Value,
                    $match.Groups[5].Value,
                    $match.Groups[6].Value,
                    '',
                    '',
                    $match.Groups[7].Value,
                    $match.Groups[8].Value,
                    '',
                    'zip',
                    $match.Groups[3].Value
                )
            )
        }
    } else {
        foreach ($link in $links) {
            $version = Get-UriLeafName -Url $link.Href
            if ($script:RegexVer.IsMatch($version)) {
                $found = Scan-ForVersions -Url $link.Href -Ignore:$optIgnore -PageCount ([ref]$pageCount)
                Update-OrderedDictionary -Target $installers1 -Source $found
            }
        }
    }
}

$installers2 = Copy-OrderedDictionary -Dictionary $installers1
$minVers = @('2', '4', '', '', '', '', '', '', '')

foreach ($fileName in @($installers1.Keys)) {
    $versPieces = $installers1[$fileName][$script:SFV_Version]
    if (Compare-VersionPiecesLess -Version1 $versPieces -Version2 $minVers) {
        $installers2.Remove($fileName)
    } elseif ($versPieces[$script:VRX_Web]) {
        $fileNonWeb = 'python-' + (Join-InstallString -Pieces @(
            $versPieces[$script:VRX_Major],
            $versPieces[$script:VRX_Minor],
            $versPieces[$script:VRX_Patch],
            $versPieces[$script:VRX_Release],
            $versPieces[$script:VRX_RelNumber],
            $versPieces[$script:VRX_x64],
            $versPieces[$script:VRX_ARM],
            '',
            $versPieces[$script:VRX_Ext]
        ))
        if ($installers2.Contains($fileNonWeb)) {
            $installers2.Remove($fileName)
        }
    }
}

$installArr = @(Sort-SemanticVersionRows -Rows $installers2.Values)
Save-VersionsXml -XmlPath $script:DBFile -VersionsArray $installArr
Write-Output ":: [Info] ::  Scanned $pageCount pages and found $($installers2.Count) installers."
