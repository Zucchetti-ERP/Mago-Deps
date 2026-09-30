function Get-Manifest {
    if ($script:Manifest) { return $script:Manifest }
    try {
        Write-Step 'Carregando manifest de dependências...'
        if ($script:ManifestLocalPath) {
            $script:Manifest = Get-Content -LiteralPath $script:ManifestLocalPath -Raw | ConvertFrom-Json
        } else {
            $script:Manifest = Invoke-RestMethod -Uri $script:ManifestUrl -UseBasicParsing
        }
        if ($script:CodeRef) {
            $script:Manifest.baseRepoUrl = "https://raw.githubusercontent.com/Zucchetti-ERP/Mago-Deps/$script:CodeRef"
        }
        return $script:Manifest
    } catch {
        Write-Fail "Não foi possível carregar o manifest: $_"
        return $null
    }
}

function Resolve-DotNetUrl {
    param(
        [string]$Channel,
        [string]$Component
    )
    try {
        Write-Step "Consultando releases do .NET $Channel..."
        $feed = $null
        foreach ($feedUrl in @(
            "https://builds.dotnet.microsoft.com/dotnet/release-metadata/$Channel/releases.json",
            "https://dotnetcli.azureedge.net/dotnet/release-metadata/$Channel/releases.json"
        )) {
            try { $feed = Invoke-RestMethod -Uri $feedUrl -UseBasicParsing -ErrorAction Stop; break } catch {}
        }
        if (-not $feed) { throw "Feed inacessível em todos os endpoints." }
        $latest = $feed.releases |
            Where-Object { $_.'release-version' -eq $feed.'latest-release' } |
            Select-Object -First 1

        switch ($Component) {
            'sdk-win-x64' {
                return ($latest.sdk.files |
                    Where-Object { $_.rid -eq 'win-x64' -and $_.name -like '*.exe' } |
                    Select-Object -First 1).url
            }
            'hosting-bundle' {
                return ($latest.'aspnetcore-runtime'.files |
                    Where-Object { $_.name -like 'dotnet-hosting*win.exe' } |
                    Select-Object -First 1).url
            }
        }
    } catch {
        Write-Fail "Falha ao consultar feed do .NET $Channel`: $_"
    }
    return $null
}

function Get-Dependency {
    param([string]$Id)

    $manifest = Get-Manifest
    if (-not $manifest) { return $null }

    $dep = $manifest.dependencies | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $dep) {
        Write-Fail "Dependência '$Id' não encontrada no manifest."
        return $null
    }

    if (-not (Test-Path $script:DownloadDir)) {
        New-Item -ItemType Directory -Path $script:DownloadDir -Force | Out-Null
    }

    $localPath = Join-Path $script:DownloadDir $dep.filename

    if (Test-Path $localPath) {
        Write-Ok "$($dep.name) já disponível em cache."
        return $localPath
    }

    $url = switch ($dep.source) {
        'direct'       { $dep.url }
        'repo'         { "$($manifest.baseRepoUrl)/Deps/$($dep.filename)" }
        'dotnet-feed'  { Resolve-DotNetUrl -Channel $dep.channel -Component $dep.component }
        default        { $null }
    }

    if (-not $url) {
        Write-Fail "Não foi possível resolver a URL de '$($dep.name)'."
        return $null
    }

    Write-Step "Baixando $($dep.name)..."
    $prev = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $url -OutFile $localPath -UseBasicParsing
        $sizeMB = [math]::Round((Get-Item $localPath).Length / 1MB, 1)
        Write-Ok "Download concluído: $($dep.name) ($sizeMB MB)"
        return $localPath
    } catch {
        Write-Fail "Falha no download de $($dep.name): $_"
        if (Test-Path $localPath) { Remove-Item $localPath -Force }
        return $null
    } finally {
        $ProgressPreference = $prev
    }
}

