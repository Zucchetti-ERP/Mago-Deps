function Show-Menu {
    Clear-Host
    Write-Host ''
    Write-HBorder '╔' '╗'
    Write-CenteredRow 'SCRIPTS MAGO4' 'Yellow'
    Write-CenteredRow 'Zucchetti Brasil' 'DarkGray'
    Write-HBorder '╠' '╣'
    Write-EmptyRow
    Write-MenuRow '1' 'Instalação de Dependências'
    Write-MenuRow '2' 'Opções de reparo'
    Write-MenuRow '3' 'Diagnósticos'
    Write-MenuRow '4' 'Opções de Limpeza'
    Write-MenuRow '5' 'Instalação ou Atualização do Mago4'
    Write-EmptyRow
    Write-HBorder '╠' '╣' '─'
    Write-MenuRow '0' 'Sair' 'Red'
    Write-HBorder '╚' '╝'
    Write-Host ''
}

function Invoke-MenuGroup {
    param([string]$Title, [string[]]$Options, [scriptblock[]]$Actions)
    while ($true) {
        Clear-Host
        Write-Host ''
        Write-HBorder '╔' '╗'
        Write-CenteredRow $Title
        Write-HBorder '╠' '╣'
        Write-EmptyRow
        for ($index = 0; $index -lt $Options.Count; $index++) {
            Write-MenuRow ([string]($index + 1)) $Options[$index]
        }
        Write-EmptyRow
        Write-HBorder '╠' '╣' '─'
        Write-MenuRow '0' 'Voltar' 'Red'
        Write-HBorder '╚' '╝'
        Write-Host ''
        $choice = (Read-Host '  Opção').Trim()
        if ($choice -eq '0') { return }
        $selected = 0
        if ([int]::TryParse($choice, [ref]$selected) -and $selected -ge 1 -and $selected -le $Actions.Count) {
            & $Actions[$selected - 1]
        } else { Write-Fail 'Opção inválida.'; Start-Sleep -Milliseconds 700 }
    }
}

function Invoke-ReparoMenu {
    Invoke-MenuGroup 'OPÇÕES DE REPARO' @('Corrigir RabbitMQ', 'Reparar erro .NET Core', 'Reparo simples do Mago4', 'Reparo avançado do Mago4') @(
        { Invoke-RabbitMQ }, { Invoke-RepararDotNet }, { Invoke-ReparoSimplesMago4 }, { Invoke-ReparoAvancadoMago4 }
    )
}

function Invoke-DiagnosticosMenu {
    Invoke-MenuGroup 'DIAGNÓSTICOS' @('Verificação de Dependências', 'Diagnóstico Completo do Sistema') @(
        { Invoke-VerificarDeps }, { Invoke-Diagnostico }
    )
}

function Invoke-MagoMenu {
    Invoke-MenuGroup 'INSTALAÇÃO OU ATUALIZAÇÃO' @('Instalar Mago4', 'Atualizar Mago4', 'Instalar verticais no Mago4 existente') @(
        { Invoke-InstalarMago4 }, { Invoke-AtualizarMago4 }, { Invoke-InstalarVerticaisMago4 }
    )
}

function Start-Mago4Bootstrap {
    while ($true) {
        Show-Menu
        $choice = (Read-Host '  Opção').Trim()
        switch ($choice) {
            '1' { Invoke-InstalarDeps }
            '2' { Invoke-ReparoMenu }
            '3' { Invoke-DiagnosticosMenu }
            '4' { Invoke-LimparAmbiente }
            '5' { Invoke-MagoMenu }
            '0' { Clear-Host; Write-Host '  Até logo!' -ForegroundColor Cyan; return }
            default { Write-Fail 'Opção inválida.'; Start-Sleep -Milliseconds 700 }
        }
    }
}

