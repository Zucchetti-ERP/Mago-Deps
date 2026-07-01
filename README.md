# Mago-Deps

Repositório de dependências e script de bootstrap para instalação e manutenção do ambiente **Mago4** (e serviços relacionados, como o **Mago Service Hub / MSH**) em máquinas Windows.

O coração do repositório é o `bootstraper.ps1`: um script PowerShell interativo, com menus, que automatiza a instalação de todos os pré-requisitos do Mago4 (IIS, .NET, Visual C++ Redistributable, RabbitMQ, etc.), além de oferecer ferramentas de diagnóstico, verificação e limpeza do ambiente.

## Para que serve

O `bootstraper.ps1` existe para eliminar o trabalho manual (e propenso a erros) de preparar um servidor/estação para rodar o Mago4. Com ele é possível:

- Instalar de forma automatizada todas as dependências de sistema exigidas pelo Mago4 e pelo MSH (IIS, ASP.NET, WCF, .NET, Visual C++ Redistributable, IIS URL Rewrite, Erlang e RabbitMQ).
- Verificar rapidamente quais dependências já estão instaladas na máquina e em quais versões.
- Diagnosticar problemas comuns do ambiente (features do IIS, serviços, conectividade dos endpoints do Mago4).
- Limpar arquivos temporários e resíduos de instalações anteriores, ou desinstalar o Mago4 por completo.
- Reparar erros comuns relacionados ao .NET Core/.NET no IIS.

O script consulta um `manifest.json` publicado neste mesmo repositório para saber onde baixar cada dependência (URLs diretas, feeds oficiais do .NET ou arquivos hospedados no próprio repositório), então as versões instaladas podem mudar com o tempo sem que este manual precise ser atualizado.

## Como iniciar

O script deve ser executado em uma janela do **PowerShell**, em uma máquina **Windows**, com conexão à internet (para baixar o manifest e as dependências).

Execute o comando abaixo (não é necessário abrir o PowerShell como Administrador manualmente — o próprio script solicita elevação automaticamente via UAC caso não esteja rodando como administrador):

```powershell
irm https://raw.githubusercontent.com/Zucchetti-ERP/Mago-Deps/refs/heads/master/bootstraper.ps1 | iex
```

Ao iniciar, o script exibe um menu principal numerado. Basta digitar o número da opção desejada e pressionar Enter. Para voltar a um menu anterior ou sair, use a opção `0`.

## Menu principal

### 1 — Instalar dependências Mago4

Abre um submenu com diferentes perfis e opções de instalação de dependências, para cobrir tanto uma instalação nova quanto cenários específicos:

- **Instalação de dependências completa (IIS + Mago4 + MSH)** — executa, em sequência, a habilitação das features do IIS, a instalação das dependências do Mago4 (Visual C++ Redistributable, .NET, ASP.NET/WCF) e a instalação das dependências do MSH (IIS URL Rewrite, Erlang e RabbitMQ). É o fluxo recomendado para preparar uma máquina do zero.
- **Instalação de dependências Mago4** — instala apenas o que o Mago4 em si precisa: Visual C++ Redistributable, .NET, o Developer Pack do .NET Framework e as features de ASP.NET/WCF no Windows.
- **Instalação de dependências MSH** — instala apenas o que o Mago Service Hub precisa: o módulo IIS URL Rewrite e o par Erlang + RabbitMQ (incluindo a configuração do serviço e do plugin de gerenciamento do RabbitMQ).
- **Instalação básica pós-atualização** — instala somente o Visual C++ Redistributable e o .NET, para cenários em que a máquina já teve o restante configurado anteriormente e só precisa atualizar esses dois componentes (por exemplo, após uma atualização de versão do Mago4).
- **Instalação IIS** — habilita apenas as features do IIS necessárias para hospedar o Mago4 (funciona tanto em Windows Desktop quanto em Windows Server, com listas de features apropriadas para cada caso).
- **Instalar dependência individual** — abre outro submenu permitindo instalar item por item, de forma isolada: Visual C++ Redistributable (x86 e x64 separadamente), .NET SDK, .NET Hosting Bundle, .NET Framework Developer Pack, IIS URL Rewrite, ou apenas habilitar as features do IIS. Útil para corrigir ou reinstalar um componente específico sem repetir todo o processo.

> As opções de instalação completa e de dependências Mago4 pressupõem que o Mago4 ainda não esteja instalado na máquina.

### 2 — Instalar/Corrigir RabbitMQ

Reinstala o par Erlang + RabbitMQ do zero: remove qualquer instalação anterior (processos, serviço, pastas em Program Files e dados em AppData), instala as versões atuais, registra e inicia o serviço do RabbitMQ e habilita o plugin de gerenciamento (painel web). Use esta opção sempre que o RabbitMQ estiver com problemas, corrompido, ou precisar ser reconfigurado.

### 3 — Verificação de dependências

Varre o sistema (registro do Windows, pastas de instalação do .NET, serviços) e exibe uma tabela simples indicando, para cada dependência (.NET SDK, .NET Hosting Bundle, Erlang, RabbitMQ, IIS URL Rewrite), se ela está instalada e qual a versão encontrada — incluindo o status do serviço do RabbitMQ quando aplicável. É uma checagem rápida, sem fazer nenhuma alteração no sistema.

### 4 — Limpar ambiente

Abre um submenu com opções de limpeza, em ordem crescente de impacto:

- **Limpeza simples** — reinicia o IIS e remove arquivos temporários do Windows e da pasta de arquivos temporários do ASP.NET (`Temporary ASP.NET Files`, nas variantes de framework/arquitetura). Operação segura e não destrutiva, útil para resolver problemas de cache ou compilação do ASP.NET.
- **Limpeza completa** — além da limpeza simples, remove por completo a pasta de instalação do Mago4 (`C:\Program Files (x86)\Microarea`). **É uma operação destrutiva e irreversível**, por isso o script bloqueia essa opção se detectar que o Mago4 ainda está instalado (peça para desinstalá-lo primeiro, opção 3 deste submenu) e exige duas confirmações explícitas do usuário antes de prosseguir.
- **Desinstalar Mago4** — localiza as instalações do Mago4-BR, Mago Service Hub e do Microarea Installer no registro do Windows e as desinstala (via MSI ou via bootstrapper, conforme o caso), após confirmação do usuário.

### 5 — Reparar erro .NET Core

Reinstala o Hosting Bundle do .NET usado pelo IIS para hospedar aplicações .NET. Use esta opção quando o Mago4 apresentar o erro clássico de ".NET Core" ou similar relacionado ao módulo do .NET Core/.NET no IIS — a reinstalação do hosting bundle costuma resolver o problema sem precisar reconfigurar o restante do ambiente.

### 6 — Diagnóstico do sistema

Executa uma checagem abrangente e somente-leitura do ambiente, exibida em seções:

- **Sistema** — versão e build do Windows, indicando se é compatível com o Mago4.
- **Funcionalidades IIS** — verifica se o IIS, o ASP.NET, o WebSockets e o Application Init estão habilitados.
- **Dependências** — verifica a presença e versão do Visual C++ Redistributable (x86/x64), .NET SDK, .NET Hosting Bundle, .NET Framework Developer Pack, IIS URL Rewrite, Erlang e RabbitMQ (incluindo o status do serviço).
- **Conectividade** — testa se o painel de gerenciamento do RabbitMQ (porta 15672) está respondendo.
- **Mago4** — identifica se o Mago4-BR e/ou o Mago Service Hub estão instalados e, se estiverem, testa se as URLs de Backend, Frontend e LoginManager do Mago4 estão respondendo localmente via IIS.

Para cada item com problema, o diagnóstico sugere qual opção do menu principal usar para corrigi-lo.

### 0 — Sair

Encerra o script.
