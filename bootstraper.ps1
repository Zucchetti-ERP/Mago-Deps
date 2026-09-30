param(
    [string]$Ref,
    [string]$Branch,
    [switch]$Local,
    [string]$ResumeId,
    [switch]$NoMenu
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repo = 'Zucchetti-ERP/Mago-Deps'
if ($Ref -and $Ref -notmatch '^[0-9a-fA-F]{40}$') { throw 'Revisao invalida.' }
if ($ResumeId -and $ResumeId -notmatch '^[0-9a-fA-F-]{36}$') { throw 'Sessao invalida.' }
$selectedBranch = if ($Branch) { $Branch } elseif ($env:MAGO_DEPS_BRANCH) { $env:MAGO_DEPS_BRANCH } else { 'master' }
if ($selectedBranch -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$' -or $selectedBranch.Contains('..') -or $selectedBranch.EndsWith('/')) {
    throw 'Nome da branch invalido.'
}
$api = "https://api.github.com/repos/$repo/commits/$([uri]::EscapeDataString($selectedBranch))"
$scriptFile = $PSCommandPath
$localSource = $Local -or ($scriptFile -and -not $Ref -and -not $Branch -and (Test-Path -LiteralPath (Join-Path (Split-Path $scriptFile) 'src')))

try {
    if (-not $localSource -and -not $Ref) {
        $commit = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'Mago4-Setup' } -UseBasicParsing
        $Ref = [string]$commit.sha
        if ($Ref -notmatch '^[0-9a-fA-F]{40}$') { throw 'A API nao retornou uma revisao valida.' }
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if (-not $isAdmin) {
        if ($localSource) {
            $elevatedFile = $scriptFile
            $mode = '-Local'
        } else {
            $elevationDir = Join-Path $env:TEMP "Mago4-Setup\$Ref"
            New-Item -ItemType Directory -Path $elevationDir -Force | Out-Null
            $elevatedFile = Join-Path $elevationDir 'bootstraper.ps1'
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$repo/$Ref/bootstraper.ps1" -OutFile $elevatedFile -UseBasicParsing
            $mode = "-Ref $Ref"
        }
        if (-not $elevatedFile) { throw 'Nao foi possivel localizar o bootstrap para elevar.' }
        $resumeArg = if ($ResumeId) { " -ResumeId $ResumeId" } else { '' }
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$elevatedFile`" $mode$resumeArg" | Out-Null
        return
    }

    $Host.UI.RawUI.WindowTitle = 'Scripts Mago4 - Zucchetti Brasil'
    if ($localSource) {
        $moduleRoot = Split-Path $scriptFile
        $moduleManifestPath = Join-Path $moduleRoot 'modules.json'
    } else {
        $moduleRoot = Join-Path $env:TEMP "Mago4-Setup\$Ref"
        New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
        $base = "https://raw.githubusercontent.com/$repo/$Ref"
        if (-not $scriptFile) {
            $scriptFile = Join-Path $moduleRoot 'bootstraper.ps1'
            Invoke-WebRequest -Uri "$base/bootstraper.ps1" -OutFile $scriptFile -UseBasicParsing
        }
        $moduleManifestPath = Join-Path $moduleRoot 'modules.json'
        Invoke-WebRequest -Uri "$base/modules.json" -OutFile $moduleManifestPath -UseBasicParsing
    }
    $moduleManifest = Get-Content -LiteralPath $moduleManifestPath -Raw | ConvertFrom-Json
    if ($moduleManifest.schema -ne 1 -or @($moduleManifest.modules).Count -lt 5) { throw 'Manifesto de modulos invalido.' }
    $seen = @{}
    foreach ($module in $moduleManifest.modules) {
        $relative = [string]$module.path
        if ($relative -notmatch '^src/[A-Za-z0-9/]+\.ps1$' -or $seen.ContainsKey($relative)) {
            throw "Caminho de modulo invalido ou duplicado: $relative"
        }
        $seen[$relative] = $true
        $destination = Join-Path $moduleRoot ($relative -replace '/', '\')
        if (-not $localSource) {
            if ([string]$module.sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw "Hash invalido: $relative" }
            $validCache = (Test-Path -LiteralPath $destination) -and
                ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ieq [string]$module.sha256)
            if (-not $validCache) {
                New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
                $partial = "$destination.part"
                try {
                    Invoke-WebRequest -Uri "$base/$relative" -OutFile $partial -UseBasicParsing
                    if ((Get-Item -LiteralPath $partial).Length -eq 0 -or
                        (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ine [string]$module.sha256) {
                        throw 'Arquivo vazio ou hash SHA-256 diferente do manifesto.'
                    }
                    Move-Item -LiteralPath $partial -Destination $destination -Force
                } finally { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
            }
        }
        if (-not (Test-Path -LiteralPath $destination)) { throw "Modulo ausente: $relative" }
        . $destination
    }
    $script:ModuleRoot = $moduleRoot
    $script:BootstrapPath = $scriptFile
    if (-not $localSource) {
        $script:ManifestUrl = "$base/manifest.json"
        $script:CodeRef = $Ref
    } elseif (Test-Path -LiteralPath (Join-Path $moduleRoot 'manifest.json')) {
        $script:ManifestLocalPath = Join-Path $moduleRoot 'manifest.json'
    }
    if ($ResumeId) { Invoke-MagoResume -ResumeId $ResumeId }
    elseif (-not $NoMenu -and -not (Invoke-MagoPendingSession)) { Start-Mago4Bootstrap }
} catch {
    Write-Host "  Falha na inicializacao: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
