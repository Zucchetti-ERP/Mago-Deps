$script:W = 54
$script:Manifest = $null
$script:ManifestUrl = 'https://raw.githubusercontent.com/Zucchetti-ERP/Mago-Deps/master/manifest.json'
$script:DownloadDir = Join-Path $env:TEMP 'Mago4-Setup'
$programFilesRoot = if (${env:ProgramFiles(x86)}) { ${env:ProgramFiles(x86)} } else { $env:ProgramFiles }
$script:DefaultMagoPath = Join-Path $programFilesRoot 'Microarea\Mago4'
$script:SessionRoot = Join-Path $env:ProgramData 'Mago4-Setup\Sessions'

function Read-ExistingPath {
    param([string]$Prompt, [ValidateSet('File','Directory')][string]$Type = 'File', [string]$Extension = '')
    Write-Host '  Você pode arrastar o arquivo ou a pasta para esta janela.' -ForegroundColor DarkGray
    $value = (Read-Host "  $Prompt").Trim().Trim('"', "'")
    if (-not $value) { return $null }
    try {
        $item = Get-Item -LiteralPath $value -ErrorAction Stop
        if ($Type -eq 'File' -and $item.PSIsContainer) { throw 'Era esperado um arquivo.' }
        if ($Type -eq 'Directory' -and -not $item.PSIsContainer) { throw 'Era esperada uma pasta.' }
        if ($Extension -and $item.Extension -ine $Extension) { throw "Era esperado um arquivo $Extension." }
        return $item.FullName
    } catch { Write-Fail "Caminho inválido ou inacessível: $($_.Exception.Message)"; return $null }
}

function Confirm-MagoAction {
    param([string]$Message)
    return (Read-Host "  $Message [S/N]").Trim().ToUpperInvariant() -eq 'S'
}

function Get-MagoLogDirectory {
    $path = Join-Path $env:ProgramData 'Mago4-Setup\Logs'
    New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
    return $path
}

function Test-MagoExitCode {
    param([int]$ExitCode, [string]$Action)
    if ($ExitCode -eq 0) { Write-Ok "$Action concluído."; return $true }
    if ($ExitCode -eq 3010) { Write-Warn "$Action concluído; reinicialização necessária."; return $true }
    if ($ExitCode -eq 1638) { Write-Ok "$Action já está instalado ou atualizado."; return $true }
    Write-Fail "$Action falhou. Código: $ExitCode"
    return $false
}
