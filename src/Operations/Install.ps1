function Invoke-DepCompleta {
    Write-SectionHeader 'INSTALAÇÃO COMPLETA (IIS + MAGO4 + MSH)'
    # Pergunta já no início para a instalação seguir sem interrupções até a fase do MSH.
    $rabbitProfile = Select-RabbitMQProfile
    if (-not $rabbitProfile) { Write-Warn 'Instalação cancelada.'; Pause-Continue; return }
    Write-Host ''
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
    Install-ErlangAndRabbitMQ -RabbitProfile $rabbitProfile
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
    $rabbitProfile = Select-RabbitMQProfile
    if (-not $rabbitProfile) { Write-Warn 'Instalação cancelada.'; Pause-Continue; return }
    Install-IISRewrite
    Install-ErlangAndRabbitMQ -RabbitProfile $rabbitProfile
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

