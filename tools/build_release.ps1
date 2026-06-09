# tools/build_release.ps1
# Exporta o JOGO (game.zip) e/ou o LAUNCHER (Launcher.exe) e publica no GitHub.
#
# Uso:
#   .\tools\build_release.ps1                          # exporta game.zip com versao atual
#   .\tools\build_release.ps1 -Version 1.1.0           # define nova versao
#   .\tools\build_release.ps1 -Version 1.1.0 -Publish  # publica release no GitHub
#   .\tools\build_release.ps1 -Launcher                # exporta so o Launcher.exe (raramente muda)
#
# Pre-requisitos (uma vez):
#   - Godot com export templates instalados.
#   - Preset "Windows Desktop" em Projeto > Exportar (nos dois projetos).
#   - Para -Publish: GitHub CLI autenticado (gh auth login).

param(
    [string]$Version,
    [switch]$Publish,
    [switch]$Launcher
)
$ErrorActionPreference = "Stop"

$GameProj     = "C:\Work\TribalLine"
$LauncherProj = "C:\Work\TribalLineClient"
$Godot        = "C:\Users\luang\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe"
$Preset       = "Windows Desktop"
$GameExe      = "TribalLine.exe"
$LauncherExe  = "TribalLine Launcher.exe"

# ---------------------------------------------------------------------------
# Versao
# ---------------------------------------------------------------------------
$versionFile = Join-Path $GameProj "version.txt"
if ($Version) {
    Set-Content -Path $versionFile -Value $Version -NoNewline -Encoding utf8
} else {
    $Version = (Get-Content $versionFile -Raw).Trim()
}
Write-Host "==> Versao: $Version" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Export do JOGO -> builds\game.zip  (sempre, exceto se so -Launcher)
# ---------------------------------------------------------------------------
if (-not $Launcher) {
    $outDir = Join-Path $GameProj "builds\game"
    $zip    = Join-Path $GameProj "builds\game.zip"

    if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    Write-Host "==> Exportando o jogo..." -ForegroundColor Cyan
    & $Godot --headless --path $GameProj --export-release $Preset (Join-Path $outDir $GameExe)
    if (-not (Test-Path (Join-Path $outDir $GameExe))) {
        throw "Export falhou: $GameExe nao gerado. Confira o preset '$Preset' e os export templates."
    }

    # version.txt vai dentro do zip — launcher usa pra saber a versao instalada
    Copy-Item $versionFile (Join-Path $outDir "version.txt") -Force

    Write-Host "==> Compactando game.zip..." -ForegroundColor Cyan
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $outDir "*") -DestinationPath $zip
    Write-Host "==> game.zip pronto: $zip" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Export do LAUNCHER -> builds\launcher\  (so com -Launcher)
# ---------------------------------------------------------------------------
if ($Launcher) {
    $launcherOut = Join-Path $GameProj "builds\launcher"

    if (Test-Path $launcherOut) { Remove-Item $launcherOut -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $launcherOut | Out-Null

    Write-Host "==> Exportando o launcher..." -ForegroundColor Cyan
    & $Godot --headless --path $LauncherProj --export-release $Preset (Join-Path $launcherOut $LauncherExe)
    if (-not (Test-Path (Join-Path $launcherOut $LauncherExe))) {
        throw "Export do launcher falhou. Confira o preset '$Preset' no projeto TribalLineClient."
    }
    Write-Host "==> Launcher pronto: $launcherOut" -ForegroundColor Green
    Write-Host ""
    Write-Host "Envie para os jogadores:" -ForegroundColor Yellow
    Write-Host "  - '$LauncherExe'" -ForegroundColor Yellow
    Write-Host "  - 'TribalLine Launcher.pck' (gerado junto)" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Publicar release no GitHub
# ---------------------------------------------------------------------------
if ($Publish -and -not $Launcher) {
    $zip = Join-Path $GameProj "builds\game.zip"
    Write-Host "==> Publicando release v$Version em luanlgo/TribalLine..." -ForegroundColor Cyan
    & gh release create "v$Version" $zip `
        --repo "luanlgo/TribalLine" `
        --title "v$Version" `
        --notes "Atualizacao automatica v$Version."
    Write-Host "==> Release publicada! O launcher ja vai baixar automaticamente." -ForegroundColor Green
} elseif (-not $Launcher) {
    Write-Host ""
    Write-Host "Para publicar a release (o launcher baixa sozinho):" -ForegroundColor Yellow
    Write-Host "  .\tools\build_release.ps1 -Version $Version -Publish" -ForegroundColor White
}
