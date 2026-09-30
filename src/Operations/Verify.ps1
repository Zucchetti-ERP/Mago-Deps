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

