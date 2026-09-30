param([string]$Branch = 'test')

$ErrorActionPreference = 'Stop'
$previousBranch = $env:MAGO_DEPS_BRANCH
$expectedBranch = $Branch
$script:ResolvedUri = $null
$script:DownloadedUri = $null
$script:LaunchArguments = $null

function Invoke-RestMethod {
    param([string]$Uri, $Headers, [switch]$UseBasicParsing)
    $script:ResolvedUri = $Uri
    return @{ sha = ('a' * 40) }
}
function Invoke-WebRequest {
    param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing)
    $script:DownloadedUri = $Uri
}
function Start-Process {
    param([string]$FilePath, [string]$Verb, [string]$ArgumentList)
    $script:LaunchArguments = $ArgumentList
}

try {
    $env:MAGO_DEPS_BRANCH = $Branch
    Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'bootstraper.ps1') -Raw -Encoding UTF8 | Invoke-Expression
    if ($script:ResolvedUri -notlike "*/commits/$expectedBranch") { throw "Branch incorreta: $script:ResolvedUri" }
    if ($script:DownloadedUri -notlike '*/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/bootstraper.ps1') {
        throw "Download sem revisao fixa: $script:DownloadedUri"
    }
    if ($script:LaunchArguments -notlike '*-Ref aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa*') {
        throw "Revisao nao repassada na elevacao: $script:LaunchArguments"
    }
    Write-Host 'Bootstrap smoke test OK'
} finally {
    if ($null -eq $previousBranch) { Remove-Item Env:MAGO_DEPS_BRANCH -ErrorAction SilentlyContinue }
    else { $env:MAGO_DEPS_BRANCH = $previousBranch }
    $testCache = Join-Path $env:TEMP ('Mago4-Setup\' + ('a' * 40))
    if ((Test-Path -LiteralPath $testCache) -and -not @(Get-ChildItem -LiteralPath $testCache -Force).Count) {
        Remove-Item -LiteralPath $testCache -Force
    }
}
