# terminal-misma-carpeta.ps1
# Hace que en Windows Terminal las pestañas y paneles nuevos abran en la carpeta actual de CMD.
#   1. CMD: AutoRun en HKCU\Software\Microsoft\Command Processor con un prompt que emite OSC 9;9 ($P).
#   2. Windows Terminal (settings.json):
#        Ctrl+Shift+T  -> duplicar pestaña        (Terminal.DuplicateTab)
#        Ctrl+Shift+D  -> duplicar pestaña        (Terminal.DuplicateTab)
#        Alt+Shift+D   -> duplicar panel (auto)   (Terminal.DuplicatePaneAuto,  splitMode duplicate)
#        Alt+Shift++   -> duplicar panel derecha  (Terminal.DuplicatePaneRight, splitMode duplicate)
#        Alt+Shift+-   -> duplicar panel abajo    (Terminal.DuplicatePaneDown,  splitMode duplicate)
#        Menú ▾ del botón + -> primera opción "Duplicar pestaña"
#      Nota: el clic en el botón + no se puede reasignar (siempre abre el perfil por defecto).
# Copia de seguridad en %LOCALAPPDATA%\terminal-misma-carpeta\<fecha>\
#
# Uso:      powershell -ExecutionPolicy Bypass -File .\terminal-misma-carpeta.ps1
# Deshacer: powershell -ExecutionPolicy Bypass -File .\terminal-misma-carpeta.ps1 -Deshacer
# Probar sin tocar nada: añade -Simular (muestra el JSON resultante)

param(
    [switch]$Deshacer,
    [switch]$Simular,
    [string]$Settings = (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
)

$ErrorActionPreference = 'Stop'
$clave     = 'HKCU:\Software\Microsoft\Command Processor'
$prompt    = 'prompt $e]9;9;$P$e\$P$G'
$copias    = Join-Path $env:LOCALAPPDATA 'terminal-misma-carpeta'
$utf8      = New-Object System.Text.UTF8Encoding $false
$atajos    = [ordered]@{
    'ctrl+shift+t'   = 'Terminal.DuplicateTab'
    'ctrl+shift+d'   = 'Terminal.DuplicateTab'
    'alt+shift+d'    = 'Terminal.DuplicatePaneAuto'
    'alt+shift+plus' = 'Terminal.DuplicatePaneRight'
    'alt+shift+-'    = 'Terminal.DuplicatePaneDown'
}

# ---------- Deshacer ----------
if ($Deshacer) {
    $ultima = Get-ChildItem $copias -Directory -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
    if (-not $ultima) { throw "No hay copias en $copias" }
    Copy-Item (Join-Path $ultima.FullName 'settings.json') $Settings -Force
    Write-Host "OK  settings.json restaurado desde $($ultima.FullName)"
    $previo = Get-Content (Join-Path $ultima.FullName 'autorun.txt') -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($previo)) {
        Remove-ItemProperty -Path $clave -Name AutoRun -ErrorAction SilentlyContinue
        Write-Host "OK  AutoRun de CMD eliminado"
    } else {
        Set-ItemProperty -Path $clave -Name AutoRun -Value $previo.Trim()
        Write-Host "OK  AutoRun de CMD restaurado: $($previo.Trim())"
    }
    return
}

if (-not (Test-Path $Settings)) { throw "No encuentro settings.json en $Settings" }

# ---------- Calcular AutoRun ----------
$actual = $null
if (Test-Path $clave) { $actual = (Get-ItemProperty $clave -ErrorAction SilentlyContinue).AutoRun }
if ([string]::IsNullOrWhiteSpace($actual)) { $nuevo = $prompt }
elseif ($actual -like '*9;9;*')            { $nuevo = $actual }          # ya configurado
else                                       { $nuevo = "$prompt & $actual" } # conserva lo que hubiera

# ---------- Calcular settings.json ----------
$json = Get-Content $Settings -Raw -Encoding UTF8 | ConvertFrom-Json   # falla si el archivo tiene comentarios
if (-not $json.PSObject.Properties['keybindings']) { $json | Add-Member keybindings @() }
$teclas = @($atajos.Keys)
$lista  = @($json.keybindings | Where-Object { $teclas -notcontains $_.keys })
foreach ($k in $atajos.Keys) { $lista += [pscustomobject]@{ id = $atajos[$k]; keys = $k } }
$json.keybindings = $lista

$entrada = [pscustomobject]@{ type = 'action'; id = 'Terminal.DuplicateTab' }
if (-not $json.PSObject.Properties['newTabMenu']) { $json | Add-Member newTabMenu @([pscustomobject]@{ type = 'remainingProfiles' }) }
$menu = @($json.newTabMenu | Where-Object { -not ($_.type -eq 'action' -and $_.id -eq 'Terminal.DuplicateTab') })
$json.newTabMenu = @($entrada) + $menu

$texto = $json | ConvertTo-Json -Depth 50
$null  = $texto | ConvertFrom-Json   # comprobar que sigue siendo JSON válido

if ($Simular) {
    Write-Host "AutoRun quedaría: $nuevo"
    $texto
    return
}

# ---------- Copia de seguridad ----------
$destino = Join-Path $copias (Get-Date -Format 'yyyy-MM-dd_HHmmss')
New-Item -ItemType Directory -Force $destino | Out-Null
Copy-Item $Settings (Join-Path $destino 'settings.json')
[System.IO.File]::WriteAllText((Join-Path $destino 'autorun.txt'), [string]$actual, $utf8)
Write-Host "OK  Copia en $destino"

# ---------- Aplicar ----------
if (-not (Test-Path $clave)) { New-Item -Path $clave -Force | Out-Null }
Set-ItemProperty -Path $clave -Name AutoRun -Value $nuevo
Write-Host "OK  AutoRun de CMD: $nuevo"

[System.IO.File]::WriteAllText($Settings, $texto, $utf8)
Write-Host "OK  $Settings"
Write-Host ""
Write-Host "Cierra y abre Windows Terminal. Prueba: pestaña CMD -> cd C:\Windows -> Ctrl+Shift+T"
