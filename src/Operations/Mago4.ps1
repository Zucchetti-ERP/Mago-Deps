function Get-MagoMainEntry {
    $entries = @(Get-Mago4Entries | Where-Object { $_.DisplayName -match '^Mago4-BR\b' })
    if ($entries.Count -gt 1) { throw 'Mais de uma instalação do Mago4 foi encontrada. Operação cancelada.' }
    if ($entries.Count -eq 0) { return $null }
    return $entries[0]
}

function Get-MagoInstallRecord {
    $entry = Get-MagoMainEntry
    if (-not $entry) { return $null }
    $records = @(foreach ($registryPath in @('HKLM:\SOFTWARE\Microarea\Mago4', 'HKLM:\SOFTWARE\WOW6432Node\Microarea\Mago4')) {
        Get-ChildItem -LiteralPath $registryPath -ErrorAction SilentlyContinue | ForEach-Object {
            Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
        }
    })
    $records = @($records | Where-Object { $_.InstallDir } | Sort-Object PSChildName -Unique)
    if ($records.Count -gt 1) { throw 'Mais de um caminho Mago4 no registro. Operação cancelada.' }
    $path = if ($records.Count -eq 1) { [string]$records[0].InstallDir } else { [string]$entry.InstallLocation }
    if (-not $path) { throw 'Pasta instalada não registrada; confirme manualmente antes de continuar.' }
    return [pscustomobject]@{ Entry = $entry; Path = $path.TrimEnd('\'); Registry = $(if ($records.Count) { $records[0] } else { $null }) }
}

function Get-MagoInstallerInfo {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.Extension -ieq '.exe') {
        if ($item.VersionInfo.ProductName -notmatch 'Microarea Installer') { throw 'O arquivo não parece ser o instalador principal do Mago4.' }
        return [pscustomobject]@{ Path = $item.FullName; Version = [version]$item.VersionInfo.ProductVersion; Type = 'Exe'; MshPath = $null; Features = $null }
    }
    if ($item.Extension -ine '.msi') { throw 'Selecione o instalador principal .exe ou .msi do Mago4.' }
    $msi = New-Object -ComObject WindowsInstaller.Installer
    $database = $msi.OpenDatabase($item.FullName, 0)
    $name = Get-MagoMsiProperty $database 'ProductName'
    $maker = Get-MagoMsiProperty $database 'Manufacturer'
    $version = [version](Get-MagoMsiProperty $database 'ProductVersion')
    $productCode = Get-MagoMsiProperty $database 'ProductCode'
    if ($name -notmatch '^Mago4-BR (\d+)\.(\d+)\.(\d+)\.(\d+)$' -or $maker -notmatch 'Microarea|Zucchetti' -or
        $productCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { throw 'MSI principal do Mago4 não reconhecido.' }
    $displayVersion = [version]($name -replace '^Mago4-BR ', '')
    if ($displayVersion.Major -ne $version.Major -or $displayVersion.Minor -ne $version.Minor -or $displayVersion.Build -ne $version.Build) {
        throw 'Versão do MSI principal inconsistente.'
    }
    $features = Get-MagoMsiInstallFeatures $database
    $mshFiles = @(Get-ChildItem -LiteralPath $item.DirectoryName -File -Filter 'MSH*.exe' | Where-Object {
        $_.VersionInfo.ProductName -match '^Mago Service Hub\b' -and
        $_.VersionInfo.ProductVersion -match '^\d+\.\d+\.\d+\.\d+$' -and
        [version]$_.VersionInfo.ProductVersion -eq $displayVersion
    })
    if ($mshFiles.Count -ne 1) { throw 'É necessário um único MSHSetup.exe da mesma versão na pasta do MSI principal.' }
    return [pscustomobject]@{ Path = $item.FullName; Version = $version; Type = 'Msi'; MshPath = $mshFiles[0].FullName; Features = $features }
}

function Get-MagoMsiInstallFeatures {
    param($Database)
    $installLevel = [int](Get-MagoMsiProperty $Database 'INSTALLLEVEL')
    if ($installLevel -lt 1) { throw 'INSTALLLEVEL inválido no MSI principal.' }
    $features = @()
    $hasBrazilianPortuguese = $false
    $view = $Database.OpenView('SELECT `Feature`, `Feature_Parent`, `Level` FROM `Feature`')
    try {
        [void]$view.Execute()
        while ($record = $view.Fetch()) {
            $name = [string]$record.StringData(1)
            $parent = [string]$record.StringData(2)
            $level = [int]$record.StringData(3)
            if ($name -eq 'Feat_pt_BR' -and $parent -eq 'Feat_Language_Packages') { $hasBrazilianPortuguese = $true; continue }
            if ($level -gt 0 -and $level -le $installLevel -and $parent -ne 'Feat_Language_Packages') { $features += $name }
        }
    } finally { [void]$view.Close() }
    if (-not $hasBrazilianPortuguese -or 'Feat_Mago4BR' -notin $features -or
        'Feat_Language_Packages' -notin $features -or 'Feat_TaskBuilderFramework' -notin $features) {
        throw 'Estrutura de funcionalidades do MSI principal diferente da esperada.'
    }
    $features += 'Feat_pt_BR'
    return ($features -join ',')
}

function Get-MagoMsiProperty {
    param($Database, [string]$Name)
    $view = $Database.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property``='$Name'")
    try { [void]$view.Execute(); $record = $view.Fetch(); if ($record) { return ([string]$record.StringData(1)).Trim() } }
    finally { [void]$view.Close() }
    return $null
}

function Get-MagoVerticalInfo {
    param([string]$Path, [version]$MainVersion)
    if ([IO.Path]::GetExtension($Path) -ine '.msi') { throw 'Selecione um arquivo .msi.' }
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $database = $installer.OpenDatabase($Path, 0)
    $name = Get-MagoMsiProperty $database 'ProductName'
    $maker = Get-MagoMsiProperty $database 'Manufacturer'
    $versionText = Get-MagoMsiProperty $database 'ProductVersion'
    $productCode = Get-MagoMsiProperty $database 'ProductCode'
    if ($name -notmatch '^Mago4 (Retail|CGM|Visibility|MCM|MSO)\b') {
        throw "MSI não reconhecido como vertical do Mago4: $Path"
    }
    $kind = $Matches[1]
    if ($maker -notmatch 'Microarea|Zucchetti') { throw "Fabricante não reconhecido: $maker" }
    if ($productCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { throw 'ProductCode do MSI inválido.' }
    $version = [version]$versionText
    if ($MainVersion -and ($version.Major -ne $MainVersion.Major -or $version.Minor -ne $MainVersion.Minor -or $version.Build -ne $MainVersion.Build)) {
        throw "$name ($version) não corresponde à versão principal $MainVersion."
    }
    return [pscustomobject]@{ Name = $name; Kind = $kind; Version = $version; ProductCode = $productCode; Path = (Get-Item -LiteralPath $Path).FullName }
}

function Test-MagoVerticalInstalled {
    param($Vertical)
    if (-not $Vertical.ProductCode) { throw 'ProductCode do vertical não informado.' }
    $installer = New-Object -ComObject WindowsInstaller.Installer
    if ([int]$installer.ProductState($Vertical.ProductCode) -ne 5) { return $false }
    $name = [string]$installer.ProductInfo($Vertical.ProductCode, 'ProductName')
    $version = [version]$installer.ProductInfo($Vertical.ProductCode, 'VersionString')
    return ($name -match "^Mago4 $([regex]::Escape($Vertical.Kind))\b" -and
        $version.Major -eq $Vertical.Version.Major -and
        $version.Minor -eq $Vertical.Version.Minor -and
        $version.Build -eq $Vertical.Version.Build)
}

function Select-MagoVerticals {
    param([string]$InstallerPath, [version]$Version, [string[]]$RequiredKinds = @())
    $folder = Split-Path $InstallerPath
    $candidates = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $folder -File -Filter '*.msi' -ErrorAction SilentlyContinue)) {
        try { $candidates += Get-MagoVerticalInfo -Path $file.FullName -MainVersion $Version } catch { }
    }
    $candidates = @($candidates | Sort-Object Kind, Version -Unique)
    Write-Phase 'Verticais disponíveis'
    for ($index = 0; $index -lt $candidates.Count; $index++) {
        Write-Host "  $($index + 1). $($candidates[$index].Name) — $($candidates[$index].Version)" -ForegroundColor White
    }
    if (-not $candidates.Count) { Write-Warn 'Nenhum MSI vertical reconhecido na pasta do instalador.' }
    Write-Host '  Informe números separados por vírgula; Enter seleciona nenhum.' -ForegroundColor DarkGray
    $answer = (Read-Host '  Verticais').Trim()
    $selected = @()
    if ($answer) {
        foreach ($part in ($answer -split ',')) {
            $number = 0
            if (-not [int]::TryParse($part.Trim(), [ref]$number) -or $number -lt 1 -or $number -gt $candidates.Count) {
                throw "Seleção inválida: $part"
            }
            $selected += $candidates[$number - 1]
        }
    }
    while (Confirm-MagoAction 'Adicionar outro MSI vertical manualmente?') {
        $path = Read-ExistingPath 'Caminho do MSI vertical' 'File' '.msi'
        if (-not $path) { continue }
        $selected += Get-MagoVerticalInfo -Path $path -MainVersion $Version
    }
    $selected = @($selected | Sort-Object Kind -Unique)
    foreach ($kind in $RequiredKinds) {
        if ($kind -notin @($selected | ForEach-Object Kind)) {
            Write-Warn "O vertical instalado '$kind' não será reinstalado."
        }
    }
    return ,$selected
}

function Install-MagoVerticals {
    param([object[]]$Verticals)
    $script:MagoVerticalInstallHadWarning = $false
    if (-not $Verticals.Count) { Write-Step 'Nenhum MSI vertical selecionado.'; return $true }
    Write-Phase "Instalando $($Verticals.Count) vertical(is)"
    foreach ($vertical in $Verticals) {
        if (-not $vertical.Path -or -not $vertical.Name -or -not $vertical.ProductCode) { throw 'Seleção de vertical inválida.' }
        $wasInstalled = Test-MagoVerticalInstalled $vertical
        $log = Join-Path (Get-MagoLogDirectory) ("vertical-{0}-{1:yyyyMMdd-HHmmss}.log" -f $vertical.Kind, (Get-Date))
        $args = "/i `"$($vertical.Path)`" /qn /norestart /L*v `"$log`""
        Write-Step "Instalando $($vertical.Name). Aguarde; esta etapa pode demorar e o processo não está travado."
        $proc = Start-Process msiexec.exe -ArgumentList $args -Wait -PassThru
        $isInstalled = Test-MagoVerticalInstalled $vertical
        if (-not $isInstalled) {
            Write-Fail "O MSI retornou $($proc.ExitCode) e o vertical $($vertical.Kind) não consta como instalado na versão esperada. Confira o log: $log"
            return $false
        }
        if ($proc.ExitCode -notin @(0, 3010, 1638)) {
            if ($wasInstalled) {
                Write-Fail "O MSI retornou $($proc.ExitCode) para um vertical que já estava instalado. Confira o log: $log"
                return $false
            }
            $script:MagoVerticalInstallHadWarning = $true
            Write-Warn "O MSI retornou $($proc.ExitCode), mas o Windows Installer registra $($vertical.Name) como instalado agora. Confira o log e valide o funcionamento: $log"
        } else { [void](Test-MagoExitCode $proc.ExitCode $vertical.Name) }
        Write-Step "Log: $log"
    }
    return $true
}

function Get-InstalledVerticalKinds {
    return @(Get-Mago4Entries | Where-Object { $_.DisplayName -match '^Mago4 (Retail|CGM|Visibility|MCM|MSO)\b' } | ForEach-Object {
        if ($_.DisplayName -match '^Mago4 (Retail|CGM|Visibility|MCM|MSO)\b') { $Matches[1] }
    } | Sort-Object -Unique)
}

function Invoke-MagoExeInstall {
    param([string]$Installer, [string]$Destination)
    $parent = Split-Path -Parent $Destination
    $instance = Split-Path -Leaf $Destination
    if ($instance -notmatch '^[A-Za-z0-9_-]+$') { throw 'O nome da pasta final deve conter apenas letras, números, hífen ou sublinhado.' }
    Write-Warn 'Na interface do instalador, selecione Português (Brasil) e o dicionário pt-BR.'
    Write-Step "Destino esperado: $Destination"
    # O parser de linha de comando do Windows exige duas barras antes da aspa final.
    $parentArgument = $parent.TrimEnd('\') + '\\'
    $args = "INSTALLLOCATION=`"$parentArgument`" INSTANCENAME=`"$instance`""
    $installStarted = Get-Date
    Write-Step 'Instalando o Mago4. Aguarde o instalador concluir; ele pode ficar vários minutos sem mudar a tela.'
    $proc = Start-Process -FilePath $Installer -ArgumentList $args -Wait -PassThru
    try {
        $burnLog = Get-ChildItem -LiteralPath $env:TEMP -File -Filter 'Microarea_Installer*.log' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $installStarted } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($burnLog) {
            $savedLog = Join-Path (Get-MagoLogDirectory) ("mago4-installer-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
            Copy-Item -LiteralPath $burnLog.FullName -Destination $savedLog -ErrorAction Stop
            Write-Step "Log do instalador: $savedLog"
        }
    } catch { Write-Warn "Não foi possível copiar o log do instalador: $($_.Exception.Message)" }
    if (-not (Test-MagoExitCode $proc.ExitCode 'Instalação principal')) { return $false }
    return (Test-MagoInstalledResult $Destination)
}

function Invoke-MagoMsiInstall {
    param($Installer, [string]$Destination)
    $parent = Split-Path -Parent $Destination
    $instance = Split-Path -Leaf $Destination
    if ($instance -notmatch '^[A-Za-z0-9_-]+$') { throw 'O nome da pasta final deve conter apenas letras, números, hífen ou sublinhado.' }
    $log = Join-Path (Get-MagoLogDirectory) ("mago4-msi-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
    $parentArgument = $parent.TrimEnd('\') + '\\'
    $dnchbx86 = if (Test-Path (Join-Path $env:SystemRoot 'SysWOW64\inetsrv\aspnetcore.dll')) { '1' } else { '0' }
    $dnchbx64 = if (Test-Path (Join-Path $env:SystemRoot 'System32\inetsrv\aspnetcore.dll')) { '1' } else { '0' }
    $args = "/i `"$($Installer.Path)`" /qn /norestart /L*v `"$log`" ALLUSERS=1 INSTANCENAME=`"$instance`" INSTALLLOCATION=`"$parentArgument`" UICULTURE=pt-BR ADDLOCAL=$($Installer.Features) DEFAULTWEBSITENAME=`"Default Web Site`" DEFAULTWEBSITEID=1 DEFAULTWEBSITEPORT=80 SKIPCLICKONCEDEPLOYER=0 DNCHBX86=$dnchbx86 DNCHBX64=$dnchbx64"
    Write-Step "Instalando o MSI principal sem interface. Aguarde; o processo pode demorar. Log: $log"
    $proc = Start-Process msiexec.exe -ArgumentList $args -Wait -PassThru
    if (-not (Test-MagoExitCode $proc.ExitCode 'MSI principal')) { return $false }
    if (-not (Invoke-MagoMshInstall $Installer.MshPath)) { return $false }
    return (Test-MagoInstalledResult $Destination)
}

function Invoke-MagoMshInstall {
    param([string]$MshPath)
    Write-Step 'Instalando Mago Service Hub sem interface. Aguarde; o processo pode demorar.'
    $msh = Start-Process -FilePath $MshPath -ArgumentList '/install /quiet /norestart' -Wait -PassThru
    return (Test-MagoExitCode $msh.ExitCode 'Mago Service Hub')
}

function Invoke-MagoMainInstall {
    param($Installer, [string]$Destination)
    if ($Installer.Type -eq 'Msi') { return (Invoke-MagoMsiInstall $Installer $Destination) }
    if ($Installer.Type -eq 'Exe') { return (Invoke-MagoExeInstall $Installer.Path $Destination) }
    throw 'Tipo de instalador principal inválido.'
}

function Test-MagoInstalledResult {
    param([string]$Destination)
    $record = Get-MagoInstallRecord
    if (-not $record -or [IO.Path]::GetFullPath($record.Path).TrimEnd('\') -ine [IO.Path]::GetFullPath($Destination).TrimEnd('\')) {
        Write-Fail 'O caminho registrado após a instalação não corresponde ao destino solicitado.'
        return $false
    }
    if (-not $record.Registry -or $record.Registry.UICulture -ine 'pt-BR' -or [string]$record.Registry.Dictionaries -notmatch '(?i)pt-BR') {
        Write-Fail 'A instalação não registrou UICulture e Dictionaries em pt-BR. Corrija pelo instalador antes de continuar.'
        return $false
    }
    $service = Get-Service W3SVC -ErrorAction SilentlyContinue
    Write-DiagLine 'Serviço IIS' $(if ($service -and $service.Status -eq 'Running') { 'ok' } else { 'warn' }) $service.Status 'Verifique o serviço W3SVC.'
    $instance = Split-Path -Leaf $Destination
    $endpoint = Test-HttpEndpoint -Url "http://localhost/$instance/m4server/account-manager/isAlive" -OkCodes @(200)
    Write-DiagLine 'M4Server isAlive' $(if ($endpoint.Ok) { 'ok' } else { 'warn' }) "HTTP $($endpoint.Code)" 'Verifique o site e os pools do IIS.'
    return $true
}

function Read-MagoDestination {
    Write-Host '  Você pode arrastar uma pasta para esta janela.' -ForegroundColor DarkGray
    $inputPath = (Read-Host "  Pasta final do Mago4 [Enter: $script:DefaultMagoPath]").Trim().Trim('"', "'")
    if (-not $inputPath) { $inputPath = $script:DefaultMagoPath }
    $path = [IO.Path]::GetFullPath($inputPath).TrimEnd('\')
    if (-not (Test-Path -LiteralPath ([IO.Path]::GetPathRoot($path)) -PathType Container)) {
        throw 'A unidade do destino não existe ou não é acessível.'
    }
    return $path
}

function Install-MissingMagoDependency {
    param([string]$Id, [string]$Arguments = '/install /quiet /norestart')
    $path = Get-Dependency -Id $Id
    if (-not $path) { return $false }
    Write-Step "Instalando dependência $Id. Aguarde; o processo pode demorar."
    $proc = Start-Process -FilePath $path -ArgumentList $Arguments -Wait -PassThru
    return (Test-MagoExitCode $proc.ExitCode $Id)
}

function Install-MissingMagoDependencies {
    Write-Phase 'Verificando dependências do Mago4'
    $iisEnabled = if (Get-IsWindowsServer) {
        (Get-WindowsFeature 'Web-Server' -ErrorAction SilentlyContinue).Installed
    } else {
        (Get-WindowsOptionalFeature -Online -FeatureName 'IIS-WebServerRole' -ErrorAction SilentlyContinue).State -in @('Enabled','EnablePending')
    }
    if (-not $iisEnabled) { Enable-IISFeatures }
    Enable-Mago4WindowsFeatures
    if (Get-IsWindowsServer) {
        foreach ($feature in @('Web-Server','NET-Framework-45-ASPNET')) {
            if (-not (Get-WindowsFeature $feature -ErrorAction SilentlyContinue).Installed) {
                Write-Fail "Feature obrigatória ausente: $feature"; return $false
            }
        }
    } else {
        foreach ($feature in @('IIS-WebServerRole','NetFx4Extended-ASPNET45')) {
            if ((Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue).State -notin @('Enabled','EnablePending')) {
                Write-Fail "Feature obrigatória ausente: $feature"; return $false
            }
        }
    }
    $entries64 = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue)
    $entries32 = @(Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue)
    if (-not @($entries32 | Where-Object { $_.DisplayName -match 'Visual C\+\+.*2015-2022.*x86' }).Count) {
        if (-not (Install-MissingMagoDependency 'vcredist-x86')) { return $false }
    }
    if (-not @($entries64 | Where-Object { $_.DisplayName -match 'Visual C\+\+.*2015-2022.*x64' }).Count) {
        if (-not (Install-MissingMagoDependency 'vcredist-x64')) { return $false }
    }
    $netFx = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
    if (-not $netFx -or [int]$netFx.Release -lt 528040) {
        if (-not (Install-MissingMagoDependency 'netfx48-devpack' '/q /norestart')) { return $false }
    }
    if (-not @(Get-ChildItem (Join-Path $env:ProgramFiles 'dotnet\sdk') -Directory -ErrorAction SilentlyContinue | Where-Object Name -Match '^10\.').Count) {
        if (-not (Install-MissingMagoDependency 'dotnet10-sdk')) { return $false }
    }
    $hosting = @(Get-ChildItem (Join-Path $env:ProgramFiles 'dotnet\shared\Microsoft.AspNetCore.App') -Directory -ErrorAction SilentlyContinue | Where-Object Name -Match '^10\.').Count
    if (-not $hosting -or -not (Test-Path (Join-Path $env:SystemRoot 'System32\inetsrv\aspnetcore.dll'))) {
        if (-not (Install-MissingMagoDependency 'dotnet10-hosting')) { return $false }
    }
    return $true
}

function Invoke-InstalarMago4 {
    Write-SectionHeader 'INSTALAR MAGO4'
    try {
        $installerPath = Read-ExistingPath 'Caminho do instalador principal .exe ou .msi' 'File'
        if (-not $installerPath) { return }
        $installer = Get-MagoInstallerInfo $installerPath
        $destination = Read-MagoDestination
        if (Get-MagoMainEntry) { throw 'O Mago4 já está instalado. Use Atualizar ou Reparar.' }
        if ((Test-Path -LiteralPath $destination) -and @(Get-ChildItem -LiteralPath $destination -Force).Count) {
            throw 'A pasta de destino contém arquivos. Escolha uma pasta vazia ou use Atualizar/Reparar.'
        }
        $verticals = Select-MagoVerticals $installer.Path $installer.Version
        Write-Step "Instalador: $($installer.Path)"
        if ($installer.Type -eq 'Msi') { Write-Step "MSH: $($installer.MshPath); idioma e dicionário: pt-BR; sem telas de instalação." }
        Write-Step "Destino: $destination"
        if (-not (Confirm-MagoAction 'Iniciar a instalação?')) { return }
        if (-not (Install-MissingMagoDependencies)) { throw 'Falha ao preparar dependências.' }
        if (-not (Invoke-MagoMainInstall $installer $destination)) { throw 'A instalação principal não passou na validação.' }
        if (-not (Install-MagoVerticals $verticals)) { throw 'Um vertical falhou.' }
        if ($script:MagoVerticalInstallHadWarning) { Write-Warn 'Mago4 instalado; um vertical retornou erro apesar do registro de instalação. Valide seu funcionamento.' }
        else { Write-Ok 'Mago4 instalado e validado.' }
    } catch { Write-Fail $_.Exception.Message }
    finally { Pause-Continue }
}

function Invoke-InstalarVerticaisMago4 {
    Write-SectionHeader 'INSTALAR VERTICAIS DO MAGO4'
    try {
        $record = Get-MagoInstallRecord
        if (-not $record) { throw 'Mago4 não está instalado. Use Instalar Mago4.' }
        $installerPath = Read-ExistingPath 'Caminho do instalador principal .exe ou .msi, para localizar os verticais' 'File'
        if (-not $installerPath) { return }
        $installer = Get-MagoInstallerInfo $installerPath
        $installedVersion = [version]$record.Entry.DisplayVersion
        if ($installer.Version.Major -ne $installedVersion.Major -or
            $installer.Version.Minor -ne $installedVersion.Minor -or
            $installer.Version.Build -ne $installedVersion.Build) {
            throw "A versão do instalador $($installer.Version) não corresponde ao Mago4 instalado $installedVersion."
        }
        $verticals = Select-MagoVerticals $installer.Path $installer.Version
        if (-not $verticals.Count) { Write-Warn 'Nenhum vertical selecionado.'; return }
        $installedKinds = @(Get-InstalledVerticalKinds)
        foreach ($vertical in $verticals) {
            if ($vertical.Kind -in $installedKinds) {
                throw "O vertical $($vertical.Kind) já está instalado. Use Atualizar Mago4 para substituí-lo."
            }
        }
        Write-Step "Mago4 instalado: $($record.Path)"
        if (-not (Confirm-MagoAction 'Instalar os verticais selecionados?')) { return }
        if (-not (Install-MagoVerticals $verticals)) { throw 'Falha na instalação de um vertical.' }
        if ($script:MagoVerticalInstallHadWarning) { Write-Warn 'Verticais registrados como instalados; houve erro de MSI. Valide seu funcionamento.' }
        else { Write-Ok 'Verticais instalados.' }
    } catch { Write-Fail $_.Exception.Message }
    finally { Pause-Continue }
}

function Invoke-ReparoSimplesMago4 {
    Write-SectionHeader 'REPARO SIMPLES DO MAGO4'
    try {
        $entry = Get-MagoMainEntry
        if (-not $entry) { throw 'Mago4 não está instalado.' }
        $guid = if ($entry.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') { $entry.PSChildName }
                elseif ($entry.UninstallString -match '(\{[0-9A-Fa-f-]{36}\})') { $Matches[1] }
                else { $null }
        if (-not $guid -or $entry.UninstallString -notmatch 'msiexec') { throw 'A entrada instalada não é um MSI reparável.' }
        if ($entry.NoRepair -eq 1) { throw 'O instalador desabilitou a opção de reparo.' }
        Write-Step "Produto: $($entry.DisplayName), código: $guid"
        if (-not (Confirm-MagoAction 'Executar o reparo MSI?')) { return }
        $log = Join-Path (Get-MagoLogDirectory) ("repair-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
        Write-Step 'Reparando o Mago4. Aguarde; o processo pode demorar.'
        $proc = Start-Process msiexec.exe -ArgumentList "/fomus $guid /L*v `"$log`"" -Wait -PassThru
        [void](Test-MagoExitCode $proc.ExitCode 'Reparo MSI')
        Write-Step "Log: $log"
    } catch { Write-Fail $_.Exception.Message }
    finally { Pause-Continue }
}

function Invoke-PostUpdateDependencies {
    foreach ($id in @('vcredist-x86','vcredist-x64','dotnet10-sdk','dotnet10-hosting')) {
        if (-not (Install-MissingMagoDependency $id)) { return $false }
    }
    return $true
}

function Invoke-AtualizarMago4 {
    Write-SectionHeader 'ATUALIZAR MAGO4'
    try {
        $record = Get-MagoInstallRecord
        if (-not $record) { throw 'Mago4 não está instalado. Use Instalar Mago4.' }
        if (-not (Test-Path -LiteralPath $record.Path -PathType Container)) { throw "Pasta instalada não encontrada: $($record.Path)" }
        $installerPath = Read-ExistingPath 'Novo instalador principal .exe ou .msi' 'File'
        if (-not $installerPath) { return }
        $installer = Get-MagoInstallerInfo $installerPath
        $kinds = Get-InstalledVerticalKinds
        $verticals = Select-MagoVerticals $installer.Path $installer.Version $kinds
        Write-Warn 'A atualização removerá a versão instalada antes de instalar a nova.'
        if ($installer.Type -eq 'Msi') { Write-Step "MSH: $($installer.MshPath); idioma e dicionário: pt-BR; sem telas de instalação." }
        Write-Step "Instalação atual: $($record.Path)"
        if (-not (Confirm-MagoAction 'Confirma que possui backup e quer atualizar?')) { return }
        $entries = @(Get-Mago4Entries)
        if (-not @($entries | Where-Object { $_.DisplayName -match '^Mago4-BR\b' }).Count) { throw 'Entrada principal desapareceu antes da desinstalação.' }
        if (-not (Invoke-MagoUninstall -Entries $entries)) { throw 'Falha na desinstalação; instalação nova não iniciada.' }
        if (Get-MagoMainEntry) { throw 'Mago4 ainda consta como instalado. Instalação nova cancelada.' }
        if (-not (Invoke-PostUpdateDependencies)) { throw 'Falha nas dependências pós-atualização.' }
        if (-not (Invoke-MagoMainInstall $installer $record.Path)) { throw 'Instalação principal não passou na validação.' }
        if (-not (Install-MagoVerticals $verticals)) { throw 'Falha na reinstalação de um vertical.' }
        if ($script:MagoVerticalInstallHadWarning) { Write-Warn 'Atualização concluída com erro de MSI em vertical registrado como instalado. Valide seu funcionamento.' }
        else { Write-Ok 'Atualização concluída.' }
    } catch { Write-Fail $_.Exception.Message }
    finally { Pause-Continue }
}

function Remove-MagoChildrenExcept {
    param([string]$Directory, [string]$KeepName, [string]$NestedKeep)
    if (-not (Test-Path -LiteralPath $Directory)) { return }
    foreach ($child in @(Get-ChildItem -LiteralPath $Directory -Force -ErrorAction Stop)) {
        if ($child.Name -ieq $KeepName -and $child.PSIsContainer -and $NestedKeep) {
            $parts = $NestedKeep -split '\\', 2
            $next = if ($parts.Count -gt 1) { $parts[1] } else { '' }
            Remove-MagoChildrenExcept $child.FullName $parts[0] $next
        } elseif ($child.Name -ieq $KeepName -and $child.PSIsContainer) {
            continue
        } else {
            Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop
        }
    }
}

function Assert-MagoTreeSafe {
    param([string]$Directory)
    foreach ($child in @(Get-ChildItem -LiteralPath $Directory -Force -ErrorAction Stop)) {
        if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Link/reparse point encontrado; limpeza cancelada: $($child.FullName)"
        }
        if ($child.PSIsContainer) { Assert-MagoTreeSafe $child.FullName }
    }
}

function Clear-MagoAdvancedFiles {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($full -match '^[A-Za-z]:\\?$') { throw 'Pasta final inválida para a limpeza avançada.' }
    if (-not (Test-Path -LiteralPath $full)) { Write-Warn 'Pasta já ausente após desinstalação; limpeza seletiva ignorada.'; return }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw 'Destino não é uma pasta.' }
    $item = Get-Item -LiteralPath $full -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'A pasta Mago4 é um link; limpeza cancelada.' }
    Assert-MagoTreeSafe $full
    Write-Step "Limpando seletivamente $full"
    $apps = Join-Path $full 'Apps'
    if (Test-Path -LiteralPath $apps) { Remove-Item -LiteralPath $apps -Recurse -Force -ErrorAction Stop }
    $custom = Join-Path $full 'Custom'
    # Companies e ReferencedAssemblies são preservadas integralmente.
    if (Test-Path -LiteralPath $custom) {
        foreach ($child in @(Get-ChildItem -LiteralPath $custom -Force)) {
            if ($child.Name -in @('ReferencedAssemblies','Companies')) { continue }
            Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop
        }
    }
    $standard = Join-Path $full 'Standard'
    Remove-MagoChildrenExcept $standard 'Taskbuilder' 'WebFramework\LoginManager\App_Data'
    foreach ($child in @(Get-ChildItem -LiteralPath $full -File -Force)) {
        Remove-Item -LiteralPath $child.FullName -Force -ErrorAction Stop
    }
    Write-Ok 'Limpeza seletiva concluída.'
}

function Save-MagoSession {
    param($State, [string]$Directory)
    $temporary = Join-Path $Directory 'state.json.part'
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporary -Encoding UTF8 -ErrorAction Stop
    Move-Item -LiteralPath $temporary -Destination (Join-Path $Directory 'state.json') -Force
}

function Protect-MagoSessionDirectory {
    param([string]$Path)
    $acl = Get-Acl -LiteralPath $Path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
        $identity = [System.Security.Principal.SecurityIdentifier]::new($sid)
        $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'
        )
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}

function New-MagoResumeSession {
    param([string]$Installer, [string]$Destination, [object[]]$Verticals)
    $id = [guid]::NewGuid().ToString()
    $directory = Join-Path $script:SessionRoot $id
    New-Item -ItemType Directory -Path $script:SessionRoot -Force -ErrorAction Stop | Out-Null
    Protect-MagoSessionDirectory $script:SessionRoot
    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
    Protect-MagoSessionDirectory $directory
    Copy-Item -LiteralPath (Join-Path $script:ModuleRoot 'src') -Destination $directory -Recurse -ErrorAction Stop
    Copy-Item -LiteralPath (Join-Path $script:ModuleRoot 'modules.json') -Destination $directory -ErrorAction Stop
    Copy-Item -LiteralPath $script:BootstrapPath -Destination (Join-Path $directory 'bootstraper.ps1') -ErrorAction Stop
    if ($script:ManifestLocalPath) {
        Copy-Item -LiteralPath $script:ManifestLocalPath -Destination (Join-Path $directory 'manifest.json') -ErrorAction Stop
    }
    $state = [pscustomobject]@{
        Schema = 1; Id = $id; Stage = 'PostReboot'; Installer = $Installer; CodeRef = $script:CodeRef;
        MainVersion = [string](Get-MagoInstallerInfo $Installer).Version;
        Destination = $Destination; Verticals = @($Verticals | ForEach-Object Path)
    }
    Save-MagoSession $state $directory
    $taskName = "Mago4-Setup-Resume-$id"
    try {
        $bootstrap = Join-Path $directory 'bootstraper.ps1'
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$bootstrap`" -Local -ResumeId $id"
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
        $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Ok "Retomada automática preparada: $taskName"
    } catch {
        Write-Warn "Não foi possível criar a tarefa automática: $($_.Exception.Message)"
        Write-Warn 'Após reiniciar, execute novamente o comando público do bootstrap para retomar.'
    }
    return $id
}

function Invoke-MagoResume {
    param([string]$ResumeId)
    $directory = Join-Path $script:SessionRoot $ResumeId
    $statePath = Join-Path $directory 'state.json'
    if (-not (Test-Path -LiteralPath $statePath)) { throw 'Estado de reparo avançado não encontrado.' }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.Schema -ne 1 -or $state.Id -ine $ResumeId -or $state.Stage -notin @('PostReboot','InstallMain','InstallVerticals')) {
        throw 'Estado de retomada inválido.'
    }
    if ($state.CodeRef) {
        if ([string]$state.CodeRef -notmatch '^[0-9a-fA-F]{40}$') { throw 'Revisão da sessão inválida.' }
        $script:CodeRef = [string]$state.CodeRef
        $script:ManifestUrl = "https://raw.githubusercontent.com/Zucchetti-ERP/Mago-Deps/$($state.CodeRef)/manifest.json"
        $script:ManifestLocalPath = $null
    }
    $lock = Join-Path $directory 'run.lock'
    if ((Test-Path -LiteralPath $lock) -and (Get-Item -LiteralPath $lock).CreationTime -lt (Get-Date).AddHours(-2)) {
        Remove-Item -LiteralPath $lock -Recurse -Force
    }
    New-Item -ItemType Directory -Path $lock -ErrorAction Stop | Out-Null
    try {
        Write-SectionHeader 'RETOMADA DO REPARO AVANÇADO'
        Write-Step "Sessão: $ResumeId"
        if ($state.Stage -eq 'PostReboot') {
            if (-not (Invoke-PostUpdateDependencies)) { throw 'Falha nas dependências após reinício.' }
            $state.Stage = 'InstallMain'; Save-MagoSession $state $directory
        }
        if ($state.Stage -eq 'InstallMain') {
            $mainInstalled = Get-MagoMainEntry
            $installerInfo = $null
            try { $installerInfo = Get-MagoInstallerInfo $state.Installer }
            catch { Write-Warn "Instalador principal ou MSH não está acessível após o reinício: $($_.Exception.Message)" }
            if (-not $installerInfo) {
                $replacement = Read-ExistingPath 'Novo caminho do instalador principal .exe ou .msi' 'File'
                if (-not $replacement) { throw 'Instalador principal necessário para retomar.' }
                $installerInfo = Get-MagoInstallerInfo $replacement
                $state.Installer = $replacement
                $state.MainVersion = [string]$installerInfo.Version
                Save-MagoSession $state $directory
            }
            $ok = if ($mainInstalled) {
                $valid = Test-MagoInstalledResult $state.Destination
                if ($valid -and $installerInfo.Type -eq 'Msi') { $valid = Invoke-MagoMshInstall $installerInfo.MshPath }
                $valid
            } else { Invoke-MagoMainInstall $installerInfo $state.Destination }
            if (-not $ok) { throw 'Instalação principal falhou ou não passou na validação.' }
            $state.Stage = 'InstallVerticals'; Save-MagoSession $state $directory
        }
        if ($state.Stage -eq 'InstallVerticals') {
            $version = [version]$state.MainVersion
            $verticals = @($state.Verticals | ForEach-Object {
                if (Test-Path -LiteralPath $_ -PathType Leaf) { Get-MagoVerticalInfo -Path $_ -MainVersion $version }
                else { Write-Warn "MSI vertical indisponível e não reinstalado: $_" }
            })
            if (-not (Install-MagoVerticals $verticals)) { throw 'Falha na instalação de um vertical.' }
        }
        Unregister-ScheduledTask -TaskName "Mago4-Setup-Resume-$ResumeId" -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $statePath -Force
        if ($script:MagoVerticalInstallHadWarning) { Write-Warn 'Reparo avançado concluído com erro de MSI em vertical registrado como instalado. Valide seu funcionamento.' }
        else { Write-Ok 'Reparo avançado concluído.' }
    } finally {
        Remove-Item -LiteralPath $lock -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-MagoPendingSession {
    if (-not (Test-Path -LiteralPath $script:SessionRoot)) { return $false }
    $states = @(Get-ChildItem -LiteralPath $script:SessionRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName 'state.json')
    })
    if (-not $states.Count) { return $false }
    if ($states.Count -gt 1) { throw 'Há múltiplos reparos avançados pendentes. Verifique ProgramData\Mago4-Setup\Sessions.' }
    $id = $states[0].Name
    if ($id -notmatch '^[0-9a-fA-F-]{36}$') { throw 'Identificador de retomada inválido.' }
    $bootstrap = Join-Path $states[0].FullName 'bootstraper.ps1'
    if (-not (Test-Path -LiteralPath $bootstrap)) { throw 'Bootstrap salvo para retomada não encontrado.' }
    Write-Warn "Reparo avançado pendente encontrado: $id"
    & $bootstrap -Local -ResumeId $id
    return $true
}

function Invoke-ReparoAvancadoMago4 {
    Write-SectionHeader 'REPARO AVANÇADO DO MAGO4'
    try {
        if (Invoke-MagoPendingSession) { return }
        $record = Get-MagoInstallRecord
        if (-not $record) { throw 'Mago4 não está instalado.' }
        $installerPath = Read-ExistingPath 'Instalador principal .exe ou .msi' 'File'
        if (-not $installerPath) { return }
        $installer = Get-MagoInstallerInfo $installerPath
        $kinds = Get-InstalledVerticalKinds
        $verticals = Select-MagoVerticals $installer.Path $installer.Version $kinds
        $destination = $record.Path
        if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
            $destination = Read-ExistingPath 'Pasta final da instalação atual' 'Directory'
            if (-not $destination) { return }
        }
        Write-Host ''
        Write-Host '  ATENÇÃO: ESTA OPERAÇÃO APAGA ARQUIVOS DA INSTALAÇÃO.' -ForegroundColor Red
        Write-Warn "Pasta afetada: $destination"
        if ($installer.Type -eq 'Msi') { Write-Step "MSH: $($installer.MshPath); idioma e dicionário: pt-BR; sem telas de instalação." }
        Write-Warn 'Apps, Custom\ESP, arquivos soltos e parte de Standard serão removidos.'
        Write-Warn 'Companies, ReferencedAssemblies e LoginManager\App_Data serão preservados.'
        if (-not (Confirm-MagoAction 'Você confirma que possui backup?')) { return }
        if (-not (Confirm-MagoAction 'Confirma o reparo destrutivo da pasta exibida?')) { return }
        $entries = @(Get-Mago4Entries)
        if (-not @($entries | Where-Object { $_.DisplayName -match '^Mago4-BR\b' }).Count) { throw 'Entrada principal desapareceu antes da desinstalação.' }
        if (-not (Invoke-MagoUninstall -Entries $entries)) { throw 'Falha na desinstalação; limpeza não iniciada.' }
        if (Get-MagoMainEntry) { throw 'Mago4 ainda consta como instalado. Limpeza cancelada.' }
        Clear-MagoAdvancedFiles $destination
        Clear-TempFiles
        $id = New-MagoResumeSession $installer.Path $destination $verticals
        Write-Warn "É necessário reiniciar. Sessão: $id"
        $answer = (Read-Host '  Reiniciar após 30 segundos [R] ou reiniciar manualmente [M]?').Trim().ToUpperInvariant()
        if ($answer -eq 'R') {
            Write-Step 'Reinício em 30 segundos. Salve seu trabalho.'
            Start-Sleep -Seconds 30
            Restart-Computer -Force
        } else {
            Write-Warn 'Reinicie a máquina manualmente. A retomada ocorrerá após o boot ou na próxima execução do script.'
        }
    } catch { Write-Fail $_.Exception.Message }
    finally { Pause-Continue }
}
