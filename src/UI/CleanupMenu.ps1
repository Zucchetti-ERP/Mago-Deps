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
        Write-MenuRow '2' 'Desinstalar Mago4'
        Write-EmptyRow
        Write-WarningRow 'Faça BACKUP antes de desinstalar'
        Write-HBorder '╠' '╣' '─'
        Write-MenuRow '0' 'Voltar' 'Red'
        Write-HBorder '╚' '╝'
        Write-Host ''

        $choice = (Read-Host '  Opção').Trim()
        switch ($choice) {
            '1' { Invoke-LimpezaSimples   }
            '2' { Invoke-DesinstalarMago4 }
            '0' { $running = $false }
            default {
                Write-Host ''
                Write-Host '  Opção inválida. Tente novamente.' -ForegroundColor Red
                Start-Sleep -Milliseconds 700
            }
        }
    }
}

