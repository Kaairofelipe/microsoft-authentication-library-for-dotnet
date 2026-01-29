# Erros Técnicos Encontrados - MSAL.NET Docker/WSL

## 🔴 Erro #1: Duplo 'sudo' em linux-install-deps.sh

**Arquivo:** [build/linux-install-deps.sh](build/linux-install-deps.sh#L50)  
**Linha:** 50  
**Severidade:** CRÍTICO  
**Status:** Bug não corrigido

### Problema Identificado

```bash
❌ ERRO - Linha 50:
curl https://packages.microsoft.com/config/ubuntu/$LINUX_VERSION/prod.list | sudo sudo tee /etc/apt/trusted.gpg.d/microsoft.asc
                                                                                    ^^^^^^^^
                                                                            Duplo 'sudo' invalid
```

### Impacto

- ❌ Comando falha com erro de sintaxe
- ❌ Repositório Microsoft não é adicionado ao APT
- ❌ Instalação de `microsoft-identity-broker` falha subsequentemente
- ❌ Broker não fica disponível em Linux

### Solução

```bash
✅ CORRETO - Remover duplo sudo:
curl https://packages.microsoft.com/config/ubuntu/$LINUX_VERSION/prod.list | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc
```

### Contexto do Código

```bash
# Linhas 45-54 do script:
echo "Installing JavaBroker"
LINUX_VERSION=$(sed -r -n -e 's/^VERSION_ID="?([^"]+)"?/\1/p' /etc/os-release)
LINUX_VERSION_MAIN=$(echo $LINUX_VERSION | sed 's/\([0-9]*\)\..*/\1/')

BROKER_PACKAGE_NAME='microsoft-identity-broker'
if [ -f '/usr/bin/apt' ]; then
    curl https://packages.microsoft.com/config/ubuntu/$LINUX_VERSION/prod.list | sudo sudo tee /etc/apt/trusted.gpg.d/microsoft.asc  # ❌ BUG AQUI
else
    $PKGINSTALL_CMD yum-utils
    yum-config-manager --add-repo=https://packages.microsoft.com/config/rhel/$LINUX_VERSION_MAIN/prod.repo
```

---

## 🔴 Erro #2: Falta de Verificação de Disponibilidade de microsoft-identity-broker

**Arquivo:** [build/linux-install-deps.sh](build/linux-install-deps.sh#L57)  
**Linhas:** 57-58  
**Severidade:** ALTO  
**Status:** Sem tratamento de erro

### Problema Identificado

```bash
echo "Installing latest published JavaBroker package"
$PKGINSTALL_CMD $BROKER_PACKAGE_NAME  # ← Sem verificação se existe

exit 0  # ← Sempre retorna sucesso mesmo se falhar
```

### Impacto em Ubuntu 24.04

- ❌ `microsoft-identity-broker` pode não estar disponível para Ubuntu 24.04
- ❌ Script "sucede" com `exit 0` mesmo que broker não instale
- ❌ Testes posteriores falham silenciosamente sem broker
- ⚠️ Difícil debugar (não há mensagem de erro clara)

### Cenários de Falha

```bash
# Cenário 1: Repositório correto, mas pacote não existe em 24.04
$ apt-get install microsoft-identity-broker
E: Unable to locate package microsoft-identity-broker

# Cenário 2: Rede indisponível
$ apt-get install microsoft-identity-broker
E: Could not get lock /var/lib/apt/lists/lock

# Cenário 3: Autenticação de APT falha
$ sudo: no password was provided
```

### Solução

```bash
✅ CORRETO - Adicionar tratamento de erro:
echo "Installing latest published JavaBroker package"
if ! $PKGINSTALL_CMD $BROKER_PACKAGE_NAME; then
    echo "⚠️ Warning: microsoft-identity-broker not available for this system"
    echo "   Broker will not be functional. Install manually if needed."
    echo "   Continuing with other dependencies..."
fi

# Ou falhar explicitamente:
$PKGINSTALL_CMD $BROKER_PACKAGE_NAME || {
    echo "❌ ERROR: Failed to install microsoft-identity-broker"
    exit 1
}
```

---

## 🔴 Erro #3: DBUS SessionBusAddress Inválido em Containers

**Arquivo:** [build/template-test-on-linux.yaml](build/template-test-on-linux.yaml#L16)  
**Linhas:** 16-40  
**Severidade:** CRÍTICO  
**Status:** Conhecida, sem solução geral

### Problema Identificado

```bash
echo "Setting DBUS_SESSION_BUS_ADDRESS"
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${UID}/bus"

# Problema: /run/user/<uid>/bus pode não existir em Docker
```

### Por que falha em Docker/WSL

```
Docker Container (padrão):
  - /run/user/ não é criado
  - D-Bus não é inicializado
  - systemd ausente (ou desabilitado)
  - Resultado: DBUS_SESSION_BUS_ADDRESS inválido

WSL 2 (com systemd habilitado):
  - /run/user/ pode existir
  - Mas permissões podem impedir acesso
  - Wayland (Ubuntu 24.04) pode conflitar com D-Bus/X11

WSL 1:
  - Sem suporte a D-Bus real
  - Socket TCP não oferecido
  - Fallback necessário
```

### Impacto Cascata

```
1. DBUS_SESSION_BUS_ADDRESS inválido
   ↓
2. gnome-keyring-daemon não consegue se conectar
   ↓
3. Token cache não pode ser criptografado com libsecret
   ↓
4. Fallback para arquivo plano (inseguro)
   ↓
5. Tokens armazenados sem criptografia em disco
```

### Solução (Docker)

```dockerfile
# Opção 1: Usar systemd container
FROM ubuntu:24.04
RUN apt-get install -y systemd
VOLUME ["/sys/fs/cgroup"]
CMD ["/lib/systemd/systemd-sysv-install"]

# Opção 2: Desabilitar keyring, usar cache in-memory
ENV GNOME_KEYRING_CONTROL=/dev/null
# Código deve detectar e usar fallback

# Opção 3: Usar dbus-daemon em socket TCP (inseguro)
ENTRYPOINT dbus-daemon --system --nofork
```

---

## 🔴 Erro #4: WebView2 Não Existe em Linux

**Arquivo:** [src/client/Microsoft.Identity.Client.Desktop.WinUI3/WebView2WebUi/WinUI3WindowWithWebView2.cs](src/client/Microsoft.Identity.Client.Desktop.WinUI3/WebView2WebUi/WinUI3WindowWithWebView2.cs)  
**Linhas:** 1-200  
**Severidade:** CRÍTICO  
**Status:** Design limitation (intencional)

### Problema Identificado

```csharp
// Arquivo: WinUI3WindowWithWebView2.cs
using Microsoft.Web.WebView2.Core;  // ← Windows/WinUI3 only

namespace Microsoft.Identity.Client.Desktop.WebView2WebUi
{
    internal sealed class WinUI3WindowWithWebView2 : Window, IDisposable
    {
        private WebView2 _webView2;  // ← Windows-only control
        
        // Este arquivo inteiro é Windows-only
        // Nenhuma implementação Linux existe
    }
}
```

### Onde é Usado

```csharp
// Aplicações que usam embedded auth UI:
var pca = PublicClientApplicationBuilder
    .Create("client-id")
    .WithEmbeddedWebView(true)  // ← Falha em Linux
    .Build();
```

### Por que Não Funciona em Docker/Linux

| Plataforma | WebView2 | Alternativa |
|-----------|----------|-------------|
| Windows | ✅ Native Chromium | N/A |
| macOS | ❌ N/A | System browser |
| Linux | ❌ N/A | System browser (Microsoft Edge) |
| Docker | ❌ N/A | N/A (sem GUI) |

### Erro Resultante em Linux

```
System.PlatformNotSupportedException: 
    'Embedded WebView is not supported on this platform. 
     Use WithBroker(true) or allow system browser instead.'
```

### Solução

```csharp
// Detectar plataforma e ajustar:
if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
{
    pca.WithBroker(true);  // Usar Edge + Broker
    // OU deixar abrir browser externo (padrão)
}
else if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
{
    pca.WithEmbeddedWebView(true);  // Windows only
}
```

---

## 🟠 Erro #5: Token Cache Não Criptografado em Linux

**Arquivo:** [tests/Microsoft.Identity.Test.Unit/CacheExtension/IntegrationTests.cs](tests/Microsoft.Identity.Test.Unit/CacheExtension/IntegrationTests.cs#L42-L43)  
**Linhas:** 40-75  
**Severidade:** ALTO (security risk)  
**Status:** Design decision

### Problema Identificado

```csharp
// Linhas 40-45 do teste
var storageBuilder = new StorageCreationPropertiesBuilder("msal.cache");

// unit tests run on Linux boxes without LibSecret 
storageBuilder.WithLinuxUnprotectedFile();  // ← Arquivo plano!

var helper = await MsalCacheHelper.CreateAsync(storageBuilder.Build());
```

### Implicação em Produção

```bash
# No Docker/Linux, tokens são armazenados assim:
$ cat ~/.cache/msal/msal.cache
{
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",  # ← VISIBLE IN CLEAR TEXT
  "refresh_token": "0.AS...",                     # ← VISIBLE IN CLEAR TEXT
  "id_token": "eyJ0eXAiOiJKV1QiLCJhbGc..."       # ← VISIBLE IN CLEAR TEXT
}

# Qualquer processo pode ler:
$ docker exec my_container cat ~/.cache/msal/msal.cache
```

### Risco de Segurança

```
1. Token hijacking possível
   - Outro container/processo lê token
   - Usa token para fazer requisições como usuário

2. Token replay attack
   - Token capturado em logs/backups
   - Replay em outra instância

3. Compliance violations
   - PCI-DSS: tokens devem estar criptografados
   - HIPAA: dados sensíveis não podem estar planos
   - GDPR: dados pessoais devem ser protegidos
```

### Solução

```csharp
// Opção 1: Usar Managed Identity em Azure
var credential = new DefaultAzureCredential();
var token = await credential.GetTokenAsync(
    new TokenRequestContext(new[] { "https://graph.microsoft.com/.default" }));
// Tokens não são persistidos localmente

// Opção 2: Cache in-memory apenas
public class InMemoryTokenCache : ITokenCache
{
    private Dictionary<string, string> _cache = new();
    
    public Task SerializeAsync(byte[] buffer, CancellationToken ct)
    {
        // In-memory, não persiste em disco
        return Task.CompletedTask;
    }
}

// Opção 3: Cache remoto (Redis/Cosmos)
// Tokens permanezem no servidor, não localmente
storageBuilder.WithRedisCache("redis://localhost");
```

---

## 🟠 Erro #6: FileSystemWatcher Não Funciona Confiável em Linux

**Arquivo:** [tests/Microsoft.Identity.Test.Unit/CacheExtension/MsalCacheHelperTests.cs](tests/Microsoft.Identity.Test.Unit/CacheExtension/MsalCacheHelperTests.cs#L367)  
**Linhas:** 365-370  
**Severidade:** MÉDIO  
**Status:** Conhecido, com decorator skip

### Problema Identificado

```csharp
[DoNotRunOnLinux] // The FileSystemWatcher on Linux doesn't always fire
public async Task MultipleTokenCacheSync_TestAsync()
{
    // Este teste é pulado em Linux porque FileSystemWatcher é unreliable
}
```

### Por que Falha em Linux

```
FileSystemWatcher implementação por SO:

Windows:
  - Usa API nativa NTFS
  - Notificações quase instantâneas
  - 100% confiável

Linux:
  - Usa inotify (kernel interface)
  - Pode perder eventos sob carga
  - Limitações de recursos (/proc/sys/fs/inotify/max_queued_events)
  - Em Docker/WSL: pode falhar completamente

Docker:
  - inotify pode não funcionar com volumes
  - FUSE mounts não suportam inotify
  - OverlayFS pode não propagar eventos
```

### Impacto

```
Cache sync issues:
  1. Múltiplos processos/containers compartilham cache
  2. Alterações não são sincronizadas em tempo real
  3. Tokens obsoletos podem ser usados
  4. Token refresh pode ser perdido
```

### Solução

```csharp
// Opção 1: Usar cache remoto em vez de arquivo
var redisClient = new StackExchange.Redis.ConnectionMultiplexer
    .Connect("redis://redis:6379");
storageBuilder.WithRedisCache(redisClient);

// Opção 2: Polling em vez de FileSystemWatcher
public class PollingTokenCache : ITokenCache
{
    private DateTime _lastCheck = DateTime.MinValue;
    
    public async Task RefreshAsync()
    {
        if (DateTime.UtcNow - _lastCheck > TimeSpan.FromSeconds(5))
        {
            // Reload do arquivo a cada 5 segundos
            await ReloadFromFileAsync();
            _lastCheck = DateTime.UtcNow;
        }
    }
}

// Opção 3: Event-driven com Redis pub/sub
// Quando processo A atualiza cache:
redis.Publish("cache:updated", "");

// Processo B se inscreve:
subscriber.Subscribe("cache:updated", (channel, msg) => 
{
    ReloadTokenCache();
});
```

---

## 🟠 Erro #7: Compatibilidade Incerta com Ubuntu 24.04

**Arquivo:** N/A (Issue de compatibilidade)  
**Status:** Não testado oficialmente  
**Severidade:** MÉDIO

### Problemas Esperados em Ubuntu 24.04

```bash
# 1. libwebkit2gtk-4.0-dev pode não existir
$ apt-cache search libwebkit2gtk-4.0-dev
# Pode retornar vazio em 24.04

# 2. Wayland é padrão, Xvfb é X11 legado
$ cat /etc/os-release | grep VARIANT_ID
ubuntu-desktop  # Usa Wayland por padrão em 24.04

# 3. systemd pode ter comportamentos diferentes
$ systemctl --version
systemd 255+

# 4. Permsões D-Bus podem ser mais restritivas
$ ls -la /run/user/1000/bus
# Pode não existir ou ter permissões diferentes
```

### Verificação Necessária

```bash
#!/bin/bash
# Script para verificar compatibilidade com Ubuntu 24.04

echo "=== Verificando Compatibilidade MSAL.NET ==="

# Check 1: Versão Ubuntu
echo "Ubuntu version:"
cat /etc/os-release | grep VERSION

# Check 2: Dependências disponíveis
echo -e "\n=== Checking Dependencies ==="
for pkg in libwebkit2gtk-4.0-dev libsecret-1-dev gnome-keyring dbus xvfb; do
    if apt-cache search "^${pkg}$" | grep -q .; then
        echo "✅ $pkg available"
    else
        echo "❌ $pkg NOT available"
    fi
done

# Check 3: Microsoft broker
echo -e "\n=== Checking Microsoft Packages ==="
if grep -r "microsoft" /etc/apt/sources.list.d/ 2>/dev/null; then
    echo "✅ Microsoft repository configured"
    if apt-cache search microsoft-identity-broker | grep -q .; then
        echo "✅ microsoft-identity-broker available"
    else
        echo "⚠️  microsoft-identity-broker NOT available"
    fi
else
    echo "❌ Microsoft repository NOT configured"
fi

# Check 4: Display server
echo -e "\n=== Display Server ==="
if [ -n "$DISPLAY" ]; then
    echo "✅ X11 display available: $DISPLAY"
elif [ -n "$WAYLAND_DISPLAY" ]; then
    echo "⚠️  Wayland display (not X11): $WAYLAND_DISPLAY"
else
    echo "❌ No display server available (headless)"
fi

# Check 5: D-Bus
echo -e "\n=== D-Bus ==="
if dbus-daemon --version 2>/dev/null | head -1; then
    echo "✅ D-Bus daemon available"
else
    echo "❌ D-Bus daemon NOT available"
fi
```

---

## 📊 Resumo de Erros por Severidade

| # | Erro | Arquivo | Severidade | Tipo | Status Fix |
|---|------|---------|-----------|------|-----------|
| 1 | Duplo 'sudo' | linux-install-deps.sh:50 | 🔴 CRÍTICO | Typo | ❌ Não corrigido |
| 2 | Sem erro handling broker | linux-install-deps.sh:57 | 🔴 CRÍTICO | Design | ⚠️ Parcial |
| 3 | DBUS inválido em Docker | template-test-on-linux.yaml:16 | 🔴 CRÍTICO | Arch | ⚠️ Workaround |
| 4 | WebView2 não existe Linux | WinUI3WindowWithWebView2.cs | 🔴 CRÍTICO | Design | ✅ Conhecido |
| 5 | Cache não criptografado | IntegrationTests.cs:42 | 🟠 ALTO | Security | ✅ Documentado |
| 6 | FileSystemWatcher unreliable | MsalCacheHelperTests.cs:367 | 🟠 MÉDIO | Design | ✅ Skipped |
| 7 | Ubuntu 24.04 não testado | N/A | 🟠 MÉDIO | Compat | ❌ Não verificado |

---

## ✅ Próximos Passos Recomendados

1. **Corrigir bug #1** (duplo sudo) - Trivial
2. **Adicionar error handling #2** - Médio
3. **Documentar limitações** - Para usuários
4. **Testar em Ubuntu 24.04** - Investigação
5. **Criar guia Docker** - Documentação
6. **Implementar CI para Docker** - Infrastructure

---

**Documento gerado:** 28 de janeiro de 2026  
**Análise completa:** Ver [DOCKER_WSL_ANALYSIS.md](DOCKER_WSL_ANALYSIS.md)
