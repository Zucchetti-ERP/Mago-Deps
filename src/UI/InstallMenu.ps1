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

