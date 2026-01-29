# Análise de Erros: Docker e Ubuntu WSL 24.04 - MSAL.NET

**Data:** 28 de janeiro de 2026  
**Projeto:** Microsoft Authentication Library (MSAL) for .NET  
**Escopo:** Análise de riscos de integração, erros conhecidos e problemas de diretórios

---

## 📋 Sumário Executivo

O projeto MSAL.NET possui **suporte experimental para Linux/WSL**, mas apresenta **várias limitações críticas** em ambientes containerizados (Docker) e WSL 24.04. A execução em Docker requer configurações complexas para GUI, gerenciamento de chaves e broker de identidade.

### Status Atual
- ✅ **Suporte Linux**: Broker via Microsoft Edge
- ✅ **Testes CI/CD**: Ubuntu 22.04 em pipeline
- ⚠️ **WSL/Docker**: Requer configurações extensivas
- ❌ **WSL 2 GUI**: Problemas conhecidos #3251
- ❌ **WebView2**: Não disponível em Linux

---

## 🔴 Erros Críticos Identificados

### 1. **Falta de WebView2 em Linux**
**Impacto:** ALTO  
**Localização:** `src/client/Microsoft.Identity.Client.Desktop.WinUI3/WebView2WebUi/`

```
ERRO: WebView2 é componente Windows-only
- WinUI3WindowWithWebView2 não funciona em Linux/Docker
- MSAL usa WebView2 para embedded auth UI em Windows
- Em Linux, a alternativa é o browser system (Microsoft Edge)
```

**Risco de Integração:**
- Código que depende de `EmbeddedWebViewOptions` falhará
- Aplicações desktop que usam WinUI3 não rodarão em Docker
- Alternativa requer fallback para browser externo

### 2. **Configuração Complexa de DBUS e Keyring**
**Impacto:** CRÍTICO  
**Arquivo:** `build/template-test-on-linux.yaml` (linhas 21-70)

```bash
# Problemas identificados:
1. DBUS_SESSION_BUS_ADDRESS precisa ser configurado manualmente
2. gnome-keyring-daemon deve ser inicializado
3. /var/lib/dbus/machine-id deve existir
4. systemd deve estar rodando para D-Bus funcionar
```

**Em Docker:**
```dockerfile
# ❌ PROBLEMA: Docker não fornece systemd por padrão
# Requer: --privileged ou systemd container
# Alternativa: usar D-Bus em socket TCP (inseguro)
```

### 3. **Compatibilidade Ubuntu 24.04**
**Impacto:** ALTO  
**Issue Relacionada:** Nenhuma específica registrada

```bash
# Problemas esperados em Ubuntu 24.04:
1. Versão quebrada de alguns pacotes de GUI (libwebkit2gtk-4.0)
2. D-Bus systemd pode não funcionar em containers
3. Xvfb pode ter conflitos com Wayland (novo padrão)
4. Microsoft Identity Broker pode não estar disponível para 24.04
```

### 4. **Falta de LibSecret em Contêineres**
**Impacto:** MÉDIO  
**Arquivo:** `tests/Microsoft.Identity.Test.Unit/CacheExtension/IntegrationTests.cs`

```csharp
// Código detectado:
if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
{
    // Fallback para arquivo desprotegido
    storageBuilder.WithLinuxUnprotectedFile();
}
```

**Risco:**
- Cache de tokens armazenado em **arquivo plano (não criptografado)**
- Em production Docker, tokens são expostos a qualquer processo no container
- libsecret-1-dev pode não instalar com sucesso em containers

### 5. **Broker Linux requer Microsoft Edge**
**Impacto:** ALTO  
**Changelog:** "MSAL now supports using Linux broker via Microsoft Edge"

```bash
# Problema em Docker:
- Microsoft Edge pode não estar instalado
- Requer display server (X11/Wayland)
- Em headless containers, falha silenciosamente
```

---

## 🗂️ Problemas de Diretórios e Integração

### 1. **Estrutura de Diretórios WSL**

```
microsoft-authentication-library-for-dotnet/
├── .devcontainer/
│   ├── Dockerfile          # ❌ Muito mínimo, falta config
│   └── devcontainer.json   # ⚠️ Requer 4 CPUs, git lfs
├── build/
│   ├── linux-install-deps.sh        # ⚠️ Erro duplo 'sudo' na linha 50
│   ├── template-test-on-linux.yaml  # ⚠️ Configuração complexa de DBUS
│   └── template-build-on-mac.yaml   # ✅ Bem documentado
├── src/
│   └── client/
│       ├── Microsoft.Identity.Client.Desktop.WinUI3/
│       │   └── WebView2WebUi/        # ❌ Windows-only
│       └── ... (sem código Linux)
└── tests/
    └── ... (testes com [DoNotRunOnLinux] decorator)
```

### 2. **Erro: Duplo 'sudo' na Linha 50**

**Arquivo:** `build/linux-install-deps.sh`

```bash
# ❌ ERRO CRÍTICO - Linha 50:
curl https://packages.microsoft.com/config/ubuntu/$LINUX_VERSION/prod.list | sudo sudo tee /etc/apt/trusted.gpg.d/microsoft.asc

# ✅ CORRETO:
curl https://packages.microsoft.com/config/ubuntu/$LINUX_VERSION/prod.list | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc
```

**Impacto:** Falha silenciosa na adição do repositório Microsoft, impedindo instalação do broker.

### 3. **Falta de Suporte Explícito a Ubuntu 24.04**

```bash
# Em linux-install-deps.sh:
LINUX_VERSION=$(sed -r -n -e 's/^VERSION_ID="?([^"]+)"?/\1/p' /etc/os-release)
# Extrai: "24.04" de VERSION_ID="24.04"

# Problema: URL pode ser inválida
# Esperado: https://packages.microsoft.com/config/ubuntu/24.04/prod.list
# Possível falha: Repositório Microsoft pode não ter pacotes para 24.04
```

### 4. **Caminho de Arquivos WSL/Docker**

```
Testes em Linux procuram por:
- tests/devapps/wam/**/bin/**  ← Diretório WAM (Windows Account Manager)
- runtimes/linux-x64/native/libmsalruntime.so
- runtimes/win-x64/native/msalruntime.dll (❌ Windows-only)

Em Docker/WSL:
- Windows binários não existem
- paths absolutos podem quebrar entre mount points
```

---

## ⚙️ Riscos Críticos de Integração

### Risco #1: **Falta de Suporte Completo para GUI em Docker**

| Componente | Windows | macOS | Linux/Docker |
|-----------|---------|-------|-------------|
| WebView2 | ✅ Nativo | ❌ N/A | ❌ N/A |
| Embedded UI | ✅ Sim | ✅ Sim | ❌ Não |
| System Browser | ✅ Sim | ✅ Sim | ⚠️ Edge |
| Token Cache (seguro) | ✅ DPAPI | ✅ Keychain | ❌ libsecret |
| Broker Integration | ✅ WAM | ✅ Broker | ⚠️ Edge |

**Conclusão:** Aplicações que usam embedded UI falharão em Docker/Linux

### Risco #2: **Segurança do Token Cache**

```csharp
// Em Linux sem libsecret:
// Tokens armazenados em arquivo PLANO:
~/.cache/msal/msal.cache

// Chmod resultante:
-rw-r--r-- 1 user user  (tokens em texto legível!)

// Em Docker, qualquer processo pode ler:
docker exec container cat ~/.cache/msal/msal.cache
```

**Recomendação:** Usar managed identity em Azure em vez de armazenar tokens

### Risco #3: **Variabilidade de Ambientes WSL**

```
WSL 1 vs WSL 2 vs Docker vs Ubuntu 22.04 vs 24.04:
- Comportamento D-Bus diferente
- Disponibilidade de libsecret varia
- Permissões de arquivo sistema podem diferir
- systemd status varia
```

### Risco #4: **Pipeline CI/CD vs Runtime Local**

```
Pipeline CI (Ubuntu 22.04):
- Roda tudo com sucesso
- Configuração de DBUS manual
- Xvfb virtual display
- Systemd disponível

Docker Desktop / WSL 24.04:
- Pode não ter systemd por padrão
- DBUS pode falhar
- Display server pode não estar presente
- Erros podem ser silenciosos
```

---

## 🐛 Erros Específicos por Versão

### Ubuntu 24.04 no WSL/Docker

```bash
❌ Possível Erro 1: libwebkit2gtk-4.0 não instala
apt-get install libwebkit2gtk-4.0-dev
# Pode falhar em 24.04 com:
# E: Unable to locate package libwebkit2gtk-4.0-dev

❌ Possível Erro 2: microsoft-identity-broker não encontrado
apt-get install microsoft-identity-broker
# Repositório Microsoft pode não ter builds para 24.04

❌ Possível Erro 3: DBUS socket não criado
unix:path=/run/user/1000/bus not found

❌ Possível Erro 4: Xvfb conflita com Wayland
Xvfb :1 -screen 0 1024x768x24
# Wayland é padrão em 24.04, Xvfb é X11 legado
```

---

## 📊 Matriz de Compatibilidade Prevista

| Cenário | Windows | macOS | Linux | WSL 1 | WSL 2 | Docker |
|---------|---------|-------|-------|-------|-------|--------|
| **Embedded WebView** | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **System Browser** | ✅ | ✅ | ⚠️ (Edge) | ⚠️ | ⚠️ | ❌ |
| **Broker (WAM/Edge)** | ✅ | ✅ | ⚠️ (Edge) | ⚠️ | ⚠️ | ❌ |
| **Secure Cache** | ✅ | ✅ | ⚠️ (libsecret) | ⚠️ | ⚠️ | ❌ |
| **Token Encryption** | ✅ DPAPI | ✅ Keychain | ❌ Plaintext | ❌ | ❌ | ❌ |
| **Managed Identity** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 🔧 Soluções e Mitigações

### Solução #1: Desabilitar UI Embedida em Docker

```csharp
#if !LINUX
    // Use WebView2
    pca.WithEmbeddedWebView(true);
#else
    // Fallback para browser system
    pca.WithBroker(true); // Se Edge disponível
    // ou deixar abrir browser externo
#endif
```

### Solução #2: Usar Managed Identity em Azure

```csharp
// Substitua autenticação interativa por:
var credential = new DefaultAzureCredential();
var token = credential.GetToken(scopes);

// Isso funciona em:
// ✅ Azure VM
// ✅ Azure Container Instance
// ✅ Azure App Service
// ✅ Local (Dev Box com Azure CLI)
```

### Solução #3: Dockerfile Otimizado para MSAL.NET

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0

# Instalar dependências Linux necessárias
RUN apt-get update && apt-get install -y \
    libx11-dev \
    dbus \
    gnome-keyring \
    libsecret-1-dev \
    libsecret-tools \
    # Remover GUI se não necessário:
    # xorg \
    # libwebkit2gtk-4.0-dev \
    && rm -rf /var/lib/apt/lists/*

# Usar token cache desprotegido apenas em dev
ENV MSAL_CACHE_ENCRYPTION=false

WORKDIR /app
COPY . .
RUN dotnet build

CMD ["dotnet", "run"]
```

### Solução #4: Corrigir Script linux-install-deps.sh

```bash
# Linha 50 - remover duplo 'sudo'
curl https://packages.microsoft.com/config/ubuntu/$LINUX_VERSION/prod.list | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc

# Adicionar suporte a Ubuntu 24.04
# Verificar se repositório existe antes de instalar
apt-get update || true

# Fallback se microsoft-identity-broker não estiver disponível
$PKGINSTALL_CMD $BROKER_PACKAGE_NAME || echo "Warning: Broker not available"
```

---

## 📋 Checklist de Validação para Docker/WSL 24.04

```bash
# ✅ Antes de rodar em Docker:

# 1. Verificar dependências críticas
[ -f /usr/bin/dbus-daemon ] && echo "✅ DBUS OK" || echo "❌ DBUS falta"
[ -f /usr/lib/libsecret* ] && echo "✅ libsecret OK" || echo "❌ libsecret falta"
[ -f /opt/microsoft/identity-broker* ] && echo "✅ Broker OK" || echo "⚠️ Broker não instalado"

# 2. Verificar versão Ubuntu
cat /etc/os-release | grep VERSION_ID

# 3. Testar DBUS
dbus-daemon --version

# 4. Testar acesso ao token cache
ls -la ~/.cache/msal/ 2>/dev/null || echo "❌ Sem cache"

# 5. Se usando GUI, testar X11/Wayland
echo $DISPLAY  # Para X11
echo $WAYLAND_DISPLAY  # Para Wayland

# 6. Teste final - rodar teste simples
dotnet test tests/Microsoft.Identity.Test.Unit --filter "Category=Core"
```

---

## 📌 Problemas Registrados no Projeto

| Issue | Título | Status | Impacto |
|-------|--------|--------|---------|
| #3251 | WSL2 - Browser não mostra | Resolvido | Alto |
| #3051 | Linux broker via Microsoft Edge | Implementado | Médio |
| #4445 | x-ms-pkeyauth enviado incorretamente em Linux | Resolvido | Médio |
| #4493 | Cache exceptions em Linux | Resolvido | Médio |
| #4784 | TotalDurationInMs incorreto em Linux | Resolvido | Baixo |
| #5075 | UseShellExecute em OpenLinuxBrowser | Resolvido | Médio |
| #5086 | Broker support em Linux | Implementado | Alto |

---

## 🎯 Recomendações Finais

### Para Desenvolvimento em Docker/WSL 24.04

1. **Use Managed Identity** se rodando em Azure
2. **Evite Embedded UI** - use browser system
3. **Não armazene tokens** em Docker (use in-memory ou cache Redis)
4. **Teste localmente primeiro** em máquina Windows/macOS
5. **Use imagem Ubuntu 22.04** em Docker se possível (mais estável)
6. **Implemente retry logic** para broker falhas
7. **Monitore logs de DBUS** para debugging

### Para Produção

- ✅ Usar Azure App Service / Container Instances
- ✅ Implementar Azure AD Managed Identity
- ✅ Remover token cache persistente
- ✅ Usar Application Permissions (não delegadas)
- ⚠️ Evitar WebView2 em servidores

### Stack Recomendado

```yaml
Cenário: Auth em Docker Linux

Componente: MSAL.NET
Autenticação: DefaultAzureCredential
Cache: Redis/Cosmos DB (externo)
Broker: Microsoft Entra (Azure AD)
Display: None (headless)
```

---

## 📚 Referências

- [MSAL.NET Documentation](https://learn.microsoft.com/entra/msal/dotnet/)
- [WSL2 Browser Issue #3251](https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/issues/3251)
- [Linux Broker PR #5086](https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/pull/5086)
- [Azure Identity - Managed Identity](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)

---

**Fim da Análise**  
Para questões específicas, abra issue em: https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/issues
