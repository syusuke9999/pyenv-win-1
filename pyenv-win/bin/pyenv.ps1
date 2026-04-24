try {
    $OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding
} catch {
}

If (($Args.Count -ge 2) -and ($Args[0] -eq "shell")) {
    if ($Args[1] -eq "--help") {
        & "$PSScriptRoot\pyenv.bat" @Args
        Exit $LastExitCode
    } elseif ($Args[1] -eq "--unset") {
        If (Test-Path Env:PYENV_VERSION) {
            Remove-Item Env:PYENV_VERSION
        }
    } else {
        $global:LASTEXITCODE = 0
        $Output = (& "$PSScriptRoot\..\libexec\pyenv.ps1" @Args)
        if ($LastExitCode -ne 0) {
            $Output -join [Environment]::NewLine
            Exit $LastExitCode
        }
        $Env:PYENV_VERSION = ($Output -join [Environment]::NewLine)
    }
} Else {
    & "$PSScriptRoot\pyenv.bat" @Args
    Exit $LastExitCode
}
