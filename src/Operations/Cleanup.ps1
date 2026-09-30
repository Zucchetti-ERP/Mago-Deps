function Clear-TempFiles {
    Write-Phase 'Limpeza de arquivos temporários'

    Write-Step 'Reiniciando IIS...'
    try { & iisreset | Out-Null; Write-Ok 'IIS parado/reiniciado.' }
    catch { Write-Warn 'iisreset indisponível — IIS pode não estar instalado.' }

    $paths = @(
        $env:TEMP,
        'C:\Windows\Temp',
        'C:\Windows\Microsoft.NET\Framework\v2.0.50727\Temporary ASP.NET Files',
        'C:\Windows\Microsoft.NET\Framework\v4.0.30319\Temporary ASP.NET Files',
        'C:\Windows\Microsoft.NET\Framework64\v2.0.50727\Temporary ASP.NET Files',
        'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\Temporary ASP.NET Files'
    )
    foreach ($p in $paths) {
        if (-not (Test-Path $p)) { continue }
        Write-Step "Limpando: $p"
        Get-ChildItem $p -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.FullName -ine (Join-Path $env:TEMP 'Mago4-Setup')) {
                Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Write-Ok 'Arquivos temporários removidos.'

    Write-Step 'Reiniciando IIS...'
    try { & iisreset | Out-Null; Write-Ok 'IIS reiniciado.' }
    catch { Write-Warn 'iisreset indisponível.' }
}

function Get-Mago4Entries {
    $allEntries = @()
    foreach ($regPath in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        $allEntries += Get-ItemProperty $regPath -ErrorAction SilentlyContinue
    }
    return $allEntries | Where-Object {
        $_.DisplayName -match '^Mago4(?:-BR| (?:Retail|CGM|Visibility|MCM|MSO))\b' -or
        $_.DisplayName -match 'Mago Service Hub' -or
        $_.DisplayName -match 'Microarea Installer'
    }
}

function Invoke-UninstallEntry {
    param($Entry)
    if (-not $Entry.UninstallString) { Write-Fail "Sem comando de desinstalação: $($Entry.DisplayName)"; return $false }
    Write-Step "Desinstalando $($Entry.DisplayName). Aguarde; esta etapa pode demorar e o processo não está travado."
    if ($Entry.UninstallString -match 'MsiExec') {
        $guid = if ($Entry.UninstallString -match '(\{[0-9A-Fa-f\-]+\})') { $Matches[1] } else { $null }
        if (-not $guid) { Write-Fail "GUID não encontrado: $($Entry.DisplayName)"; return $false }
        $proc = Start-Process 'msiexec.exe' -ArgumentList "/x $guid /quiet /norestart" -Wait -PassThru
        if ($proc.ExitCode -in @(0, 3010, 1605)) { Write-Ok "Desinstalado: $($Entry.DisplayName)"; return $true }
        Write-Fail "$($Entry.DisplayName) — código: $($proc.ExitCode)"; return $false
    } else {
        $exePath = if ($Entry.UninstallString -match '^"([^"]+)"') { $Matches[1] }
                   else { ($Entry.UninstallString -split ' ')[0] }
        if (-not (Test-Path $exePath)) { Write-Fail "Instalador não encontrado: $exePath"; return $false }
        # WiX Burn bootstrapper: /uninstall /quiet
        $proc = Start-Process -FilePath $exePath -ArgumentList '/uninstall', '/quiet' -Wait -PassThru
        if ($proc.ExitCode -in @(0, 3010, 1605)) { Write-Ok "Desinstalado: $($Entry.DisplayName)"; return $true }
        Write-Fail "$($Entry.DisplayName) — código: $($proc.ExitCode)"; return $false
    }
}

function Invoke-LimpezaSimples {
    Write-SectionHeader 'LIMPEZA SIMPLES'
    Clear-TempFiles
    Write-Host ''
    Write-Ok 'Limpeza simples concluída!'
    Pause-Continue
}

function Invoke-DesinstalarMago4 {
    Write-SectionHeader 'DESINSTALAR MAGO4'

    $entries = Get-Mago4Entries
    if (-not $entries) {
        Write-Warn 'Nenhuma instalação do Mago4 encontrada.'
        Pause-Continue; return
    }

    Write-Host ''
    Write-Step 'Instalações encontradas:'
    $entries | ForEach-Object { Write-Host "       $($_.DisplayName)" -ForegroundColor White }
    Write-Host ''
    $c = (Read-Host '  Confirma a desinstalação? [S/N]').Trim().ToUpper()
    if ($c -ne 'S') {
        Write-Host ''; Write-Host '  Operação cancelada.' -ForegroundColor DarkGray
        Pause-Continue; return
    }
    Write-Host ''

    if (-not (Invoke-MagoUninstall -Entries $entries)) { Write-Fail 'Desinstalação interrompida após falha.'; Pause-Continue; return }

    Write-Host ''
    Write-Ok 'Desinstalação do Mago4 concluída!'
    Pause-Continue
}

function Invoke-MagoUninstall {
    param([object[]]$Entries)
    foreach ($pattern in @('^Mago4 (?:Retail|CGM|Visibility|MCM|MSO)\b', '^Mago4-BR\b', '^Mago Service Hub\b', '^Microarea Installer\b')) {
        $matching = @($Entries | Where-Object { $_.DisplayName -match $pattern })
        foreach ($entry in $matching) {
            Write-Phase $entry.DisplayName
            if (-not (Invoke-UninstallEntry -Entry $entry)) { return $false }
        }
    }
    return $true
}
