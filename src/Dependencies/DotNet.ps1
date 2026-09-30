function Install-DotNet10 {
    Write-Phase '.NET 10'
    foreach ($id in @('dotnet10-sdk', 'dotnet10-hosting')) {
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

function Install-NetFx48DevPack {
    Write-Phase '.NET Framework 4.8 Developer Pack'
    $path = Get-Dependency -Id 'netfx48-devpack'
    if (-not $path) { return }
    Write-Step 'Instalando .NET Framework 4.8 Developer Pack...'
    $proc = Start-Process -FilePath $path -ArgumentList '/q', '/norestart' -Wait -PassThru
    switch ($proc.ExitCode) {
        0       { Write-Ok '.NET Framework 4.8 Developer Pack instalado.' }
        3010    { Write-Ok '.NET Framework 4.8 Developer Pack instalado (reinicialização pendente).' }
        1638    { Write-Ok '.NET Framework 4.8 Developer Pack já está instalado.' }
        default { Write-Fail ".NET Framework 4.8 Developer Pack falhou. Código: $($proc.ExitCode)" }
    }
}
