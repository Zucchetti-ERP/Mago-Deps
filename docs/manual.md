# Mini-manual: instalar, atualizar e reparar o Mago4

Este manual cobre o uso do script **Mago-Deps** para instalar, atualizar e reparar o Mago4 em servidores e estações Windows.

---

## 1. Como abrir o script

1. Abra o **Windows PowerShell** (de preferência como administrador; o script pede elevação se for preciso).
2. Execute:

   ```powershell
   irm https://raw.githubusercontent.com/Zucchetti-ERP/Mago-Deps/refs/heads/master/bootstraper.ps1 | iex
   ```

   Se aparecer *"a execução de scripts foi desabilitada neste sistema"*, libere para o seu usuário (não precisa de administrador) e rode o comando de novo:

   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
   ```

   Se o erro continuar, a política pode vir de GPO (confira com `Get-ExecutionPolicy -List`). Nesse caso, procure o time de TI.

3. O menu principal aparece:

   | Opção | Menu                                   |
   |-------|----------------------------------------|
   | 1     | Instalação de Dependências             |
   | 2     | Opções de reparo                       |
   | 3     | Diagnósticos                           |
   | 4     | Opções de Limpeza                      |
   | 5     | Instalação ou Atualização do Mago4     |
   | 0     | Sair                                   |

Nada é executado ao abrir o menu. Toda operação que remove arquivos ou instalações pede confirmação.

> **Dica:** nos campos que pedem caminho de arquivo ou pasta, clique no item no Explorer com **Shift + botão direito → Copiar como caminho** e cole na janela (botão direito ou Ctrl+V). Arrastar e soltar não funciona, porque o Windows bloqueia essa ação em janelas executadas como administrador.

---

## 2. Antes de começar

- Deixe na **mesma pasta** o instalador principal do Mago4 (`.exe` ou `.msi`) e os **MSIs dos verticais** (Retail, CGM, Visibility, MCM, MSO). O script procura os verticais nessa pasta.
- Se usar o **`.msi`**, coloque também o **`MSHSetup*.exe` da mesma versão** nessa pasta (veja a seção 3).
- Todos os instaladores devem ser da **mesma versão** (major.minor.build). Versões diferentes são recusadas.
- **Backup do banco de dados:** obrigatório antes de uma **atualização que altera o banco de dados**. Os reparos não mexem no banco e não exigem backup.
- Os logs ficam em `%ProgramData%\Mago4-Setup\Logs`.

---

## 3. `.exe` ou `.msi`: qual usar?

> **Novidade:** a partir de agora, o time de **QA** distribui o instalador do Mago4 nos **dois formatos**: **`.exe`** e **`.msi` + MSH** (`MSHSetup*.exe`). Escolha o formato conforme a tabela abaixo. Se optar pelo `.msi`, copie também o MSH do mesmo pacote para a pasta do instalador.

O script aceita os dois formatos do instalador principal. Diferenças:

| Aspecto | **`.exe`** (Microarea Installer) | **`.msi`** (Mago4-BR) |
|---|---|---|
| Interface | **Com telas**: o técnico acompanha o assistente. | **Sem telas** (silencioso, `/qn`). |
| Idioma e dicionário (sempre **pt-BR**) | Selecione na tela **Português (Brasil)** e o dicionário **pt-BR**. | O script define pt-BR automaticamente. |
| Mago Service Hub (MSH) | Já vem incluído no pacote. | **Não vem incluído.** É obrigatório ter **um único** `MSHSetup*.exe` da mesma versão na pasta do MSI. O script o instala em seguida, também sem telas. |
| Funcionalidades | As definidas no assistente. | As funcionalidades padrão do MSI. |
| Log | O script copia o log do instalador (`mago4-installer-*.log`) para a pasta de logs. | Log detalhado do MSI (`mago4-msi-*.log`) gravado na pasta de logs. |
| Quando preferir | Primeira instalação assistida. | Instalações e atualizações sem interação, padronizadas e repetíveis. |

Nos dois casos, ao final o script **valida** a instalação:

- a pasta registrada é igual à pasta escolhida;
- idioma e dicionário estão em **pt-BR**;
- o serviço do IIS (W3SVC) está em execução;
- o endpoint `http://localhost/<instância>/m4server/account-manager/isAlive` responde.

Se a validação falhar, o fluxo para **antes** de instalar os verticais.

---

## 4. Instalar o Mago4

**Menu 5 → 1. Instalar Mago4**

Use para uma máquina **sem** Mago4. Se o Mago4 já estiver instalado ou a pasta de destino tiver arquivos, o script recusa (use Atualizar ou Reparar).

Passo a passo:

1. Informe o caminho do instalador principal (`.exe` ou `.msi`).
2. Informe a pasta final. Pressione **Enter** para o padrão `C:\Program Files (x86)\Microarea\Mago4`.
   - O nome da última pasta (a "instância") aceita apenas letras, números, `-` e `_`. Ele também compõe a URL do Mago4.
3. Escolha os verticais na lista, digitando números separados por vírgula (ex.: `1,3`). **Enter** = nenhum. Você pode adicionar outros MSIs manualmente.
4. Confira o resumo e confirme.
5. O script:
   1. instala as dependências que estiverem faltando (IIS e features do Windows, VC++ x86/x64, .NET Framework 4.8, .NET 10 SDK e Hosting Bundle);
   2. instala o Mago4 (`.exe` com telas ou `.msi` + MSH sem telas);
   3. valida a instalação;
   4. instala os verticais selecionados.

> Algumas etapas demoram vários minutos sem mudar a tela. **Não feche a janela**: o processo não está travado.

### Instalar só os verticais

**Menu 5 → 3. Instalar verticais no Mago4 existente**

Use quando o Mago4 já está instalado, mas faltou algum vertical. Informe o instalador principal da **mesma versão** instalada; ele só serve para localizar os MSIs na pasta. Verticais que já estão instalados são recusados (para substituí-los, use Atualizar).

---

## 5. Atualizar o Mago4

**Menu 5 → 2. Atualizar Mago4**

1. O script identifica a instalação atual (pasta e verticais).
2. Informe o **novo** instalador principal (`.exe` ou `.msi`).
3. Selecione os novos MSIs dos verticais. Se um vertical instalado não tiver MSI novo, você recebe um aviso: ele **não será reinstalado**.
4. Confirme a atualização. Se a nova versão altera o banco de dados, o **backup do banco é obrigatório** antes de continuar; o script exibe esse aviso.
5. O script:
   1. desinstala os verticais e depois o Mago4 atual;
   2. reinstala as dependências pós-atualização (VC++, .NET 10 SDK e Hosting Bundle);
   3. instala a nova versão **na mesma pasta** registrada;
   4. valida e instala os verticais.

Se a desinstalação falhar, a instalação nova não começa.

---

## 6. Reparar o Mago4

**Menu 2. Opções de reparo**

| Opção | Quando usar | O que faz |
|---|---|---|
| **Corrigir RabbitMQ** | Problemas com filas e mensageria. | Instala ou corrige Erlang e RabbitMQ. |
| **Reparar erro .NET Core** | Erros 500.x, M4Server sem resposta, falhas do AspNetCore. | Reinstala o .NET 10 Hosting Bundle e oferece um diagnóstico **somente leitura** (veja abaixo). |
| **Reparo simples do Mago4** | Arquivos corrompidos ou ausentes, configuração ok. | Executa o reparo do Windows Installer (`msiexec /fomus`) com log `repair-*.log`. **Não apaga nada.** |
| **Reparo avançado do Mago4** | O reparo simples não resolveu. | Desinstala, limpa, reinicia e reinstala (veja abaixo). **Destrutivo.** |

### Diagnóstico .NET Core

Depois de reinstalar o Hosting Bundle, o script pode mostrar runtimes e SDKs, o módulo AspNetCore no IIS, o estado dos pools, as permissões das pastas, o `config.json`, o endpoint `isAlive` e os logs existentes. Ele também pode salvar `dotnet --info` e um resumo em `%ProgramData%\Mago4-Setup\Logs`.

Itens como antivírus, permissões amplas, `hosts`, `web.config` e teste manual com `dotnet web-server.dll` são **apenas orientações**: o script não altera nada disso.

> Revise os logs antes de compartilhá-los: eles podem conter dados sensíveis.

### Reparo avançado: passo a passo

1. Informe o instalador principal (`.exe` ou `.msi`) e selecione os verticais.
2. Responda às **duas confirmações** do script. O reparo **não afeta o banco de dados**; ele atua só nos arquivos da instalação, e as pastas com dados das empresas são preservadas (veja abaixo).
3. O script desinstala o Mago4 e os verticais e faz uma **limpeza seletiva** da pasta:
   - **Removidos:** `Apps`, o conteúdo de `Custom` (exceto o que está preservado), a maior parte de `Standard` e os arquivos soltos da raiz.
   - **Preservados:** `Custom\Companies`, `Custom\ReferencedAssemblies` e `Standard\Taskbuilder\WebFramework\LoginManager\App_Data`.
4. Escolha **R** (reiniciar em 30 segundos) ou **M** (reiniciar manualmente).
5. Após o reinício, **entre com o mesmo usuário administrador**: uma tarefa agendada retoma o processo, reinstala as dependências, o Mago4 e os verticais.

Se a retomada não iniciar sozinha, execute o comando da seção 1 de novo. O script encontra a sessão pendente e continua de onde parou. Se o instalador não estiver mais acessível (ex.: pasta de rede), o script pede o novo caminho.

> **Não inicie outra operação** enquanto houver reparo avançado pendente. As sessões ficam em `%ProgramData%\Mago4-Setup\Sessions`.

---

## 7. Problemas comuns

| Mensagem | Causa e solução |
|---|---|
| *O Mago4 já está instalado. Use Atualizar ou Reparar.* | Instalar Mago4 só funciona em máquina sem Mago4. |
| *A pasta de destino contém arquivos.* | Escolha uma pasta vazia ou use Atualizar/Reparar. |
| *É necessário um único MSHSetup.exe da mesma versão na pasta do MSI principal.* | Com `.msi`, coloque exatamente um `MSHSetup*.exe` da mesma versão ao lado do MSI. |
| *A instalação não registrou UICulture e Dictionaries em pt-BR.* | Com `.exe`, faltou selecionar Português (Brasil) e o dicionário pt-BR na tela. |
| *O caminho registrado após a instalação não corresponde ao destino solicitado.* | O caminho foi alterado na tela do instalador. Instale de novo, mantendo o destino informado ao script. |
| *... não corresponde à versão principal ...* | O vertical é de outra versão. Use MSIs da mesma versão do Mago4. |
| *O MSI retornou X, mas o Windows Installer registra ... como instalado.* | O vertical foi instalado com aviso. Confira o log indicado e teste o vertical. |
| *Mais de uma instalação do Mago4 foi encontrada.* | Há mais de uma entrada Mago4-BR no Windows. Resolva manualmente antes de continuar. |

### Códigos de retorno do instalador

- **0**: sucesso.
- **3010**: sucesso, mas é necessário **reiniciar** a máquina.
- **1638**: a mesma versão (ou mais nova) já está instalada.
- Outros: falha; consulte o log indicado na tela.
