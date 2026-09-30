param([string]$Installer, [string]$Vertical, [string]$Msi)

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
if (-not (Invoke-MagoMainInstall ([pscustomobject]@{ Type = 'Exe'; Path = 'mock-installer.exe' }) 'C:\Program Files (x86)\Microarea\Mago4')) {
    throw 'Instalação simulada falhou.'
}
$expectedArgs = 'INSTALLLOCATION="C:\Program Files (x86)\Microarea\\" INSTANCENAME="Mago4"'
if ($script:CapturedArgs -cne $expectedArgs) { throw "Argumentos incorretos: $script:CapturedArgs" }
Remove-Item Function:Start-Process
Remove-Item Function:Test-MagoInstalledResult

if ($Msi) {
    $msiInfo = Get-MagoInstallerInfo $Msi
    if ($msiInfo.Type -cne 'Msi' -or -not $msiInfo.MshPath -or
        $msiInfo.Features -notmatch 'Feat_pt_BR' -or $msiInfo.Features -match 'Feat_it_IT|Feat_PAAS|Feat_TaskBuilderStudio') {
        throw 'Pacote MSI/MSH ou seleção de funcionalidades inválida.'
    }
    $script:MainInstallCalls = @()
    function Get-MagoLogDirectory { return $PSScriptRoot }
    function Start-Process {
        param([string]$FilePath, [string]$ArgumentList, [switch]$Wait, [switch]$PassThru)
        $script:MainInstallCalls += [pscustomobject]@{ FilePath = $FilePath; ArgumentList = $ArgumentList }
        return [pscustomobject]@{ ExitCode = 0 }
    }
    function Test-MagoInstalledResult { param([string]$Destination) return $true }
    if (-not (Invoke-MagoMainInstall $msiInfo 'C:\Mago\Mago4')) { throw 'Instalação MSI simulada falhou.' }
    if ($script:MainInstallCalls.Count -ne 2 -or $script:MainInstallCalls[0].FilePath -ne 'msiexec.exe' -or
        $script:MainInstallCalls[0].ArgumentList -notmatch ' /qn /norestart ' -or
        $script:MainInstallCalls[0].ArgumentList -notmatch 'UICULTURE=pt-BR ADDLOCAL=' -or
        $script:MainInstallCalls[0].ArgumentList -cnotlike '*INSTALLLOCATION="C:\Mago\\"*' -or
        $script:MainInstallCalls[1].FilePath -cne $msiInfo.MshPath -or
        $script:MainInstallCalls[1].ArgumentList -cne '/install /quiet /norestart') {
        throw 'Comandos da instalação MSI/MSH incorretos.'
    }
    Remove-Item Function:Start-Process
    Remove-Item Function:Test-MagoInstalledResult
    Remove-Item Function:Get-MagoLogDirectory
}

function Get-MagoMainEntry { return [pscustomobject]@{ InstallLocation = 'C:\Mago\Mago4\' } }
function Get-ChildItem {
    param([string]$LiteralPath)
    if ($LiteralPath -eq 'HKLM:\SOFTWARE\WOW6432Node\Microarea\Mago4') {
        return [pscustomobject]@{ PSPath = 'mock-registry-entry' }
    }
}
function Get-ItemProperty {
    param([string]$LiteralPath)
    if ($LiteralPath -eq 'mock-registry-entry') {
        return [pscustomobject]@{ PSChildName = 'mock-guid'; InstallDir = 'C:\Mago\Mago4\'; UICulture = 'pt-BR'; Dictionaries = 'pt-BR ' }
    }
}
$record = Get-MagoInstallRecord
if ($record.Path -cne 'C:\Mago\Mago4' -or $record.Registry.UICulture -cne 'pt-BR') {
    throw 'Registro do Mago4 na visão de 32 bits não foi encontrado.'
}
Remove-Item Function:Get-MagoMainEntry
Remove-Item Function:Get-ChildItem
Remove-Item Function:Get-ItemProperty

$mockVertical = [pscustomobject]@{
    Name = 'Mago4 MSO 6.0.0'; Kind = 'MSO'; Version = [version]'6.0.0'
    ProductCode = '{625574C2-2FC0-4D7A-B237-C6EB2D61B24F}'; Path = 'mock-vertical.msi'
}
function Get-MagoLogDirectory { return $PSScriptRoot }
function Start-Process {
    param([string]$FilePath, [string]$ArgumentList, [switch]$Wait, [switch]$PassThru)
    return [pscustomobject]@{ ExitCode = 1603 }
}
$script:VerticalStateChecks = 0
function Test-MagoVerticalInstalled {
    param($Vertical)
    $script:VerticalStateChecks++
    return ($script:VerticalStateChecks -ge 2)
}
if (-not (Install-MagoVerticals @($mockVertical))) { throw 'Vertical recém-instalado foi tratado como falha apenas pelo código de saída.' }
if (-not $script:MagoVerticalInstallHadWarning) { throw 'O retorno de erro do MSI não foi sinalizado como aviso.' }
$script:VerticalStateChecks = 0
function Test-MagoVerticalInstalled { param($Vertical) return $false }
if (Install-MagoVerticals @($mockVertical)) { throw 'Erro MSI sem produto instalado foi aceito.' }
Remove-Item Function:Get-MagoLogDirectory
Remove-Item Function:Start-Process
Remove-Item Function:Test-MagoVerticalInstalled

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
