function Wait-ServiceRemoved {
    param([string]$Name, [int]$TimeoutSeconds = 10)
    for ($i = 0; $i -lt ($TimeoutSeconds * 2); $i++) {
        if (-not (Get-Service $Name -ErrorAction SilentlyContinue)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return -not (Get-Service $Name -ErrorAction SilentlyContinue)
}

function Stop-ErlangProcesses {
    # Para o epmd graciosamente (evita deixar a porta 4369 num estado esquisito) antes de
    # forçar o encerramento de qualquer processo Erlang/RabbitMQ remanescente.
    $epmdBin = $null
    if ($env:ERLANG_HOME) {
        $candidate = Join-Path $env:ERLANG_HOME 'bin\epmd.exe'
        if (Test-Path $candidate) { $epmdBin = $candidate }
    }
    if (-not $epmdBin) {
        $epmdBin = Get-ChildItem $env:ProgramFiles -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '^(erl|Erlang)' } |
                   ForEach-Object { Join-Path $_.FullName 'bin\epmd.exe' } |
                   Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if ($epmdBin) { try { & $epmdBin -kill | Out-Null } catch {} }

    Get-Process -Name 'erl', 'werl', 'epmd', 'erlsrv' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

function Remove-DirWithRetry {
    param([string]$Path, [int]$Retries = 5)
    for ($i = 0; $i -lt $Retries; $i++) {
        if (-not (Test-Path $Path)) { return $true }
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $Path)) { return $true }
        Start-Sleep -Seconds 2
    }
    return -not (Test-Path $Path)
}

function Clear-ErlangRabbitMQ {
    Write-Phase 'Limpeza de instalações anteriores'
    $rmqBase = Join-Path $env:ProgramFiles 'RabbitMQ Server'

    # Para e remove o serviço primeiro — matar o node por baixo do SCM pode disparar um
    # restart automático (erlsrv) antes do sc stop/delete rodarem, travando arquivos.
    if (Get-Service 'RabbitMQ' -ErrorAction SilentlyContinue) {
        Write-Step 'Parando serviço RabbitMQ...'
        $p = Start-Process 'sc.exe' -ArgumentList 'stop RabbitMQ'   -PassThru -WindowStyle Hidden
        if (-not $p.WaitForExit(8000)) { try { $p.Kill() } catch {} }
        $p = Start-Process 'sc.exe' -ArgumentList 'delete RabbitMQ' -PassThru -WindowStyle Hidden
        if (-not $p.WaitForExit(8000)) { try { $p.Kill() } catch {} }
        if (-not (Wait-ServiceRemoved -Name 'RabbitMQ')) {
            Write-Warn 'Serviço RabbitMQ ainda aparece registrado — feche services.msc/Gerenciador de Tarefas se estiverem abertos.'
        }
    }

    # sc delete só limpa o registro do SCM — o erlsrv mantém seu próprio cadastro do serviço
    # à parte, e uma entrada velha aqui pode fazer o próximo "erlsrv add" falhar ou ficar
    # inconsistente com o SCM.
    Remove-Item 'HKLM:\SOFTWARE\Ericsson\Erlang\ErlSrv\1.1\RabbitMQ' -Recurse -Force -ErrorAction SilentlyContinue

    # Mata (graciosamente e depois à força) processos Erlang/RabbitMQ residuais
    Stop-ErlangProcesses

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
                if ($p) { if (-not $p.WaitForExit(40000)) { try { $p.Kill() } catch {} } }
                Write-Ok "$($_.DisplayName) desinstalado."
            }
        }
    }

    # Fallback: instalações anteriores interrompidas durante a extração (antes de escrever a
    # entrada de registro) não aparecem no loop acima, mas ainda podem ter um uninstall.exe na
    # própria pasta de instalação — tenta o desinstalador oficial antes de apagar arquivos à mão.
    $rmqUninstallExe = Join-Path $rmqBase 'uninstall.exe'
    if (Test-Path $rmqUninstallExe) {
        Write-Step 'Desinstalando RabbitMQ Server (uninstall.exe encontrado na pasta de instalação)...'
        $p = Start-Process -FilePath $rmqUninstallExe -ArgumentList '/S' -PassThru -ErrorAction SilentlyContinue
        if ($p) { if (-not $p.WaitForExit(40000)) { try { $p.Kill() } catch {} } }
        Write-Ok 'RabbitMQ Server desinstalado.'
    }

    # Remove diretórios residuais do Program Files — último recurso, com retry para absorver
    # handles que ainda não soltaram logo após matar os processos.
    Write-Step 'Removendo diretórios residuais...'
    if (Test-Path $rmqBase) {
        if (Remove-DirWithRetry $rmqBase) { Write-Ok 'Pasta RabbitMQ Server removida.' }
        else { Write-Warn 'Não foi possível remover completamente: RabbitMQ Server' }
    }
    Get-ChildItem $env:ProgramFiles -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(erl|Erlang)' } | ForEach-Object {
        if (Remove-DirWithRetry $_.FullName) { Write-Ok "Pasta $($_.Name) removida." }
        else { Write-Warn "Não foi possível remover: $($_.Name)" }
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
    $staleErlDir = Get-ChildItem $env:ProgramFiles -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '^(erl|Erlang)' } | Select-Object -First 1
    if ($staleErlDir) {
        Write-Fail "A limpeza não conseguiu remover uma instalação anterior do Erlang ($($staleErlDir.FullName)). Feche processos que possam estar usando a pasta (Explorer, antivírus, terminal) e tente novamente."
        return
    }
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
    if (-not $proc.WaitForExit(120000)) {
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

    Write-Step 'Reconfigurando serviço RabbitMQ...'
    # sc.exe stop/delete é direto e não comunica com o broker — sem risco de trave
    $p = Start-Process 'sc.exe' -ArgumentList 'stop RabbitMQ'   -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit(8000)) { try { $p.Kill() } catch {} }
    $p = Start-Process 'sc.exe' -ArgumentList 'delete RabbitMQ' -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit(8000)) { try { $p.Kill() } catch {} }
    if (-not (Wait-ServiceRemoved -Name 'RabbitMQ')) {
        Write-Warn 'Serviço RabbitMQ ainda aparece registrado — feche services.msc/Gerenciador de Tarefas se estiverem abertos.'
    }

    # sc delete só limpa o registro do SCM — o erlsrv mantém seu próprio cadastro do serviço
    # à parte, e uma entrada velha aqui pode fazer o próximo "erlsrv add" falhar ou ficar
    # inconsistente com o SCM.
    Remove-Item 'HKLM:\SOFTWARE\Ericsson\Erlang\ErlSrv\1.1\RabbitMQ' -Recurse -Force -ErrorAction SilentlyContinue

    # Mata processos Erlang residuais do installer antes de registrar o serviço
    Stop-ErlangProcesses

    $svcLog = Join-Path $env:TEMP 'rabbitmq-service-install.log'
    Remove-Item $svcLog, "$svcLog.err" -ErrorAction SilentlyContinue
    $p = Start-Process 'cmd.exe' -ArgumentList "/c `"$sbin\rabbitmq-service.bat`" install" -PassThru -WindowStyle Hidden -RedirectStandardOutput $svcLog -RedirectStandardError "$svcLog.err"
    if (-not $p.WaitForExit(60000)) { try { $p.Kill() } catch {}; $p.WaitForExit(5000) | Out-Null }
    # erlsrv, sob redirecionamento de saída, pode não devolver um exit code confiável a tempo —
    # a fonte da verdade real é o próprio SCM: se o serviço existe, o registro funcionou.
    if (-not (Get-Service 'RabbitMQ' -ErrorAction SilentlyContinue)) {
        Write-Fail 'Falha ao registrar o serviço RabbitMQ.'
        Get-Content $svcLog, "$svcLog.err" -ErrorAction SilentlyContinue | Where-Object { $_ } | ForEach-Object { Write-Warn $_ }
        return
    }
    Write-Ok 'Serviço RabbitMQ registrado.'

    Write-Step 'Habilitando Management Plugin...'
    $pluginLog = Join-Path $env:TEMP 'rabbitmq-plugin-enable.log'
    Remove-Item $pluginLog, "$pluginLog.err" -ErrorAction SilentlyContinue
    $p = Start-Process 'cmd.exe' -ArgumentList "/c `"$sbin\rabbitmq-plugins.bat`" enable --offline rabbitmq_management" -PassThru -WindowStyle Hidden -RedirectStandardOutput $pluginLog -RedirectStandardError "$pluginLog.err"
    if (-not $p.WaitForExit(30000)) { try { $p.Kill() } catch {}; $p.WaitForExit(5000) | Out-Null }
    if ($p.ExitCode -ne 0) {
        Write-Warn "Management Plugin pode não ter sido habilitado (código $($p.ExitCode))."
        Get-Content $pluginLog, "$pluginLog.err" -ErrorAction SilentlyContinue | Where-Object { $_ } | ForEach-Object { Write-Warn $_ }
    } else {
        Write-Ok 'Management Plugin habilitado.'
    }

    Write-Step 'Iniciando serviço RabbitMQ...'
    Start-Service 'RabbitMQ' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    $svc = Get-Service 'RabbitMQ' -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Ok 'Serviço RabbitMQ iniciado com sucesso.'
    } else {
        Write-Warn 'Serviço RabbitMQ pode não ter iniciado. Verifique manualmente.'
        $rmqLogDir = Join-Path $env:APPDATA 'RabbitMQ\log'
        $rmqLog = Get-ChildItem $rmqLogDir -Filter '*.log' -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($rmqLog) {
            Write-Step "Últimas linhas de $($rmqLog.Name):"
            Get-Content $rmqLog.FullName -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        }
    }
}

