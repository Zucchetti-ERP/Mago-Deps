# Mago-Deps

Script interativo para preparar, diagnosticar e manter uma instalação Windows do Mago4.

## Iniciar

No Windows PowerShell, execute:

```powershell
irm https://raw.githubusercontent.com/Zucchetti-ERP/Mago-Deps/refs/heads/master/bootstraper.ps1 | iex
```

O script solicita elevação administrativa. Ele resolve um commit do repositório, baixa os módulos desse mesmo commit por HTTPS e confere o SHA-256 de cada arquivo antes de carregá-lo. A publicação deve incluir `bootstraper.ps1`, `modules.json` e todos os arquivos em `src/` no mesmo commit.

Para desenvolvimento local, execute `powershell.exe -File .\bootstraper.ps1 -Local`. Para testar a carga sem abrir o menu, use `-Local -NoMenu` em uma janela elevada. `-Ref <SHA-40>` carrega uma revisão remota específica.

Para testar uma branch antes de publicar em `master`, informe a branch ao carregador na mesma sessão:

```powershell
$env:MAGO_DEPS_BRANCH = 'test'
irm https://raw.githubusercontent.com/Zucchetti-ERP/Mago-Deps/refs/heads/test/bootstraper.ps1 | iex
Remove-Item Env:MAGO_DEPS_BRANCH
```

O conteúdo recebido por `irm | iex` não informa ao script a URL de origem. Por isso a variável `MAGO_DEPS_BRANCH` deve acompanhar a URL usada. Em uma chamada local também é possível passar `-Branch test`.

## Menu

1. **Instalação de Dependências:** mantém os perfis de instalação completos, Mago4, MSH, pós-atualização, IIS e dependência individual.
2. **Opções de reparo:** Corrigir RabbitMQ, Reparar erro .NET Core, Reparo simples do Mago4 e Reparo avançado do Mago4.
3. **Diagnósticos:** Verificação de Dependências e Diagnóstico Completo do Sistema.
4. **Opções de Limpeza:** Limpeza Simples e Desinstalar Mago4. A antiga Limpeza Completa foi removida.
5. **Instalação ou Atualização do Mago4:** Instalar Mago4, Atualizar Mago4 e instalar verticais numa instalação existente.

As operações que removem instalações ou arquivos pedem confirmação. Nenhuma opção é executada automaticamente ao abrir o menu.

## Instalar, atualizar e reparar

**Instalar Mago4** solicita o instalador principal (`.exe` ou `.msi`) e a pasta final, verifica instalações existentes, prepara dependências ausentes, localiza MSIs verticais na pasta do instalador e permite adicionar outros manualmente. Uma instalação existente ou uma pasta de destino ocupada bloqueia o fluxo. Com o `.exe`, o instalador abre com interface: selecione **Português (Brasil)** e o dicionário `pt-BR`. Com o `.msi`, coloque o `MSHSetup*.exe` da mesma versão na mesma pasta; o script instala o MSI e o Mago Service Hub sem interface, selecionando `pt-BR` e as funcionalidades padrão do MSI. Em ambos os casos, valida o caminho, `UICulture` e `Dictionaries` antes de instalar os verticais. As etapas demoradas mostram uma mensagem para aguardar.

No instalador do Mago4, `INSTALLLOCATION` recebe a **pasta pai**, enquanto `INSTANCENAME` compõe a pasta final. O destino padrão é `C:\Program Files (x86)\Microarea\Mago4`. A validação após a instalação interrompe o fluxo se o instalador usar um caminho diferente. A opção `.msi` usa `ADDLOCAL` com as funcionalidades padrão e `Feat_pt_BR`; ela não instala o Mago4 App Pool Manager incluído no pacote `.exe`.

**Atualizar Mago4** identifica a instalação e os verticais, solicita os novos instaladores, remove verticais antes do produto principal, executa as dependências pós-atualização e instala a versão nova no caminho registrado. Verticais sem MSI novo são avisados e não reinstalados.

**Instalar verticais no Mago4 existente** localiza os MSIs junto ao instalador principal informado, verifica a versão instalada e instala apenas os verticais selecionados. Use esta opção para completar uma instalação que terminou sem os verticais, sem reinstalar o produto principal. Se um MSI retornar erro após instalar um vertical novo, o script consulta o Windows Installer pelo `ProductCode` e pela versão: continua com aviso somente quando a instalação for confirmada; nos demais casos, interrompe e indica o log.

**Reparo simples** invoca apenas o reparo MSI do Mago4 instalado, com log detalhado. **Reparo avançado** remove a instalação, faz uma limpeza seletiva, reinicia a máquina e retoma a instalação. Ele preserva integralmente `Custom\Companies`, `Custom\ReferencedAssemblies` e `Standard\Taskbuilder\WebFramework\LoginManager\App_Data` quando existirem. A retomada usa uma tarefa no próximo login do administrador que iniciou o reparo; se ela não puder ser criada ou falhar, execute novamente o comando público para localizar a sessão pendente. Não inicie uma segunda operação enquanto houver reparo pendente.

**Reparar erro .NET Core** reinstala o Hosting Bundle atual e oferece diagnóstico adicional de leitura: runtimes e SDKs, módulo AspNetCore, permissões, `config.json`, endpoint `isAlive` e logs existentes. Pode salvar `dotnet --info` e um resumo local em `%ProgramData%\Mago4-Setup\Logs`. Alterações de antivírus, permissões amplas, `hosts`, `web.config` e teste manual com `dotnet web-server.dll` são apenas orientações; o script não as executa.

## Organização e manutenção

- `bootstraper.ps1`: entrada pública, elevação, revisão fixa, download, validação e carga.
- `modules.json`: ordem e hashes SHA-256 dos módulos.
- `src/Core`: estado compartilhado, saída e HTTP.
- `src/Dependencies`: manifest e instalação de pré-requisitos.
- `src/Operations`: instalação, limpeza, reparo, verificação e diagnóstico.
- `src/UI`: menus e navegação.
- `manifest.json`: metadados das dependências.

Depois de modificar qualquer módulo, execute `python tools/update-modules-manifest.py` e publique o `modules.json` atualizado junto com os módulos. Os logs operacionais ficam em `%ProgramData%\Mago4-Setup\Logs`; sessões pendentes de reparo avançado ficam em `%ProgramData%\Mago4-Setup\Sessions`.

Os módulos `.ps1` usam UTF-8 com BOM para Windows PowerShell 5.1. O `bootstraper.ps1` usa ASCII sem BOM para funcionar com `irm | iex`. Os arquivos são armazenados sem conversão de fim de linha no Git, pois os hashes precisam refletir exatamente os bytes publicados. Os testes locais não destrutivos são `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\BootstrapSmoke.ps1` e `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Smoke.ps1`.
