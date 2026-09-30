function Install-IISRewrite {
    Write-Phase 'IIS URL Rewrite Module'
    $path = Get-Dependency -Id 'iis-rewrite-x64'
    if (-not $path) { return }
    $dep = (Get-Manifest).dependencies | Where-Object { $_.id -eq 'iis-rewrite-x64' } | Select-Object -First 1
    Write-Step "Instalando $($dep.name)..."
    $proc = Start-Process -FilePath 'msiexec.exe' `
        -ArgumentList '/i', "`"$path`"", '/quiet', '/norestart' -Wait -PassThru
    switch ($proc.ExitCode) {
        0       { Write-Ok "$($dep.name) instalado." }
        3010    { Write-Ok "$($dep.name) instalado (reinicialização pendente)." }
        1638    { Write-Ok "$($dep.name) já está instalado." }
        default { Write-Fail "$($dep.name) falhou. Código: $($proc.ExitCode)" }
    }
}
