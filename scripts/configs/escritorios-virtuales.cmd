@echo off
rem escritorios-virtuales.cmd
rem Hace que cada escritorio virtual funcione por separado: las apps se abren
rem en el escritorio actual y no saltan a otro.
rem   1. Explorador: no abre carpetas como pestana en una ventana de otro escritorio
rem      (OpenFolderInNewTab = 0; se escribe en Explorer y Explorer\Advanced porque
rem       la clave varia segun la build).
rem   2. Explorador: cada ventana en su propio proceso (SeparateProcess = 1).
rem   3. Barra de tareas y Alt+Tab: solo ventanas del escritorio actual
rem      (VirtualDesktopTaskbarFilter = 1, VirtualDesktopAltTabFilter = 1).
rem   4. Empezar de cero al iniciar sesion:
rem      - Windows no reabre apps (RestartApps = 0).
rem      - El Explorador no restaura carpetas (PersistBrowsers = 0).
rem      - Tras reiniciar por una actualizacion no se reabren apps
rem        (DisableAutomaticRestartSignOn = 1). Solo como administrador; si no, se salta.
rem Copia de los valores anteriores en %LOCALAPPDATA%\escritorios-virtuales\respaldo.txt
rem (cada valor se guarda solo la primera vez, para que deshacer vuelva al estado original).
rem
rem Uso:      escritorios-virtuales.cmd
rem Deshacer: escritorios-virtuales.cmd /deshacer
rem Probar sin tocar nada: escritorios-virtuales.cmd /simular

setlocal EnableExtensions EnableDelayedExpansion

set "EXP=HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer"
set "ADV=%EXP%\Advanced"
set "WINLOGON=HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
set "POLITICA=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
set "DIR=%LOCALAPPDATA%\escritorios-virtuales"
set "RESPALDO=%DIR%\respaldo.txt"
set "SIMULAR="
set "ADMIN="
net session >nul 2>&1 && set "ADMIN=1"

if /i "%~1"=="/deshacer" goto :deshacer
if /i "%~1"=="/simular" set "SIMULAR=1"
if not "%~1"=="" if not defined SIMULAR (
    echo Opcion desconocida: %~1
    echo Uso: %~nx0 [/deshacer ^| /simular]
    exit /b 1
)

rem ---------- Copia de seguridad ----------
if defined SIMULAR (
    echo [simular] Valores actuales:
) else if not exist "%RESPALDO%" (
    if not exist "%DIR%" mkdir "%DIR%"
    type nul > "%RESPALDO%"
)
call :respaldar "%EXP%" OpenFolderInNewTab
call :respaldar "%ADV%" OpenFolderInNewTab
call :respaldar "%ADV%" SeparateProcess
call :respaldar "%ADV%" VirtualDesktopTaskbarFilter
call :respaldar "%ADV%" VirtualDesktopAltTabFilter
call :respaldar "%WINLOGON%" RestartApps
call :respaldar "%ADV%" PersistBrowsers
if defined ADMIN call :respaldar "%POLITICA%" DisableAutomaticRestartSignOn

rem ---------- Aplicar ----------
if defined SIMULAR echo [simular] Se aplicaria:
call :poner "%EXP%" OpenFolderInNewTab 0
call :poner "%ADV%" OpenFolderInNewTab 0
call :poner "%ADV%" SeparateProcess 1
call :poner "%ADV%" VirtualDesktopTaskbarFilter 1
call :poner "%ADV%" VirtualDesktopAltTabFilter 1
call :poner "%WINLOGON%" RestartApps 0
call :poner "%ADV%" PersistBrowsers 0
if defined ADMIN (
    call :poner "%POLITICA%" DisableAutomaticRestartSignOn 1
) else (
    echo Aviso: sin administrador se salta DisableAutomaticRestartSignOn
    echo        ^(reabrir apps tras una actualizacion^). Ejecutalo como administrador para incluirlo.
)

if defined SIMULAR exit /b 0
call :reiniciar_explorer
echo.
echo Listo. Copia de seguridad en: %RESPALDO%
echo Consejo: Shift+clic (o clic con la rueda) en un icono de la barra de tareas
echo abre una instancia nueva en el escritorio actual, incluso en apps que
echo reutilizan su ventana.
exit /b 0

rem ---------- Deshacer ----------
:deshacer
if not exist "%RESPALDO%" (
    echo No hay copia de seguridad en %RESPALDO%
    exit /b 1
)
set "FALLO="
for /f "usebackq tokens=1-3 delims=;" %%a in ("%RESPALDO%") do (
    set "ok=1"
    if "%%c"=="-" (
        reg query "%%a" /v %%b >nul 2>&1 && (reg delete "%%a" /v %%b /f >nul 2>&1 || set "ok=")
    ) else (
        reg add "%%a" /v %%b /t REG_DWORD /d %%c /f >nul 2>&1 || set "ok="
    )
    if defined ok (
        echo Restaurado %%b = %%c
    ) else (
        set "FALLO=1"
        echo No se pudo restaurar %%b ^(si es HKLM, ejecuta como administrador^)
    )
)
call :reiniciar_explorer
if defined FALLO (
    echo Faltan valores por restaurar. La copia se conserva en %RESPALDO%
    exit /b 1
)
del "%RESPALDO%"
echo Valores originales restaurados.
exit /b 0

rem ---------- Funciones ----------
rem :respaldar <clave> <valor>  -> guarda "clave;valor;dato" ("-" si no existia)
rem Si el valor ya esta en la copia no se vuelve a guardar (se conserva el original).
:respaldar
set "dato=-"
for /f "tokens=3" %%v in ('reg query "%~1" /v %~2 2^>nul ^| findstr /i "REG_DWORD"') do set "dato=%%v"
if defined SIMULAR (
    echo   %~1\%~2 = !dato!
    exit /b 0
)
findstr /b /i /l /c:"%~1;%~2;" "%RESPALDO%" >nul 2>&1 || >>"%RESPALDO%" echo %~1;%~2;!dato!
exit /b 0

rem :poner <clave> <valor> <dato>
:poner
if defined SIMULAR (
    echo   %~1\%~2 = %~3
    exit /b 0
)
reg add "%~1" /v %~2 /t REG_DWORD /d %~3 /f >nul || (
    echo Error al escribir %~1\%~2
    exit /b 1
)
echo Aplicado %~2 = %~3
exit /b 0

:reiniciar_explorer
echo Reiniciando el Explorador...
taskkill /f /im explorer.exe >nul 2>&1
start "" explorer.exe
exit /b 0
