@echo off
setlocal

set "pyenv=powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pyenv.ps1""

set "skip=-1"
for /f "delims=" %%i in ('echo skip') do (call :incrementskip)
if [%skip%]==[0] set "skip_arg="
if not [%skip%]==[0] set "skip_arg=skip=%skip% "

if "%1" == "--help" (
  echo Usage: pyenv shell ^<version^>
  echo        pyenv shell --unset
  echo.
  echo Sets a shell-specific Python version by setting the `PYENV_VERSION'
  echo environment variable in your shell. This version overrides local
  echo application-specific versions and the global version.
  echo.
  EXIT /B
)

if [%1]==[] (
  if "%PYENV_VERSION%"=="" (
    echo no shell-specific version configured
  ) else (
    echo %PYENV_VERSION%
  )

) else if /i [%1]==[--unset] (
  endlocal && set "PYENV_VERSION="

) else (
  %pyenv% shell %* 1> nul || goto :error
  for /f "%skip_arg%delims=" %%a in ('%pyenv% shell %*') do (
    endlocal && set "PYENV_VERSION=%%a"
  )
)

goto :eof

:incrementskip
set /a skip=%skip%+1
goto :eof

:error
%pyenv% shell %*
exit /b %errorlevel%

