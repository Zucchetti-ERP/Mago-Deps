param([string]$Installer, [string]$Vertical)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $root 'modules.json') -Raw | ConvertFrom-Json
foreach ($module in $manifest.modules) {
    $path = Join-Path $root ($module.path -replace '/', '\')
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $module.sha256) {
        throw "Hash diferente: $($module.path)"
    }
    . $path
}
if ($Installer) {
    $info = Get-MagoInstallerInfo $Installer
    if ($Vertical) {
        $verticalInfo = Get-MagoVerticalInfo $Vertical $info.Version
        if (-not $verticalInfo.Kind) { throw 'Vertical sem tipo.' }
    }
    function Read-Host { param([string]$Prompt) return '1' }
    function Confirm-MagoAction { param([string]$Message) return $false }
    $selected = @(Select-MagoVerticals $Installer $info.Version)
    if ($selected.Count -ne 1 -or -not $selected[0].Kind) { throw 'Seleção automática de vertical falhou.' }
    Remove-Item Function:Read-Host
    Remove-Item Function:Confirm-MagoAction
}

$script:CapturedArgs = $null
function Start-Process {
    param([string]$FilePath, [string]$ArgumentList, [switch]$Wait, [switch]$PassThru)
    $script:CapturedArgs = $ArgumentList
    return [pscustomobject]@{ ExitCode = 0 }
}
function Test-MagoInstalledResult { param([string]$Destination) return $true }
if (-not (Invoke-MagoExeInstall 'mock-installer.exe' 'C:\Program Files (x86)\Microarea\Mago4')) {
    throw 'Instalação simulada falhou.'
}
$expectedArgs = 'INSTALLLOCATION="C:\Program Files (x86)\Microarea\\" INSTANCENAME="Mago4"'
if ($script:CapturedArgs -cne $expectedArgs) { throw "Argumentos incorretos: $script:CapturedArgs" }
Remove-Item Function:Start-Process
Remove-Item Function:Test-MagoInstalledResult

$fixture = Join-Path $PSScriptRoot '.scratch-mago'
if (Test-Path -LiteralPath $fixture) { throw 'Pasta de teste já existe; não será removida.' }
try {
    foreach ($relative in @(
        'Apps', 'Custom\Companies', 'Custom\ReferencedAssemblies', 'Custom\ESP',
        'Standard\Taskbuilder\WebFramework\LoginManager\App_Data',
        'Standard\Taskbuilder\WebFramework\M4Server', 'Standard\Other'
    )) { New-Item -ItemType Directory -Path (Join-Path $fixture $relative) -Force | Out-Null }
    foreach ($relative in @(
        'root.txt', 'Apps\remove.txt', 'Custom\Companies\keep.txt',
        'Custom\ReferencedAssemblies\keep.txt', 'Custom\ESP\remove.txt',
        'Standard\Taskbuilder\WebFramework\LoginManager\App_Data\keep.txt',
        'Standard\Taskbuilder\WebFramework\M4Server\remove.txt'
    )) { Set-Content -LiteralPath (Join-Path $fixture $relative) -Value 'test' }
    Clear-MagoAdvancedFiles $fixture
    foreach ($relative in @(
        'Custom\Companies\keep.txt', 'Custom\ReferencedAssemblies\keep.txt',
        'Standard\Taskbuilder\WebFramework\LoginManager\App_Data\keep.txt'
    )) { if (-not (Test-Path -LiteralPath (Join-Path $fixture $relative))) { throw "Arquivo preservado ausente: $relative" } }
    foreach ($relative in @('root.txt', 'Apps', 'Custom\ESP', 'Standard\Other', 'Standard\Taskbuilder\WebFramework\M4Server')) {
        if (Test-Path -LiteralPath (Join-Path $fixture $relative)) { throw "Arquivo deveria ser removido: $relative" }
    }
    Write-Host 'Smoke test OK'
} finally {
    $resolvedRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
    $resolvedFixture = [IO.Path]::GetFullPath($fixture).TrimEnd('\')
    if ($resolvedFixture.StartsWith("$resolvedRoot\", [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $fixture)) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
