[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

# ─── Auto-elevate ────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    $rawUrl = 'https://raw.githubusercontent.com/Zucchetti-ERP/Mago-Deps/master/bootstraper.ps1'
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"iex (irm '$rawUrl')`""
    exit
}

$Host.UI.RawUI.WindowTitle = 'Scripts Mago4 - Zucchetti Brasil'

$W = 54  # largura interna entre as bordas verticais

# ─── Helpers visuais ─────────────────────────────────────────────────────────

function Write-HBorder {
    param([string]$L, [string]$R, [string]$Fill = '═')
    Write-Host "  $L$($Fill * $W)$R" -ForegroundColor Cyan
}

function Write-EmptyRow {
    Write-Host "  ║$(' ' * $W)║" -ForegroundColor Cyan
}

function Write-CenteredRow {
    param([string]$Text, [ConsoleColor]$Color = 'Yellow')
    $pad  = [math]::Floor(($W - $Text.Length) / 2)
    $line = (' ' * $pad) + $Text + (' ' * ($W - $pad - $Text.Length))
    Write-Host '  ║' -NoNewline -ForegroundColor Cyan
    Write-Host $line  -NoNewline -ForegroundColor $Color
    Write-Host '║'   -ForegroundColor Cyan
}

function Write-MenuRow {
    param(
        [string]$Key,
        [string]$Label,
        [ConsoleColor]$KeyColor   = 'Green',
        [ConsoleColor]$LabelColor = 'White'
    )
    $spaces = ' ' * ($W - 5 - $Key.Length - $Label.Length)
    Write-Host '  ║  [' -NoNewline -ForegroundColor Cyan
    Write-Host $Key      -NoNewline -ForegroundColor $KeyColor
    Write-Host '] '      -NoNewline -ForegroundColor DarkGray
    Write-Host "$Label$spaces" -NoNewline -ForegroundColor $LabelColor
    Write-Host '║'       -ForegroundColor Cyan
}

function Write-SectionHeader {
    param([string]$Title)
    Clear-Host
    Write-Host ''
    Write-HBorder '╔' '╗'
    Write-CenteredRow $Title
    Write-HBorder '╚' '╝'
    Write-Host ''
}

function Pause-Continue {
    Write-Host ''
    Write-Host '  Pressione qualquer tecla para voltar ao menu...' -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
}

function Write-Step {
    param([string]$Message)
    Write-Host '  » ' -NoNewline -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor White
}

function Write-Ok {
    param([string]$Message)
    Write-Host '  ✔ ' -NoNewline -ForegroundColor Green
    Write-Host $Message -ForegroundColor White
}

function Write-Fail {
    param([string]$Message)
    Write-Host '  ✘ ' -NoNewline -ForegroundColor Red
    Write-Host $Message -ForegroundColor White
}

function Write-Warn {
    param([string]$Message)
    Write-Host '  ! ' -NoNewline -ForegroundColor Yellow
    Write-Host $Message -ForegroundColor White
}

function Write-WarningRow {
    param([string]$Text)
    $pad = ' ' * ($W - 6 - $Text.Length)
    Write-Host '  ║  [' -NoNewline -ForegroundColor Cyan
    Write-Host '!'       -NoNewline -ForegroundColor Red
    Write-Host "] $Text$pad" -NoNewline -ForegroundColor Yellow
    Write-Host '║'       -ForegroundColor Cyan
}

function Write-Phase {
    param([string]$Title)
    Write-Host ''
    Write-Host "  ─── $Title" -ForegroundColor Cyan
    Write-Host ''
}

function Write-DiagLine {
    param(
        [string]$Label,
        [string]$State,
        [string]$Detail = '',
        [string]$Fix    = ''
    )
    $pad = ' ' * [math]::Max(1, 26 - $Label.Length)
    switch ($State) {
        'ok'   {
            Write-Host '  ✔  ' -NoNewline -ForegroundColor Green
            Write-Host "$Label$pad" -NoNewline -ForegroundColor White
            Write-Host $Detail -ForegroundColor DarkGray
        }
        'fail' {
            Write-Host '  ✘  ' -NoNewline -ForegroundColor Red
            Write-Host "$Label$pad" -NoNewline -ForegroundColor DarkGray
            Write-Host $Detail -ForegroundColor DarkGray
            if ($Fix) {
                Write-Host '       → ' -NoNewline -ForegroundColor DarkGray
                Write-Host $Fix -ForegroundColor Yellow
            }
        }
        'warn' {
            Write-Host '  !  ' -NoNewline -ForegroundColor Yellow
            Write-Host "$Label$pad" -NoNewline -ForegroundColor White
            Write-Host $Detail -ForegroundColor DarkGray
            if ($Fix) {
                Write-Host '       → ' -NoNewline -ForegroundColor DarkGray
                Write-Host $Fix -ForegroundColor Yellow
            }
        }
        'info' {
            Write-Host '  ·  ' -NoNewline -ForegroundColor DarkGray
            Write-Host "$Label$pad" -NoNewline -ForegroundColor DarkGray
            Write-Host $Detail -ForegroundColor DarkGray
        }
    }
}

function Test-HttpEndpoint {
    param([string]$Url, [int[]]$OkCodes = @(200))
    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        $code = [int]$resp.StatusCode
        return @{ Code = $code; Ok = ($code -in $OkCodes) }
    } catch {
        $inner = $_.Exception
        if ($inner.InnerException) { $inner = $inner.InnerException }
        if ($inner -is [System.Net.WebException] -and $null -ne $inner.Response) {
            $code = [int]$inner.Response.StatusCode
            return @{ Code = $code; Ok = ($code -in $OkCodes) }
        }
        return @{ Code = -1; Ok = $false }
    }
}

# ─── Manifest e obtenção de dependências ─────────────────────────────────────

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:Manifest    = $null
$script:ManifestUrl = 'https://raw.githubusercontent.com/Zucchetti-ERP/Mago-Deps/master/manifest.json'
$script:DownloadDir = Join-Path $env:TEMP 'Mago4-Setup'

function Get-Manifest {
    if ($script:Manifest) { return $script:Manifest }
    try {
        Write-Step 'Carregando manifest de dependências...'
        $script:Manifest = Invoke-RestMethod -Uri $script:ManifestUrl -UseBasicParsing
        return $script:Manifest
    } catch {
        Write-Fail "Não foi possível carregar o manifest: $_"
        return $null
    }
}

function Resolve-DotNetUrl {
    param(
        [string]$Channel,
        [string]$Component
    )
    try {
        Write-Step "Consultando releases do .NET $Channel..."
        $feed = $null
        foreach ($feedUrl in @(
            "https://builds.dotnet.microsoft.com/dotnet/release-metadata/$Channel/releases.json",
            "https://dotnetcli.azureedge.net/dotnet/release-metadata/$Channel/releases.json"
        )) {
            try { $feed = Invoke-RestMethod -Uri $feedUrl -UseBasicParsing -ErrorAction Stop; break } catch {}
        }
        if (-not $feed) { throw "Feed inacessível em todos os endpoints." }
        $latest = $feed.releases |
            Where-Object { $_.'release-version' -eq $feed.'latest-release' } |
            Select-Object -First 1

        switch ($Component) {
            'sdk-win-x64' {
                return ($latest.sdk.files |
                    Where-Object { $_.rid -eq 'win-x64' -and $_.name -like '*.exe' } |
                    Select-Object -First 1).url
            }
            'hosting-bundle' {
                return ($latest.'aspnetcore-runtime'.files |
                    Where-Object { $_.name -like 'dotnet-hosting*win.exe' } |
                    Select-Object -First 1).url
            }
        }
    } catch {
        Write-Fail "Falha ao consultar feed do .NET $Channel`: $_"
    }
    return $null
}

function Get-Dependency {
    param([string]$Id)

    $manifest = Get-Manifest
    if (-not $manifest) { return $null }

    $dep = $manifest.dependencies | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $dep) {
        Write-Fail "Dependência '$Id' não encontrada no manifest."
        return $null
    }

    if (-not (Test-Path $script:DownloadDir)) {
        New-Item -ItemType Directory -Path $script:DownloadDir -Force | Out-Null
    }

    $localPath = Join-Path $script:DownloadDir $dep.filename

    if (Test-Path $localPath) {
        Write-Ok "$($dep.name) já disponível em cache."
        return $localPath
    }

    $url = switch ($dep.source) {
        'direct'       { $dep.url }
        'repo'         { "$($manifest.baseRepoUrl)/Deps/$($dep.filename)" }
        'dotnet-feed'  { Resolve-DotNetUrl -Channel $dep.channel -Component $dep.component }
        default        { $null }
    }

    if (-not $url) {
        Write-Fail "Não foi possível resolver a URL de '$($dep.name)'."
        return $null
    }

    Write-Step "Baixando $($dep.name)..."
    $prev = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $url -OutFile $localPath -UseBasicParsing
        $sizeMB = [math]::Round((Get-Item $localPath).Length / 1MB, 1)
        Write-Ok "Download concluído: $($dep.name) ($sizeMB MB)"
        return $localPath
    } catch {
        Write-Fail "Falha no download de $($dep.name): $_"
        if (Test-Path $localPath) { Remove-Item $localPath -Force }
        return $null
    } finally {
        $ProgressPreference = $prev
    }
}

# ─── Menu principal ──────────────────────────────────────────────────────────

function Show-Menu {
    Clear-Host
    Write-Host ''
    Write-HBorder '╔' '╗'
    Write-CenteredRow 'SCRIPTS MAGO4' 'Yellow'
    Write-CenteredRow 'Zucchetti Brasil' 'DarkGray'
    Write-HBorder '╠' '╣'
    Write-EmptyRow
    Write-MenuRow '1' 'Instalar dependências Mago4'
    Write-MenuRow '2' 'Instalar/Corrigir RabbitMQ'
    Write-MenuRow '3' 'Verificação de dependências'
    Write-MenuRow '4' 'Limpar ambiente'
    Write-MenuRow '5' 'Reparar erro .NET Core'
    Write-MenuRow '6' 'Diagnóstico do sistema'
    Write-EmptyRow
    Write-HBorder '╠' '╣' '─'
    Write-MenuRow '0' 'Sair' 'Red'
    Write-HBorder '╚' '╝'
    Write-Host ''
}

# ─── Helpers de instalação ───────────────────────────────────────────────────

function Get-IsWindowsServer {
    $caption = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
    if (-not $caption) {
        $caption = (Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
    }
    return $caption -match 'Server'
}

function Enable-IISFeatures {
    Write-Phase 'Internet Information Services (IIS)'
    if (Get-IsWindowsServer) {
        $features = @(
            'Web-Server', 'Web-WebServer', 'Web-Common-Http',
            'Web-Static-Content', 'Web-Default-Doc', 'Web-Dir-Browsing',
            'Web-Http-Errors', 'Web-Http-Redirect', 'Web-App-Dev',
            'Web-Asp-Net', 'Web-Asp-Net45', 'Web-Net-Ext', 'Web-Net-Ext45',
            'Web-ISAPI-Ext', 'Web-ISAPI-Filter', 'Web-Includes',
            'Web-Health', 'Web-Http-Logging', 'Web-Log-Libraries',
            'Web-Request-Monitor', 'Web-Http-Tracing', 'Web-Security',
            'Web-Basic-Auth', 'Web-Windows-Auth', 'Web-Digest-Auth',
            'Web-Client-Auth', 'Web-Cert-Auth', 'Web-IP-Security',
            'Web-URL-Auth', 'Web-Filtering', 'Web-Performance',
            'Web-Stat-Compression', 'Web-Dyn-Compression',
            'Web-Mgmt-Tools', 'Web-Mgmt-Console', 'Web-Scripting-Tools',
            'Web-Mgmt-Service', 'Web-AppInit', 'Web-WebSockets',
            'Web-CGI', 'Web-ASP', 'Web-CertProvider'
        )
        Write-Step "Habilitando $($features.Count) funcionalidades IIS (Windows Server)..."
        try {
            $result = Install-WindowsFeature -Name $features -IncludeManagementTools
            if ($result.Success) {
                Write-Ok 'Funcionalidades IIS habilitadas com sucesso.'
                if ($result.RestartNeeded -ne 'No') {
                    Write-Warn 'Reinicialização necessária para concluir a instalação.'
                }
            } else {
                Write-Fail 'Falha ao habilitar algumas funcionalidades IIS.'
            }
        } catch {
            Write-Fail "Erro ao habilitar funcionalidades IIS: $_"
        }
    } else {
        # NetFx4Extended-ASPNET45 deve vir primeiro — IIS-NetFxExtensibility45 e
        # IIS-ASPNET45 dependem dele e falham silenciosamente se não estiver ativo.
        # IIS-NetFxExtensibility (3.5) e IIS-ASPNET (3.5) foram removidos: precisam
        # de .NET 3.5, ausente no LTSC e desnecessário para o Mago4.
        $features = @(
            'NetFx4Extended-ASPNET45',
            'IIS-WebServerRole', 'IIS-WebServer', 'IIS-CommonHttpFeatures',
            'IIS-StaticContent', 'IIS-DefaultDocument', 'IIS-DirectoryBrowsing',
            'IIS-HttpErrors', 'IIS-HttpRedirect', 'IIS-ApplicationDevelopment',
            'IIS-NetFxExtensibility45', 'IIS-ASPNET45',
            'IIS-ISAPIExtensions', 'IIS-ISAPIFilter', 'IIS-ServerSideIncludes',
            'IIS-HealthAndDiagnostics', 'IIS-HttpLogging', 'IIS-LoggingLibraries',
            'IIS-RequestMonitor', 'IIS-HttpTracing', 'IIS-Security',
            'IIS-BasicAuthentication', 'IIS-WindowsAuthentication',
            'IIS-DigestAuthentication', 'IIS-ClientCertificateMappingAuthentication',
            'IIS-IISCertificateMappingAuthentication', 'IIS-URLAuthorization',
            'IIS-RequestFiltering', 'IIS-IPSecurity', 'IIS-Performance',
            'IIS-HttpCompressionStatic', 'IIS-HttpCompressionDynamic',
            'IIS-WebServerManagementTools', 'IIS-ManagementConsole',
            'IIS-ManagementScriptingTools', 'IIS-ManagementService',
            'IIS-ApplicationInit', 'IIS-WebSockets', 'IIS-CertProvider'
        )
        Write-Step "Habilitando $($features.Count) funcionalidades IIS (Windows Desktop)..."
        $failCount = 0
        $currentFeats = Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue
        foreach ($feat in $features) {
            try {
                $cur = ($currentFeats | Where-Object { $_.FeatureName -eq $feat }).State
                if ($cur -in @('Enabled','EnablePending')) { continue }
                # -All habilita automaticamente features pai (ex: NetFx4-AdvSrvs para NetFx4Extended-ASPNET45)
                Enable-WindowsOptionalFeature -Online -FeatureName $feat -All -NoRestart -ErrorAction Stop | Out-Null
            } catch {
                Write-Warn "Não habilitado: $feat — $($_.Exception.Message -replace '\r?\n',' ')"
                $failCount++
            }
        }
        if ($failCount -eq 0) {
            Write-Ok 'Funcionalidades IIS habilitadas com sucesso.'
        } else {
            Write-Warn "$failCount funcionalidade(s) não puderam ser habilitadas."
        }

        # Fallback para edições (ex: IoT LTSC) onde IIS-ASPNET45 não existe como optional feature.
        # aspnet_regiis.exe -i configura IIS diretamente sem precisar da optional feature.
        $aspEnabled = ($currentFeats | Where-Object { $_.FeatureName -eq 'IIS-ASPNET45' }).State -in @('Enabled','EnablePending')
        if (-not $aspEnabled) {
            $aspReg = "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\aspnet_regiis.exe"
            if (Test-Path $aspReg) {
                Write-Step 'Registrando ASP.NET 4.x no IIS (fallback IoT/LTSC)...'
                $p = Start-Process $aspReg -ArgumentList '-i' -PassThru -WindowStyle Hidden
                $p.WaitForExit(30000); if (-not $p.HasExited) { try { $p.Kill() } catch {} }
                if ($p.ExitCode -eq 0) { Write-Ok 'ASP.NET 4.x registrado no IIS.' }
                else { Write-Warn "aspnet_regiis saiu com código $($p.ExitCode)." }
            }
        }
    }
}

function Enable-Mago4WindowsFeatures {
    Write-Phase 'ASP.NET 4.8 e WCF Services'
    if (Get-IsWindowsServer) {
        $features = @(
            'NET-Framework-45-ASPNET',
            'NET-WCF-HTTP-Activation45', 'NET-WCF-TCP-Activation45',
            'NET-WCF-Pipe-Activation45', 'NET-WCF-MSMQ-Activation45',
            'NET-WCF-TCP-PortSharing45'
        )
        Write-Step 'Habilitando ASP.NET 4.8 e WCF Services (Windows Server)...'
        try {
            $result = Install-WindowsFeature -Name $features
            if ($result.Success) { Write-Ok 'ASP.NET 4.8 e WCF Services habilitados.' }
            else { Write-Fail 'Falha ao habilitar ASP.NET/WCF.' }
        } catch {
            Write-Fail "Erro: $_"
        }
    } else {
        $features = @(
            'NetFx4Extended-ASPNET45',
            'WCF-Services45', 'WCF-HTTP-Activation45', 'WCF-TCP-Activation45',
            'WCF-Pipe-Activation45', 'WCF-MSMQ-Activation45', 'WCF-TCP-PortSharing45'
        )
        Write-Step 'Habilitando ASP.NET 4.8 e WCF Services (Windows Desktop)...'
        $failCount = 0
        $currentFeats = Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue
        foreach ($feat in $features) {
            try {
                $cur = ($currentFeats | Where-Object { $_.FeatureName -eq $feat }).State
                if ($cur -in @('Enabled','EnablePending')) { continue }
                Enable-WindowsOptionalFeature -Online -FeatureName $feat -All -NoRestart -ErrorAction Stop | Out-Null
            } catch {
                Write-Warn "Não habilitado: $feat — $($_.Exception.Message -replace '\r?\n',' ')"
                $failCount++
            }
        }
        if ($failCount -eq 0) { Write-Ok 'ASP.NET 4.8 e WCF Services habilitados.' }
        else { Write-Warn "$failCount funcionalidade(s) não puderam ser habilitadas." }
    }
}

function Install-VCRedist {
    Write-Phase 'Visual C++ Redistributable 2015+'
    foreach ($id in @('vcredist-x86', 'vcredist-x64')) {
        $path = Get-Dependency -Id $id
        if (-not $path) { continue }
        $dep = (Get-Manifest).dependencies | Where-Object { $_.id -eq $id } | Select-Object -First 1
        Write-Step "Instalando $($dep.name)..."
        $proc = Start-Process -FilePath $path -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
        switch ($proc.ExitCode) {
            0       { Write-Ok "$($dep.name) instalado." }
            3010    { Write-Ok "$($dep.name) instalado (reinicialização pendente)." }
            1638    { Write-Ok "$($dep.name) já está atualizado." }
            default { Write-Fail "$($dep.name) falhou. Código: $($proc.ExitCode)" }
        }
    }
}

function Install-DotNet10 {
    Write-Phase '.NET 10'
    foreach ($id in @('dotnet10-sdk', 'dotnet10-hosting')) {
        $path = Get-Dependency -Id $id
        if (-not $path) { continue }
        $dep = (Get-Manifest).dependencies | Where-Object { $_.id -eq $id } | Select-Object -First 1
        Write-Step "Instalando $($dep.name)..."
        $proc = Start-Process -FilePath $path -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
        switch ($proc.ExitCode) {
            0       { Write-Ok "$($dep.name) instalado." }
            3010    { Write-Ok "$($dep.name) instalado (reinicialização pendente)." }
            1638    { Write-Ok "$($dep.name) já está atualizado." }
            default { Write-Fail "$($dep.name) falhou. Código: $($proc.ExitCode)" }
        }
    }
}

function Install-NetFx48DevPack {
    Write-Phase '.NET Framework 4.8 Developer Pack'
    $path = Get-Dependency -Id 'netfx48-devpack'
    if (-not $path) { return }
    Write-Step 'Instalando .NET Framework 4.8 Developer Pack...'
    $proc = Start-Process -FilePath $path -ArgumentList '/q', '/norestart' -Wait -PassThru
    switch ($proc.ExitCode) {
        0       { Write-Ok '.NET Framework 4.8 Developer Pack instalado.' }
        3010    { Write-Ok '.NET Framework 4.8 Developer Pack instalado (reinicialização pendente).' }
        1638    { Write-Ok '.NET Framework 4.8 Developer Pack já está instalado.' }
        default { Write-Fail ".NET Framework 4.8 Developer Pack falhou. Código: $($proc.ExitCode)" }
    }
}

function Install-IISRewrite {
    Write-Phase 'IIS URL Rewrite Module'
    $path = Get-Dependency -Id 'iis-rewrite-x64'
    if (-not $path) { return }
    $dep = (Get-Manifest).dependencies | Where-Object { $_.id -eq 'iis-rewrite-x64' } | Select-Object -First 1
    Write-Step "Instalando $($dep.name)..."
    $proc = Start-Process -FilePath 'msiexec.exe' `
        -ArgumentList '/i', "`"$path`"", '/quiet', '/norestart' -Wait -PassThru
    switch ($proc.ExitCode) {
        0       { Write-Ok "$($dep.name) instalado." }
        3010    { Write-Ok "$($dep.name) instalado (reinicialização pendente)." }
        1638    { Write-Ok "$($dep.name) já está instalado." }
        default { Write-Fail "$($dep.name) falhou. Código: $($proc.ExitCode)" }
    }
}

function Clear-ErlangRabbitMQ {
    Write-Phase 'Limpeza de instalações anteriores'

    # Mata processos Erlang/RabbitMQ antes de qualquer operação
    Get-Process -Name 'erl', 'epmd', 'beam' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    # Para e remove serviço se registrado
    if (Get-Service 'RabbitMQ' -ErrorAction SilentlyContinue) {
        Write-Step 'Parando serviço RabbitMQ...'
        $p = Start-Process 'sc.exe' -ArgumentList 'stop RabbitMQ'   -PassThru -WindowStyle Hidden
        $p.WaitForExit(8000); if (-not $p.HasExited) { try { $p.Kill() } catch {} }
        $p = Start-Process 'sc.exe' -ArgumentList 'delete RabbitMQ' -PassThru -WindowStyle Hidden
        $p.WaitForExit(8000); if (-not $p.HasExited) { try { $p.Kill() } catch {} }
        Start-Sleep -Seconds 1
    }

    # Desinstala RabbitMQ e Erlang via entradas do registro
    $allEntries = @()
    foreach ($regPath in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        $allEntries += Get-ItemProperty $regPath -ErrorAction SilentlyContinue
    }
    foreach ($pattern in @('RabbitMQ', 'Erlang')) {
        $allEntries | Where-Object { $_.DisplayName -match $pattern } | ForEach-Object {
            if (-not $_.UninstallString) { return }
            $exePath = if ($_.UninstallString -match '^"([^"]+)"') { $Matches[1] }
                       else { ($_.UninstallString -split ' ')[0] }
            if (Test-Path $exePath) {
                Write-Step "Desinstalando $($_.DisplayName)..."
                $p = Start-Process -FilePath $exePath -ArgumentList '/S' -PassThru -ErrorAction SilentlyContinue
                if ($p) { $p.WaitForExit(40000); if (-not $p.HasExited) { try { $p.Kill() } catch {} } }
                Write-Ok "$($_.DisplayName) desinstalado."
            }
        }
    }

    # Remove diretórios residuais do Program Files
    Write-Step 'Removendo diretórios residuais...'
    $rmqDir = Join-Path $env:ProgramFiles 'RabbitMQ Server'
    if (Test-Path $rmqDir) {
        Remove-Item $rmqDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $rmqDir) { Write-Warn 'Não foi possível remover completamente: RabbitMQ Server' }
        else { Write-Ok 'Pasta RabbitMQ Server removida.' }
    }
    Get-ChildItem $env:ProgramFiles -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(erl|Erlang)' } | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $_.FullName) { Write-Warn "Não foi possível remover: $($_.Name)" }
        else { Write-Ok "Pasta $($_.Name) removida." }
    }

    # Remove dados de aplicação do RabbitMQ
    $rmqAppData = Join-Path $env:APPDATA 'RabbitMQ'
    if (Test-Path $rmqAppData) {
        Remove-Item $rmqAppData -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $rmqAppData) { Write-Warn 'Não foi possível remover AppData\RabbitMQ.' }
        else { Write-Ok 'Dados AppData\RabbitMQ removidos.' }
    }
}

function Install-ErlangAndRabbitMQ {
    Clear-ErlangRabbitMQ

    # ── Erlang ──
    Write-Phase 'Erlang OTP'
    $erlPath = Get-Dependency -Id 'erlang'
    if (-not $erlPath) { return }

    Write-Step 'Instalando Erlang 27.3.4.13...'
    $proc = Start-Process -FilePath $erlPath -ArgumentList '/S' -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Fail "Falha na instalação do Erlang. Código: $($proc.ExitCode)"; return
    }
    Write-Ok 'Erlang instalado.'

    $erlDir = Get-ChildItem $env:ProgramFiles -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match '^(erl|Erlang)' } |
              Sort-Object Name -Descending | Select-Object -First 1
    if ($erlDir) {
        [System.Environment]::SetEnvironmentVariable('ERLANG_HOME', $erlDir.FullName, 'Machine')
        $env:ERLANG_HOME = $erlDir.FullName
        Write-Ok "ERLANG_HOME = $($erlDir.FullName)"
    } else {
        Write-Warn 'Diretório do Erlang não encontrado. Defina ERLANG_HOME manualmente.'
    }

    # ── RabbitMQ ──
    Write-Phase 'RabbitMQ 3.13.7'
    $rmqPath = Get-Dependency -Id 'rabbitmq'
    if (-not $rmqPath) { return }

    Write-Step 'Instalando RabbitMQ 3.13.7...'
    $rmqBase = Join-Path $env:ProgramFiles 'RabbitMQ Server'
    # /NOSERVICEINSTALL impede que o próprio instalador registre/inicie o serviço via "net start"
    # — é essa etapa interna que travava o instalador silenciosamente. O serviço é registrado e
    # iniciado por este script logo abaixo, de forma controlada e com timeouts próprios.
    $proc = Start-Process -FilePath $rmqPath -ArgumentList '/S', '/NOSERVICEINSTALL' -PassThru
    $proc.WaitForExit(120000)
    if (-not $proc.HasExited) {
        Write-Fail 'Instalador do RabbitMQ excedeu o tempo limite.'
        try { $proc.Kill() } catch {}
        return
    }
    if ($proc.ExitCode -ne 0) {
        Write-Fail "Falha na instalação do RabbitMQ. Código: $($proc.ExitCode)"; return
    }
    if (-not (Get-ChildItem $rmqBase -Directory -Filter 'rabbitmq_server-*' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        Write-Fail 'Arquivos do RabbitMQ não encontrados após instalação.'; return
    }
    Write-Ok 'RabbitMQ instalado.'

    $sbinDir = Get-ChildItem $rmqBase -Directory -Filter 'rabbitmq_server-*' -ErrorAction SilentlyContinue |
               Sort-Object Name -Descending | Select-Object -First 1
    if (-not $sbinDir) {
        Write-Fail 'Diretório do RabbitMQ não encontrado após instalação.'; return
    }
    $sbin = Join-Path $sbinDir.FullName 'sbin'

    # Mata processos Erlang residuais do installer antes de tocar no serviço
    Get-Process -Name 'erl', 'epmd', 'beam' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    Write-Step 'Reconfigurando serviço RabbitMQ...'
    # sc.exe stop/delete é direto e não comunica com o broker — sem risco de trave
    $p = Start-Process 'sc.exe' -ArgumentList 'stop RabbitMQ'   -PassThru -WindowStyle Hidden
    $p.WaitForExit(8000); if (-not $p.HasExited) { try { $p.Kill() } catch {} }
    $p = Start-Process 'sc.exe' -ArgumentList 'delete RabbitMQ' -PassThru -WindowStyle Hidden
    $p.WaitForExit(8000); if (-not $p.HasExited) { try { $p.Kill() } catch {} }
    Start-Sleep -Seconds 1

    $p = Start-Process 'cmd.exe' -ArgumentList "/c `"$sbin\rabbitmq-service.bat`" install" -PassThru -WindowStyle Hidden
    $p.WaitForExit(20000); if (-not $p.HasExited) { try { $p.Kill() } catch {} }

    Write-Step 'Habilitando Management Plugin...'
    $p = Start-Process 'cmd.exe' -ArgumentList "/c `"$sbin\rabbitmq-plugins.bat`" enable --offline rabbitmq_management" -PassThru -WindowStyle Hidden
    $p.WaitForExit(30000); if (-not $p.HasExited) { try { $p.Kill() } catch {} }

    Write-Step 'Iniciando serviço RabbitMQ...'
    Start-Service 'RabbitMQ' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    $svc = Get-Service 'RabbitMQ' -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Ok 'Serviço RabbitMQ iniciado com sucesso.'
    } else {
        Write-Warn 'Serviço RabbitMQ pode não ter iniciado. Verifique manualmente.'
    }
}

# ─── Opção 1 — Subopções ─────────────────────────────────────────────────────

function Invoke-DepCompleta {
    Write-SectionHeader 'INSTALAÇÃO COMPLETA (IIS + MAGO4 + MSH)'
    Write-Host '  FASE 1/3 — IIS' -ForegroundColor Yellow
    Enable-IISFeatures
    Write-Host ''
    Write-Host '  FASE 2/3 — MAGO4' -ForegroundColor Yellow
    Install-VCRedist
    Install-NetFx48DevPack
    Install-DotNet10
    Enable-Mago4WindowsFeatures
    Write-Host ''
    Write-Host '  FASE 3/3 — MSH' -ForegroundColor Yellow
    Install-IISRewrite
    Install-ErlangAndRabbitMQ
    Write-Host ''
    Write-Ok 'Instalação completa concluída!'
    Pause-Continue
}

function Invoke-DepMago4 {
    Write-SectionHeader 'INSTALAÇÃO DE DEPENDÊNCIAS MAGO4'
    Install-VCRedist
    Install-NetFx48DevPack
    Install-DotNet10
    Enable-Mago4WindowsFeatures
    Write-Host ''
    Write-Ok 'Dependências Mago4 instaladas!'
    Pause-Continue
}

function Invoke-DepMSH {
    Write-SectionHeader 'INSTALAÇÃO DE DEPENDÊNCIAS MSH'
    Install-IISRewrite
    Install-ErlangAndRabbitMQ
    Write-Host ''
    Write-Ok 'Dependências MSH instaladas!'
    Pause-Continue
}

function Invoke-DepBasica {
    Write-SectionHeader 'INSTALAÇÃO BÁSICA PÓS-ATUALIZAÇÃO'
    Install-VCRedist
    Install-DotNet10
    Write-Host ''
    Write-Ok 'Instalação básica concluída!'
    Pause-Continue
}

function Invoke-DepIIS {
    Write-SectionHeader 'INSTALAÇÃO IIS'
    Enable-IISFeatures
    Write-Host ''
    Write-Ok 'Configuração IIS concluída!'
    Pause-Continue
}

# ─── Opção 1 — Instalar dependência individual ──────────────────────────────

function Invoke-DepIndividual {
    $oldW = $script:W
    $script:W = 64
    try {
        $running = $true
        while ($running) {
            Clear-Host
            Write-Host ''
            Write-HBorder '╔' '╗'
            Write-CenteredRow 'INSTALAR DEPENDÊNCIA INDIVIDUAL' 'Yellow'
            Write-HBorder '╠' '╣'
            Write-EmptyRow
            Write-MenuRow '1' 'VC++ Redist x86'
            Write-MenuRow '2' 'VC++ Redist x64'
            Write-MenuRow '3' '.NET 10 SDK'
            Write-MenuRow '4' '.NET 10 Hosting Bundle'
            Write-MenuRow '5' '.NET Framework 4.8 Developer Pack'
            Write-MenuRow '6' 'IIS URL Rewrite x64'
            Write-MenuRow '7' 'Habilitar Features IIS'
            Write-EmptyRow
            Write-HBorder '╠' '╣' '─'
            Write-MenuRow '0' 'Voltar' 'Red'
            Write-HBorder '╚' '╝'
            Write-Host ''

            $choice = (Read-Host '  Opção').Trim()
            switch ($choice) {
                '1' {
                    Write-SectionHeader 'VC++ REDIST X86'
                    $path = Get-Dependency -Id 'vcredist-x86'
                    if ($path) {
                        Write-Step 'Instalando Visual C++ Redist 2015+ x86...'
                        $proc = Start-Process -FilePath $path -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
                        switch ($proc.ExitCode) {
                            0    { Write-Ok 'VC++ Redist x86 instalado.' }
                            3010 { Write-Ok 'VC++ Redist x86 instalado (reinicialização pendente).' }
                            1638 { Write-Ok 'VC++ Redist x86 já está atualizado.' }
                            default { Write-Fail "Falhou. Código: $($proc.ExitCode)" }
                        }
                    }
                    Pause-Continue; $running = $false
                }
                '2' {
                    Write-SectionHeader 'VC++ REDIST X64'
                    $path = Get-Dependency -Id 'vcredist-x64'
                    if ($path) {
                        Write-Step 'Instalando Visual C++ Redist 2015+ x64...'
                        $proc = Start-Process -FilePath $path -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
                        switch ($proc.ExitCode) {
                            0    { Write-Ok 'VC++ Redist x64 instalado.' }
                            3010 { Write-Ok 'VC++ Redist x64 instalado (reinicialização pendente).' }
                            1638 { Write-Ok 'VC++ Redist x64 já está atualizado.' }
                            default { Write-Fail "Falhou. Código: $($proc.ExitCode)" }
                        }
                    }
                    Pause-Continue; $running = $false
                }
                '3' {
                    Write-SectionHeader '.NET 10 SDK'
                    $path = Get-Dependency -Id 'dotnet10-sdk'
                    if ($path) {
                        Write-Step 'Instalando .NET 10 SDK...'
                        $proc = Start-Process -FilePath $path -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
                        switch ($proc.ExitCode) {
                            0    { Write-Ok '.NET 10 SDK instalado.' }
                            3010 { Write-Ok '.NET 10 SDK instalado (reinicialização pendente).' }
                            1638 { Write-Ok '.NET 10 SDK já está atualizado.' }
                            default { Write-Fail "Falhou. Código: $($proc.ExitCode)" }
                        }
                    }
                    Pause-Continue; $running = $false
                }
                '4' {
                    Write-SectionHeader '.NET 10 HOSTING BUNDLE'
                    $path = Get-Dependency -Id 'dotnet10-hosting'
                    if ($path) {
                        Write-Step 'Instalando .NET 10 Hosting Bundle...'
                        $proc = Start-Process -FilePath $path -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
                        switch ($proc.ExitCode) {
                            0    { Write-Ok '.NET 10 Hosting Bundle instalado.' }
                            3010 { Write-Ok '.NET 10 Hosting Bundle instalado (reinicialização pendente).' }
                            1638 { Write-Ok '.NET 10 Hosting Bundle já está atualizado.' }
                            default { Write-Fail "Falhou. Código: $($proc.ExitCode)" }
                        }
                    }
                    Pause-Continue; $running = $false
                }
                '5' {
                    Write-SectionHeader '.NET FRAMEWORK 4.8 DEVELOPER PACK'
                    $path = Get-Dependency -Id 'netfx48-devpack'
                    if ($path) {
                        Write-Step 'Instalando .NET Framework 4.8 Developer Pack...'
                        $proc = Start-Process -FilePath $path -ArgumentList '/q', '/norestart' -Wait -PassThru
                        switch ($proc.ExitCode) {
                            0    { Write-Ok '.NET Framework 4.8 Developer Pack instalado.' }
                            3010 { Write-Ok '.NET Framework 4.8 Developer Pack instalado (reinicialização pendente).' }
                            1638 { Write-Ok '.NET Framework 4.8 Developer Pack já está instalado.' }
                            default { Write-Fail "Falhou. Código: $($proc.ExitCode)" }
                        }
                    }
                    Pause-Continue; $running = $false
                }
                '6' {
                    Write-SectionHeader 'IIS URL REWRITE X64'
                    $path = Get-Dependency -Id 'iis-rewrite-x64'
                    if ($path) {
                        Write-Step 'Instalando IIS URL Rewrite x64...'
                        $proc = Start-Process 'msiexec.exe' -ArgumentList '/i', "`"$path`"", '/quiet', '/norestart' -Wait -PassThru
                        switch ($proc.ExitCode) {
                            0    { Write-Ok 'IIS URL Rewrite x64 instalado.' }
                            3010 { Write-Ok 'IIS URL Rewrite x64 instalado (reinicialização pendente).' }
                            1638 { Write-Ok 'IIS URL Rewrite x64 já está instalado.' }
                            default { Write-Fail "Falhou. Código: $($proc.ExitCode)" }
                        }
                    }
                    Pause-Continue; $running = $false
                }
                '7' {
                    Write-SectionHeader 'HABILITAR FEATURES IIS'
                    Enable-IISFeatures
                    Enable-Mago4WindowsFeatures
                    Write-Host ''
                    Write-Ok 'Funcionalidades IIS habilitadas!'
                    Pause-Continue; $running = $false
                }
                '0' { $running = $false }
                default {
                    Write-Host ''
                    Write-Host '  Opção inválida. Tente novamente.' -ForegroundColor Red
                    Start-Sleep -Milliseconds 700
                }
            }
        }
    } finally {
        $script:W = $oldW
    }
}

# ─── Opção 1 — Instalar dependências Mago4 ──────────────────────────────────

function Invoke-InstalarDeps {
    $oldW = $script:W
    $script:W = 64
    try {
        $running = $true
        while ($running) {
            Clear-Host
            Write-Host ''
            Write-HBorder '╔' '╗'
            Write-CenteredRow 'INSTALAR DEPENDÊNCIAS MAGO4' 'Yellow'
            Write-HBorder '╠' '╣'
            Write-EmptyRow
            Write-MenuRow '1' 'Instalação de dependências completa (IIS + Mago4 + MSH)'
            Write-MenuRow '2' 'Instalação de dependências Mago4'
            Write-MenuRow '3' 'Instalação de dependências MSH'
            Write-MenuRow '4' 'Instalação básica pós-atualização'
            Write-MenuRow '5' 'Instalação IIS'
            Write-MenuRow '6' 'Instalar dependência individual'
            Write-EmptyRow
            Write-WarningRow 'Para as opções 1 e 2 o Mago4 não deve estar instalado'
            Write-HBorder '╠' '╣' '─'
            Write-MenuRow '0' 'Voltar' 'Red'
            Write-HBorder '╚' '╝'
            Write-Host ''

            $choice = (Read-Host '  Opção').Trim()
            switch ($choice) {
                '1' { Invoke-DepCompleta    }
                '2' { Invoke-DepMago4       }
                '3' { Invoke-DepMSH         }
                '4' { Invoke-DepBasica      }
                '5' { Invoke-DepIIS         }
                '6' { Invoke-DepIndividual  }
                '0' { $running = $false     }
                default {
                    Write-Host ''
                    Write-Host '  Opção inválida. Tente novamente.' -ForegroundColor Red
                    Start-Sleep -Milliseconds 700
                }
            }
        }
    } finally {
        $script:W = $oldW
    }
}

# ─── Opção 2 — Instalar/Corrigir RabbitMQ ───────────────────────────────────

function Invoke-RabbitMQ {
    Write-SectionHeader 'INSTALAR/CORRIGIR RABBITMQ'
    Install-ErlangAndRabbitMQ
    Write-Host ''
    Write-Ok 'RabbitMQ configurado!'
    Pause-Continue
}

# ─── Opção 3 — Verificação de dependências ──────────────────────────────────

function Invoke-VerificarDeps {
    Write-SectionHeader 'VERIFICAÇÃO DE DEPENDÊNCIAS'

    # Coleta todas as entradas de desinstalação do registro
    $allEntries = @()
    foreach ($regPath in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        $allEntries += Get-ItemProperty $regPath -ErrorAction SilentlyContinue
    }

    # .NET 10 SDK (registry path unreliable — check install dir)
    $sdk10dir = Get-ChildItem "$env:ProgramFiles\dotnet\sdk" -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^10\.' } | Sort-Object Name | Select-Object -Last 1
    $sdkVer = if ($sdk10dir) { $sdk10dir.Name } else { $null }

    # .NET 10 Hosting Bundle (via ASP.NET Core Runtime shared dir)
    $asp10dir = Get-ChildItem "$env:ProgramFiles\dotnet\shared\Microsoft.AspNetCore.App" -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^10\.' } | Sort-Object Name | Select-Object -Last 1
    $hostingVer = if ($asp10dir) { $asp10dir.Name } else { $null }

    # Erlang
    $erlang = $allEntries | Where-Object { $_.DisplayName -match 'Erlang' } | Select-Object -First 1
    $erlangVer = if ($erlang) { $erlang.DisplayVersion } else { $null }

    # RabbitMQ (com status do serviço)
    $rmq    = $allEntries | Where-Object { $_.DisplayName -match 'RabbitMQ' } | Select-Object -First 1
    $rmqSvc = Get-Service 'RabbitMQ' -ErrorAction SilentlyContinue
    $rmqVer = if ($rmq -and $rmqSvc) { "$($rmq.DisplayVersion) ($($rmqSvc.Status))" }
              elseif ($rmq)          { $rmq.DisplayVersion }
              else                   { $null }

    # IIS URL Rewrite
    $rewrite    = $allEntries | Where-Object { $_.DisplayName -match 'IIS URL Rewrite' } | Select-Object -First 1
    $rewriteVer = if ($rewrite) { $rewrite.DisplayVersion } else { $null }

    # Exibe tabela de status
    $checks = @(
        [pscustomobject]@{ Name = '.NET 10 SDK';            Ver = $sdkVer     }
        [pscustomobject]@{ Name = '.NET 10 Hosting Bundle'; Ver = $hostingVer }
        [pscustomobject]@{ Name = 'Erlang OTP';             Ver = $erlangVer  }
        [pscustomobject]@{ Name = 'RabbitMQ';               Ver = $rmqVer     }
        [pscustomobject]@{ Name = 'IIS URL Rewrite';        Ver = $rewriteVer }
    )

    Write-Host ''
    foreach ($c in $checks) {
        $pad = ' ' * [math]::Max(1, 28 - $c.Name.Length)
        if ($c.Ver) {
            Write-Host '  ✔  ' -NoNewline -ForegroundColor Green
            Write-Host "$($c.Name)$pad" -NoNewline -ForegroundColor White
            Write-Host $c.Ver -ForegroundColor DarkGray
        } else {
            Write-Host '  ✘  ' -NoNewline -ForegroundColor Red
            Write-Host "$($c.Name)$pad" -NoNewline -ForegroundColor DarkGray
            Write-Host 'não instalado' -ForegroundColor DarkGray
        }
    }

    Pause-Continue
}

# ─── Opção 4 — Limpar ambiente ───────────────────────────────────────────────

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
            Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
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
        $_.DisplayName -match 'Mago4-BR' -or
        $_.DisplayName -match 'Mago Service Hub' -or
        $_.DisplayName -match 'Microarea Installer'
    }
}

function Invoke-UninstallEntry {
    param($Entry)
    if (-not $Entry.UninstallString) { return }
    if ($Entry.UninstallString -match 'MsiExec') {
        $guid = if ($Entry.UninstallString -match '(\{[0-9A-Fa-f\-]+\})') { $Matches[1] } else { $null }
        if (-not $guid) { Write-Warn "GUID não encontrado: $($Entry.UninstallString)"; return }
        $proc = Start-Process 'msiexec.exe' -ArgumentList "/x $guid /quiet /norestart" -Wait -PassThru
        if ($proc.ExitCode -in @(0, 3010, 1605)) { Write-Ok "Desinstalado: $($Entry.DisplayName)" }
        else { Write-Warn "$($Entry.DisplayName) — código: $($proc.ExitCode)" }
    } else {
        $exePath = if ($Entry.UninstallString -match '^"([^"]+)"') { $Matches[1] }
                   else { ($Entry.UninstallString -split ' ')[0] }
        if (-not (Test-Path $exePath)) { Write-Warn "Instalador não encontrado: $exePath"; return }
        # WiX Burn bootstrapper: /uninstall /quiet
        $proc = Start-Process -FilePath $exePath -ArgumentList '/uninstall', '/quiet' -Wait -PassThru
        if ($proc.ExitCode -in @(0, 3010, 1605)) { Write-Ok "Desinstalado: $($Entry.DisplayName)" }
        else { Write-Warn "$($Entry.DisplayName) — código: $($proc.ExitCode)" }
    }
}

function Invoke-LimpezaSimples {
    Write-SectionHeader 'LIMPEZA SIMPLES'
    Clear-TempFiles
    Write-Host ''
    Write-Ok 'Limpeza simples concluída!'
    Pause-Continue
}

function Invoke-LimpezaCompleta {
    Write-SectionHeader 'LIMPEZA COMPLETA'

    # Bloqueia se Mago4 estiver instalado
    $mago4 = Get-Mago4Entries
    if ($mago4) {
        Write-Fail 'O Mago4 está instalado. Desinstale-o (opção 3) antes de executar a limpeza completa.'
        Write-Host ''
        $mago4 | ForEach-Object { Write-Warn "Instalado: $($_.DisplayName)" }
        Pause-Continue; return
    }

    # Dupla confirmação com aviso de risco
    Write-Host ''
    Write-Host '  !! ATENÇÃO !! ATENÇÃO !! ATENÇÃO !!' -ForegroundColor Red
    Write-Host ''
    Write-Warn 'É ABSOLUTAMENTE NECESSÁRIO ter backup antes de continuar.'
    Write-Warn 'A pasta C:\Program Files (x86)\Microarea será PERMANENTEMENTE apagada.'
    Write-Host ''
    $c1 = (Read-Host '  Confirma a limpeza completa? [S/N]').Trim().ToUpper()
    if ($c1 -ne 'S') {
        Write-Host ''; Write-Host '  Operação cancelada.' -ForegroundColor DarkGray
        Pause-Continue; return
    }
    Write-Host ''
    Write-Host '  Esta é sua ÚLTIMA CHANCE.' -ForegroundColor Red
    Write-Warn 'Dados apagados NÃO poderão ser recuperados.'
    $c2 = (Read-Host '  Tem ABSOLUTA CERTEZA? [S/N]').Trim().ToUpper()
    if ($c2 -ne 'S') {
        Write-Host ''; Write-Host '  Operação cancelada.' -ForegroundColor DarkGray
        Pause-Continue; return
    }

    Write-Host ''
    Clear-TempFiles

    # Remove pasta Microarea
    Write-Phase 'Remoção de C:\Program Files (x86)\Microarea'
    $microareaDir = 'C:\Program Files (x86)\Microarea'
    if (-not (Test-Path $microareaDir)) {
        Write-Warn 'Pasta não encontrada — etapa ignorada.'
    } else {
        Write-Step 'Removendo pasta Microarea...'
        Remove-Item $microareaDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $microareaDir) { Write-Warn 'Não foi possível remover completamente a pasta Microarea.' }
        else { Write-Ok 'Pasta Microarea removida.' }
    }

    Write-Host ''
    Write-Ok 'Limpeza completa concluída!'
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

    foreach ($pattern in @('Mago4-BR', 'Mago Service Hub', 'Microarea Installer')) {
        $matching = $entries | Where-Object { $_.DisplayName -match $pattern }
        if (-not $matching) { continue }
        Write-Phase $pattern
        foreach ($entry in $matching) { Invoke-UninstallEntry -Entry $entry }
    }

    Write-Host ''
    Write-Ok 'Desinstalação do Mago4 concluída!'
    Pause-Continue
}

function Invoke-LimparAmbiente {
    $running = $true
    while ($running) {
        Clear-Host
        Write-Host ''
        Write-HBorder '╔' '╗'
        Write-CenteredRow 'LIMPAR AMBIENTE' 'Yellow'
        Write-HBorder '╠' '╣'
        Write-EmptyRow
        Write-MenuRow '1' 'Limpeza simples'
        Write-MenuRow '2' 'Limpeza completa'
        Write-MenuRow '3' 'Desinstalar Mago4'
        Write-EmptyRow
        Write-WarningRow 'Faça BACKUP antes de usar a opção 2'
        Write-HBorder '╠' '╣' '─'
        Write-MenuRow '0' 'Voltar' 'Red'
        Write-HBorder '╚' '╝'
        Write-Host ''

        $choice = (Read-Host '  Opção').Trim()
        switch ($choice) {
            '1' { Invoke-LimpezaSimples   }
            '2' { Invoke-LimpezaCompleta  }
            '3' { Invoke-DesinstalarMago4 }
            '0' { $running = $false }
            default {
                Write-Host ''
                Write-Host '  Opção inválida. Tente novamente.' -ForegroundColor Red
                Start-Sleep -Milliseconds 700
            }
        }
    }
}

# ─── Opção 5 — Reparar .NET ──────────────────────────────────────────────────

function Invoke-RepararDotNet {
    Write-SectionHeader 'REPARAR ERRO .NET CORE'
    $path = Get-Dependency -Id 'dotnet10-hosting'
    if (-not $path) { Pause-Continue; return }
    Write-Step 'Reinstalando .NET 10 Hosting Bundle...'
    $proc = Start-Process -FilePath $path -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
    switch ($proc.ExitCode) {
        0       { Write-Ok '.NET 10 Hosting Bundle reinstalado com sucesso.' }
        3010    { Write-Ok '.NET 10 Hosting Bundle reinstalado (reinicialização pendente).' }
        default { Write-Fail "Falha na reinstalação. Código: $($proc.ExitCode)" }
    }
    Pause-Continue
}

# ─── Opção 6 — Diagnóstico do sistema ───────────────────────────────────────

function Invoke-Diagnostico {
    Write-SectionHeader 'DIAGNÓSTICO DO SISTEMA'

    # Coleta entradas do registro separadas por arquitetura
    $entries64  = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'           -ErrorAction SilentlyContinue)
    $entries32  = @(Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue)
    $allEntries = $entries64 + $entries32

    # ── Sistema ──────────────────────────────────────────────────────────
    Write-Phase 'Sistema'
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (-not $os) { $os = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue }
    if ($os) {
        $build     = [int]$os.BuildNumber
        $caption   = $os.Caption -replace 'Microsoft ', ''
        $isServer  = $caption -match 'Server'
        $supported = if ($isServer) { $build -ge 14393 } else { $build -ge 19044 }
        $osState   = if ($supported) { 'ok' } else { 'fail' }
        Write-DiagLine 'Windows' $osState "$caption (Build $build)" 'Atualize para Windows 10 21H2+ ou Server 2016+'
    } else {
        Write-DiagLine 'Windows' 'fail' 'Não detectado' ''
    }

    # ── Features IIS ─────────────────────────────────────────────────────
    Write-Phase 'Funcionalidades IIS'
    Write-Step 'Verificando recursos do Windows (pode demorar)...'
    $isServerOS = Get-IsWindowsServer
    if ($isServerOS) {
        $featIIS    = Get-WindowsFeature 'Web-Server'              -ErrorAction SilentlyContinue
        $featAsp    = Get-WindowsFeature 'NET-Framework-45-ASPNET' -ErrorAction SilentlyContinue
        $featWs     = Get-WindowsFeature 'Web-WebSockets'          -ErrorAction SilentlyContinue
        $featAppInit= Get-WindowsFeature 'Web-AppInit'             -ErrorAction SilentlyContinue
        $fIIS       = [bool]($featIIS     -and $featIIS.Installed)
        $fAsp       = [bool]($featAsp     -and $featAsp.Installed)
        $fWs        = [bool]($featWs      -and $featWs.Installed)
        $fAppInit   = [bool]($featAppInit -and $featAppInit.Installed)
    } else {
        # Uma única chamada DISM para evitar timeout na inicialização por query sequencial
        $allFeats = Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue
        $fEnabled = { param($n) ($allFeats | Where-Object { $_.FeatureName -eq $n }).State -in @('Enabled','EnablePending') }
        $fIIS     = & $fEnabled 'IIS-WebServerRole'
        # IIS-ASPNET45 pode não existir como optional feature em edições IoT/LTSC.
        # Fallback: aspnet_regiis -lv verifica se ASP.NET está registrado no IIS diretamente.
        $fAsp     = & $fEnabled 'IIS-ASPNET45'
        if (-not $fAsp) {
            $aspReg = "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\aspnet_regiis.exe"
            if (Test-Path $aspReg) {
                $pinfo = New-Object System.Diagnostics.ProcessStartInfo $aspReg, '-lv'
                $pinfo.RedirectStandardOutput = $true; $pinfo.UseShellExecute = $false
                try {
                    $proc = [System.Diagnostics.Process]::Start($pinfo)
                    $out  = $proc.StandardOutput.ReadToEnd()
                    $proc.WaitForExit(5000)
                    $fAsp = $out -match '4\.\d+.*Valid'
                } catch {}
            }
        }
        $fWs      = & $fEnabled 'IIS-WebSockets'
        $fAppInit = & $fEnabled 'IIS-ApplicationInit'
    }
    Write-DiagLine 'IIS instalado'    $(if ($fIIS)     { 'ok' } else { 'fail' }) '' 'Execute: Opção 1 > Instalar IIS'
    Write-DiagLine 'ASP.NET 4.8'      $(if ($fAsp)     { 'ok' } else { 'fail' }) '' 'Execute: Opção 1 > Habilitar Features IIS'
    Write-DiagLine 'WebSockets'       $(if ($fWs)      { 'ok' } else { 'fail' }) '' 'Execute: Opção 1 > Habilitar Features IIS'
    Write-DiagLine 'Application Init' $(if ($fAppInit) { 'ok' } else { 'fail' }) '' 'Execute: Opção 1 > Habilitar Features IIS'

    # ── Dependências ──────────────────────────────────────────────────────
    Write-Phase 'Dependências'

    $vcx86 = $entries32 | Where-Object { $_.DisplayName -match 'Visual C\+\+' -and $_.DisplayVersion -match '^14\.' } | Sort-Object DisplayVersion | Select-Object -Last 1
    $vcx64 = $entries64 | Where-Object { $_.DisplayName -match 'Visual C\+\+' -and $_.DisplayVersion -match '^14\.' } | Sort-Object DisplayVersion | Select-Object -Last 1
    Write-DiagLine 'VC++ Redist x86' $(if ($vcx86) { 'ok' } else { 'fail' }) ($vcx86.DisplayVersion) 'Execute: Opção 1 > Instalar individual > VC++ Redist x86'
    Write-DiagLine 'VC++ Redist x64' $(if ($vcx64) { 'ok' } else { 'fail' }) ($vcx64.DisplayVersion) 'Execute: Opção 1 > Instalar individual > VC++ Redist x64'

    $sdk10dir = Get-ChildItem "$env:ProgramFiles\dotnet\sdk" -Directory -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -match '^10\.' } | Sort-Object Name | Select-Object -Last 1
    $sdkVer = if ($sdk10dir) { $sdk10dir.Name } else { $null }
    Write-DiagLine '.NET 10 SDK' $(if ($sdkVer) { 'ok' } else { 'fail' }) $sdkVer 'Execute: Opção 1 > Instalar individual > .NET 10 SDK'

    $asp10dir = Get-ChildItem "$env:ProgramFiles\dotnet\shared\Microsoft.AspNetCore.App" -Directory -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -match '^10\.' } | Sort-Object Name | Select-Object -Last 1
    $hostVer = if ($asp10dir) { $asp10dir.Name } else { $null }
    Write-DiagLine '.NET 10 Hosting Bundle' $(if ($hostVer) { 'ok' } else { 'fail' }) $hostVer 'Execute: Opção 5 (Reparar .NET Core)'

    $ndp48 = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
    $ndp48ok = $ndp48 -and [int]$ndp48.Release -ge 528040
    Write-DiagLine '.NET Fx 4.8 Dev Pack' $(if ($ndp48ok) { 'ok' } else { 'fail' }) $(if ($ndp48ok) { $ndp48.Version } else { $null }) 'Execute: Opção 1 > Instalar individual > .NET Fx 4.8 Dev Pack'

    $rwx64 = $entries64 | Where-Object { $_.DisplayName -match 'IIS URL Rewrite' } | Select-Object -First 1
    Write-DiagLine 'IIS URL Rewrite x64' $(if ($rwx64) { 'ok' } else { 'fail' }) ($rwx64.DisplayVersion) 'Execute: Opção 1 > Instalar individual > IIS URL Rewrite x64'

    $erlang = $allEntries | Where-Object { $_.DisplayName -match 'Erlang' } | Select-Object -First 1
    Write-DiagLine 'Erlang OTP' $(if ($erlang) { 'ok' } else { 'fail' }) ($erlang.DisplayVersion) 'Execute: Opção 2 (Instalar/Corrigir RabbitMQ)'

    $rmq    = $allEntries | Where-Object { $_.DisplayName -match 'RabbitMQ' } | Select-Object -First 1
    $rmqSvc = Get-Service 'RabbitMQ' -ErrorAction SilentlyContinue
    $rmqDetail = if ($rmq -and $rmqSvc) { "$($rmq.DisplayVersion) (serviço: $($rmqSvc.Status))" }
                 elseif ($rmq)           { $rmq.DisplayVersion }
                 else                    { '' }
    $rmqState  = if (-not $rmq) { 'fail' }
                 elseif (-not $rmqSvc -or $rmqSvc.Status -ne 'Running') { 'warn' }
                 else { 'ok' }
    $rmqFix    = if ($rmqState -eq 'fail') { 'Execute: Opção 2 (Instalar/Corrigir RabbitMQ)' }
                 elseif ($rmqState -eq 'warn') { 'Execute: Opção 2 para reconfigurar o serviço' }
                 else { '' }
    Write-DiagLine 'RabbitMQ' $rmqState $rmqDetail $rmqFix

    # ── Conectividade ────────────────────────────────────────────────────
    Write-Phase 'Conectividade'

    Write-Step 'Testando RabbitMQ Management (porta 15672)...'
    $rmqHttp = Test-HttpEndpoint -Url 'http://localhost:15672' -OkCodes @(200, 401)
    $rmqHttpDetail = if ($rmqHttp.Code -gt 0) { "HTTP $($rmqHttp.Code)" } else { 'sem resposta' }
    Write-DiagLine 'RabbitMQ porta 15672' $(if ($rmqHttp.Ok) { 'ok' } else { 'fail' }) $rmqHttpDetail 'Verifique o serviço RabbitMQ (services.msc)'

    # ── Mago4 ────────────────────────────────────────────────────────────
    Write-Phase 'Mago4'

    $mago4Entry = $allEntries | Where-Object { $_.DisplayName -match 'Mago4-BR' }          | Sort-Object DisplayVersion | Select-Object -Last 1
    $mshEntry   = $allEntries | Where-Object { $_.DisplayName -match 'Mago Service Hub' }  | Sort-Object DisplayVersion | Select-Object -Last 1
    $mago4Ver   = if ($mago4Entry) { $mago4Entry.DisplayVersion } else { $null }
    $mshVer     = if ($mshEntry)   { $mshEntry.DisplayVersion   } else { $null }

    Write-DiagLine 'Mago4-BR'         $(if ($mago4Ver) { 'ok' } else { 'info' }) $mago4Ver ''
    Write-DiagLine 'Mago Service Hub' $(if ($mshVer)   { 'ok' } else { 'info' }) $mshVer   ''

    if ($mshEntry) {
        Write-Step 'Testando Backend (ERPServiceProvider/Backend)...'
        $backRes = Test-HttpEndpoint -Url 'http://localhost/Mago4/ERPServiceProvider/Backend' -OkCodes @(200)
        $backDetail = if ($backRes.Code -gt 0) { "HTTP $($backRes.Code)" } else { 'sem resposta' }
        Write-DiagLine 'Backend URL' $(if ($backRes.Ok) { 'ok' } else { 'fail' }) $backDetail 'Verifique o IIS e os app pools'

        Write-Step 'Testando Frontend (ERPServiceProvider/Frontend)...'
        $frontRes = Test-HttpEndpoint -Url 'http://localhost/Mago4/ERPServiceProvider/Frontend' -OkCodes @(200)
        $frontDetail = if ($frontRes.Code -gt 0) { "HTTP $($frontRes.Code)" } else { 'sem resposta' }
        Write-DiagLine 'Frontend URL' $(if ($frontRes.Ok) { 'ok' } else { 'fail' }) $frontDetail 'Verifique o IIS e os app pools'
    }

    if ($mago4Entry) {
        Write-Step 'Testando LoginManager...'
        $lmRes = Test-HttpEndpoint -Url 'http://localhost/Mago4/LoginManager' -OkCodes @(200, 403)
        $lmDetail = if ($lmRes.Code -gt 0) { "HTTP $($lmRes.Code)" } else { 'sem resposta' }
        Write-DiagLine 'LoginManager URL' $(if ($lmRes.Ok) { 'ok' } else { 'fail' }) $lmDetail 'Verifique o IIS e os app pools'
    }

    Write-Host ''
    Pause-Continue
}

# ─── Loop principal ──────────────────────────────────────────────────────────

$running = $true
while ($running) {
    Show-Menu
    $choice = (Read-Host '  Opção').Trim()
    switch ($choice) {
        '1' { Invoke-InstalarDeps   }
        '2' { Invoke-RabbitMQ       }
        '3' { Invoke-VerificarDeps  }
        '4' { Invoke-LimparAmbiente }
        '5' { Invoke-RepararDotNet  }
        '6' { Invoke-Diagnostico   }
        '0' { $running = $false    }
        default {
            Write-Host ''
            Write-Host '  Opção inválida. Tente novamente.' -ForegroundColor Red
            Start-Sleep -Milliseconds 700
        }
    }
}

Clear-Host
Write-Host ''
Write-Host '  Até logo!' -ForegroundColor Cyan
Write-Host ''
