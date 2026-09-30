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
    Write-DiagLine '.NET 10 Hosting Bundle' $(if ($hostVer) { 'ok' } else { 'fail' }) $hostVer 'Execute: Opção 2 > Reparar erro .NET Core'

    $ndp48 = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
    $ndp48ok = $ndp48 -and [int]$ndp48.Release -ge 528040
    Write-DiagLine '.NET Fx 4.8 Dev Pack' $(if ($ndp48ok) { 'ok' } else { 'fail' }) $(if ($ndp48ok) { $ndp48.Version } else { $null }) 'Execute: Opção 1 > Instalar individual > .NET Fx 4.8 Dev Pack'

    $rwx64 = $entries64 | Where-Object { $_.DisplayName -match 'IIS URL Rewrite' } | Select-Object -First 1
    Write-DiagLine 'IIS URL Rewrite x64' $(if ($rwx64) { 'ok' } else { 'fail' }) ($rwx64.DisplayVersion) 'Execute: Opção 1 > Instalar individual > IIS URL Rewrite x64'

    $erlang = $allEntries | Where-Object { $_.DisplayName -match 'Erlang' } | Select-Object -First 1
    Write-DiagLine 'Erlang OTP' $(if ($erlang) { 'ok' } else { 'fail' }) ($erlang.DisplayVersion) 'Execute: Opção 2 > Corrigir RabbitMQ'

    $rmq    = $allEntries | Where-Object { $_.DisplayName -match 'RabbitMQ' } | Select-Object -First 1
    $rmqSvc = Get-Service 'RabbitMQ' -ErrorAction SilentlyContinue
    $rmqDetail = if ($rmq -and $rmqSvc) { "$($rmq.DisplayVersion) (serviço: $($rmqSvc.Status))" }
                 elseif ($rmq)           { $rmq.DisplayVersion }
                 else                    { '' }
    $rmqState  = if (-not $rmq) { 'fail' }
                 elseif (-not $rmqSvc -or $rmqSvc.Status -ne 'Running') { 'warn' }
                 else { 'ok' }
    $rmqFix    = if ($rmqState -eq 'fail') { 'Execute: Opção 2 > Corrigir RabbitMQ' }
                 elseif ($rmqState -eq 'warn') { 'Execute: Opção 2 > Corrigir RabbitMQ para reconfigurar o serviço' }
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
