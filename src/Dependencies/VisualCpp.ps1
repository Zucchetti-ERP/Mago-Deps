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
