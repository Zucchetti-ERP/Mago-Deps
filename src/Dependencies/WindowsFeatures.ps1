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
