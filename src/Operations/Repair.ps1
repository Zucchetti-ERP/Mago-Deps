function Invoke-RabbitMQ {
    Write-SectionHeader 'INSTALAR/CORRIGIR RABBITMQ'
    Install-ErlangAndRabbitMQ
    Write-Host ''
    Write-Ok 'RabbitMQ configurado!'
    Pause-Continue
}


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
    if (Confirm-MagoAction 'Executar diagnóstico adicional somente de leitura?') {
        try { Invoke-DiagnosticoDotNetMago } catch { Write-Fail "Diagnóstico interrompido: $($_.Exception.Message)" }
    }
    Pause-Continue
}

function Invoke-DiagnosticoDotNetMago {
    Write-Phase 'Diagnóstico .NET Core do Mago4'
    $record = Get-MagoInstallRecord
    if (-not $record) { Write-Warn 'Mago4 não está instalado; verificação de pastas e URL ignorada.' }
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($dotnet) {
        Write-Step 'Runtimes e SDKs instalados:'
        & $dotnet.Source --list-runtimes | ForEach-Object { Write-Host "    $_" }
        & $dotnet.Source --list-sdks | ForEach-Object { Write-Host "    $_" }
    } else { Write-Warn 'dotnet.exe não encontrado no PATH.' }
    $hostingModule = Join-Path $env:SystemRoot 'System32\inetsrv\aspnetcore.dll'
    Write-DiagLine 'AspNetCoreModule' $(if (Test-Path $hostingModule) { 'ok' } else { 'fail' }) $hostingModule 'Reinstale o Hosting Bundle.'
    try {
        Import-Module WebAdministration -ErrorAction Stop
        $modules = @(Get-WebGlobalModule -ErrorAction Stop | Where-Object { $_.Name -match 'AspNetCoreModule' })
        Write-DiagLine 'Módulo no IIS' $(if ($modules.Count) { 'ok' } else { 'fail' }) (@($modules | ForEach-Object Name) -join ', ') 'Reinstale o Hosting Bundle.'
        $pools = @(Get-ChildItem 'IIS:\AppPools' -ErrorAction Stop | Where-Object { $_.Name -match 'Mago|M4' })
        foreach ($pool in $pools) {
            $state = (Get-WebAppPoolState -Name $pool.Name -ErrorAction SilentlyContinue).Value
            Write-DiagLine "Pool $($pool.Name)" $(if ($state -eq 'Started') { 'ok' } else { 'warn' }) $state 'Verifique o pool no IIS.'
        }
        $mime = @(Get-WebConfiguration -Filter 'system.webServer/staticContent/mimeMap' -PSPath 'IIS:\' -ErrorAction SilentlyContinue |
            Where-Object { $_.fileExtension -eq '.json' })
        if (-not $mime.Count) { Write-Warn 'Confira se .json está mapeado como application/json no site Mago4.' }
    } catch { Write-Warn "Consulta ao IIS indisponível: $($_.Exception.Message)" }
    if ($record) {
        $server = Join-Path $record.Path 'Standard\TaskBuilder\WebFramework\M4Server'
        $config = Join-Path $record.Path 'Standard\TaskBuilder\WebFramework\M4Client\assets\config.json'
        $keyFolders = @(
            (Join-Path $env:LOCALAPPDATA 'ASP.NET\DataProtection-Keys'),
            (Join-Path $env:SystemRoot 'System32\config\systemprofile\AppData\Local\ASP.NET\DataProtection-Keys')
        )
        foreach ($path in @($record.Path, (Join-Path $record.Path 'Standard'), (Join-Path $record.Path 'Custom'), $server,
                           (Join-Path $env:SystemRoot 'Microsoft.NET\Framework64'), $env:SystemRoot) + $keyFolders) {
            if (Test-Path -LiteralPath $path) {
                Write-Step "ACL: $path"
                (Get-Acl -LiteralPath $path).Access | ForEach-Object {
                    Write-Host "    $($_.IdentityReference): $($_.FileSystemRights) ($($_.AccessControlType))" -ForegroundColor DarkGray
                }
            } else { Write-Warn "Pasta não encontrada: $path" }
        }
        if (Test-Path -LiteralPath $config) {
            try {
                $json = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
                Write-Step "config.json: baseUrl=$($json.baseUrl); wsBaseUrl=$($json.wsBaseUrl)"
            } catch { Write-Warn 'config.json não pôde ser interpretado.' }
        } else { Write-Warn "config.json não encontrado: $config" }
        $instanceName = Split-Path -Leaf $record.Path
        $url = "http://localhost/$instanceName/m4server/account-manager/isAlive"
        $response = Test-HttpEndpoint -Url $url -OkCodes @(200)
        Write-DiagLine 'M4Server isAlive' $(if ($response.Ok) { 'ok' } else { 'fail' }) "HTTP $($response.Code)" $url
        $stdoutPath = Join-Path $server 'logs'
        if (Test-Path -LiteralPath $stdoutPath) {
            Write-Step "Logs já existentes: $stdoutPath"
            Get-ChildItem -LiteralPath $stdoutPath -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object {
                Write-Host "    $($_.Name) — $($_.LastWriteTime)" -ForegroundColor DarkGray
            }
        }
    }
    Write-Warn 'Norton: confirme bloqueios/exclusões manualmente com a equipe de segurança; não desative proteções pelo script.'
    Write-Warn 'Permissões Everyone/Full Control não são aplicadas. Corrija somente identidades necessárias.'
    Write-Warn 'Confira manualmente hosts, MIME .json, IIS e o guia do fabricante se o problema persistir.'
    Write-Warn 'A ativação temporária de stdoutLogEnabled e o teste dotnet web-server.dll exigem operação assistida.'
    if (Confirm-MagoAction 'Salvar dotnet --info e relatório de diagnóstico local?') {
        $dir = Join-Path (Get-MagoLogDirectory) ("dotnet-diagnostic-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        if ($dotnet) { & $dotnet.Source --info | Out-File -LiteralPath (Join-Path $dir 'dotnet-info.txt') -Encoding UTF8 }
        @(
            "Instalação: $($record.Path)",
            "AspNetCoreModule: $(Test-Path $hostingModule)",
            "Data: $(Get-Date -Format o)"
        ) | Out-File -LiteralPath (Join-Path $dir 'resumo.txt') -Encoding UTF8
        if ($record -and (Test-Path -LiteralPath $stdoutPath)) {
            $existingLogs = @(Get-ChildItem -LiteralPath $stdoutPath -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -le 20MB } | Sort-Object LastWriteTime -Descending | Select-Object -First 5)
            if ($existingLogs.Count) {
                $copyTo = Join-Path $dir 'stdout-existente'
                New-Item -ItemType Directory -Path $copyTo | Out-Null
                foreach ($log in $existingLogs) { Copy-Item -LiteralPath $log.FullName -Destination $copyTo }
            }
        }
        Write-Ok "Relatório salvo em: $dir"
        Write-Warn 'Revise os logs antes de compartilhá-los: podem conter dados sensíveis.'
    }
}

