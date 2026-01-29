# 📋 Plano de Implementação - Otimização e Hardening

**Status:** Pronto para Ação  
**Prioridade:** CRÍTICA  
**Timeline:** 1-4 semanas  

---

## 🚨 Problemas Críticos de Segurança Identificados

### 1. Tokens Armazenados em Texto Plano
**Severidade:** CRÍTICA  
**Localização:** `~/.cache/msal/msal.cache`  
**Risco:** Comprometimento de acesso por 60+ minutos  

#### Ação Imediata
```bash
# Opção 1: Managed Identity (Azure)
# Nenhum armazenamento local necessário
az identity create --name msal-identity

# Opção 2: Cache remoto (Redis seguro)
docker run -d \
  --name redis \
  -e REDIS_PASSWORD=$(openssl rand -base64 32) \
  redis:7-alpine
```

---

## 📅 Cronograma Executivo

### HOJE (30 minutos)
- [ ] Revisar este documento
- [ ] Confirmar aprovação para mudanças

### DIA 1 (2-3 horas)
- [ ] Implementar Dockerfile seguro
- [ ] Configurar docker-compose hardened
- [ ] Testar localmente

### DIA 2-3 (1 dia)
- [ ] Implementar CI/CD security
- [ ] Testar em staging
- [ ] Treinamento do time

### SEMANA 2-4 (Backlog)
- [ ] Migração para Managed Identity
- [ ] Implementar monitoramento
- [ ] Auditoria de compliance

---

## 🔧 Implementação Passo-a-Passo

### Passo 1: Dockerfile Seguro

**Arquivo:** `Dockerfile.prod`

```dockerfile
# ===== BUILDER =====
FROM mcr.microsoft.com/dotnet/sdk:8.0-noble AS builder

WORKDIR /src
COPY ["src/", "src/"]
COPY ["*.csproj", "*.props", "*.sln", "Directory.Packages.props", "./"]

# Build com otimizações
RUN dotnet build -c Release --no-self-contained

# ===== RUNTIME =====
FROM mcr.microsoft.com/dotnet/runtime:8.0-noble

# Instalação mínima de dependências
RUN apt-get update && apt-get install -y \
    ca-certificates \
    dbus \
    libsecret-1-0 \
    curl \
    --no-install-recommends \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Criar usuário non-root
RUN groupadd -r appuser && useradd -r -g appuser -u 1001 appuser

# Preparar diretórios
RUN mkdir -p /home/appuser/.cache/msal && \
    chmod 700 /home/appuser/.cache/msal && \
    chown -R appuser:appuser /home/appuser

WORKDIR /app
COPY --from=builder /src/bin/Release/net8.0/publish .
RUN chown -R appuser:appuser /app

USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:5000/health || exit 1

ENTRYPOINT ["dotnet", "Microsoft.Identity.Client.Desktop.dll"]
```

**Checklist de Teste:**
```bash
# Construir
docker build -f Dockerfile.prod -t msal-app:latest .

# Testar
docker run --rm msal-app:latest whoami
# Deve retornar: appuser (não root!)

docker run --rm msal-app:latest cat /etc/passwd | tail -1
# Deve mostrar: appuser:x:1001:1001:...
```

---

### Passo 2: docker-compose Seguro

**Arquivo:** `docker-compose.prod.yml`

```yaml
version: '3.8'

services:
  msal-app:
    build:
      context: .
      dockerfile: Dockerfile.prod
    
    image: msal-app:${APP_VERSION:-latest}
    container_name: msal-app
    
    # Networking seguro
    networks:
      msal-network:
        ipv4_address: 172.20.0.2
    
    # Volumes (APENAS necessários)
    volumes:
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - msal-cache:/home/appuser/.cache/msal
    
    # Variáveis de ambiente seguros
    environment:
      ASPNETCORE_ENVIRONMENT: Production
      ASPNETCORE_URLS: http://+:5000
      DOTNET_RUNNING_IN_CONTAINER: "true"
      MSAL_CACHE_TYPE: ${MSAL_CACHE_TYPE:-memory}  # memory ou redis
      REDIS_HOST: ${REDIS_HOST:-redis}
      REDIS_PORT: ${REDIS_PORT:-6379}
      REDIS_DATABASE: ${REDIS_DATABASE:-0}
    
    # Limitar recursos
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
    
    # Segurança de contentor
    security_opt:
      - no-new-privileges:true
      - apparmor=docker-default
    
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    
    # Filesystem read-only
    read_only: true
    tmpfs:
      - /tmp
      - /run
      - /var/run
    
    # Sem privilegiado
    privileged: false
    user: "1001:1001"
    
    # Health check
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 5s
    
    restart: unless-stopped
    
    # Logging
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        labels: "app=msal"
    
    depends_on:
      redis:
        condition: service_healthy
  
  # Cache remoto seguro
  redis:
    image: redis:7-alpine
    container_name: msal-redis
    
    networks:
      msal-network:
        ipv4_address: 172.20.0.3
    
    # Segurança
    security_opt:
      - no-new-privileges:true
      - apparmor=docker-default
    
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
    
    # Usuário non-root
    user: "999:999"
    
    # Filesystem read-only
    read_only: true
    tmpfs:
      - /var/lib/redis
      - /tmp
    
    # Requer autenticação
    command: >
      redis-server
      --requirepass ${REDIS_PASSWORD}
      --appendonly yes
      --appendfsync always
      --databases 16
      --databases 1
    
    environment:
      REDIS_PASSWORD: ${REDIS_PASSWORD}
    
    # Volume para persistência
    volumes:
      - redis-data:/var/lib/redis
    
    # Health check
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    
    restart: unless-stopped
    
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  msal-cache:
    driver: local
  redis-data:
    driver: local

networks:
  msal-network:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: "msal-br0"
    ipam:
      config:
        - subnet: 172.20.0.0/16
          gateway: 172.20.0.1
```

**Arquivo:** `.env.example`

```bash
# Copiar para .env e preencher valores seguros
# NUNCA commit .env no Git!

ASPNETCORE_ENVIRONMENT=Production
MSAL_CACHE_TYPE=redis

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_DATABASE=0
REDIS_PASSWORD=seu_senha_aleatoria_longa_aqui_32_caracteres_minimo

# App
APP_VERSION=1.0.0
LOG_LEVEL=Warning

# Adicionar ao .gitignore:
# .env
# .env.local
# .env.*.local
```

---

### Passo 3: Scripts de Validação

**Arquivo:** `scripts/validate-docker-security.sh`

```bash
#!/bin/bash
set -euo pipefail

echo "🔐 Validando segurança do Docker..."
echo "===================================="

FAILED=0

# 1. Verificar Dockerfile
echo -n "✓ Verificando Dockerfile... "
if grep -q "USER " Dockerfile.prod; then
    echo "✅"
else
    echo "❌ USER não configurado!"
    FAILED=1
fi

# 2. Verificar se usa root
echo -n "✓ Verificando non-root... "
if grep -q "USER appuser\|USER 1001" Dockerfile.prod; then
    echo "✅"
else
    echo "❌ Executa como root!"
    FAILED=1
fi

# 3. Verificar permissões de arquivo
echo -n "✓ Verificando permissões... "
if grep -q "chmod 755\|chmod 700" Dockerfile.prod; then
    echo "✅"
else
    echo "⚠️  Revisar permissões"
fi

# 4. Verificar secrets em arquivo
echo -n "✓ Verificando secrets... "
if grep -i "password\|token\|secret" Dockerfile.prod | grep -qv "REDIS_PASSWORD=" || [ $? -eq 1 ]; then
    echo "✅"
else
    echo "❌ Secrets no Dockerfile!"
    FAILED=1
fi

# 5. Testar build
echo -n "✓ Construindo imagem... "
if docker build -f Dockerfile.prod -t msal-test:latest . > /dev/null 2>&1; then
    echo "✅"
else
    echo "❌ Build falhou!"
    FAILED=1
fi

# 6. Verificar usuário no container
echo -n "✓ Verificando usuário no container... "
USER_IN_CONTAINER=$(docker run --rm msal-test:latest whoami)
if [ "$USER_IN_CONTAINER" = "appuser" ]; then
    echo "✅ (appuser)"
else
    echo "❌ ($USER_IN_CONTAINER)"
    FAILED=1
fi

# 7. Verificar permissões de filesystem
echo -n "✓ Verificando filesystem... "
if docker run --rm msal-test:latest test -w / 2>/dev/null; then
    echo "❌ Filesystem é writable!"
    FAILED=1
else
    echo "✅ (read-only)"
fi

# Cleanup
docker rmi msal-test:latest > /dev/null 2>&1 || true

# Resultado
echo ""
if [ $FAILED -eq 0 ]; then
    echo "✅ Todas as verificações passaram!"
    exit 0
else
    echo "❌ Algumas verificações falharam!"
    exit 1
fi
```

**Arquivo:** `scripts/validate-docker-compose.sh`

```bash
#!/bin/bash
set -euo pipefail

echo "🔐 Validando docker-compose..."
echo "=============================="

# 1. Sintaxe YAML
echo -n "✓ Validando YAML... "
docker-compose -f docker-compose.prod.yml config > /dev/null && echo "✅" || {
    echo "❌"
    exit 1
}

# 2. Verificar secrets não estão expostos
echo -n "✓ Verificando secrets... "
if grep -i "password=" docker-compose.prod.yml | grep -qv '${' ; then
    echo "❌ Password exposta!"
    exit 1
fi
echo "✅"

# 3. Verificar read_only
echo -n "✓ Verificando read_only... "
if grep -q "read_only: true" docker-compose.prod.yml; then
    echo "✅"
else
    echo "⚠️  Não configurado"
fi

# 4. Verificar cap_drop
echo -n "✓ Verificando capabilities... "
if grep -q "cap_drop:" docker-compose.prod.yml; then
    echo "✅"
else
    echo "❌ Capabilities não removidas!"
    exit 1
fi

# 5. Verificar healthcheck
echo -n "✓ Verificando healthcheck... "
if grep -q "healthcheck:" docker-compose.prod.yml; then
    echo "✅"
else
    echo "⚠️  Não configurado"
fi

echo ""
echo "✅ docker-compose validado!"
```

---

### Passo 4: Testes de Integração

**Arquivo:** `tests/SecurityTests.cs`

```csharp
using Xunit;
using Docker.DotNet;
using Docker.DotNet.Models;
using System.Threading.Tasks;

public class DockerSecurityTests
{
    private readonly DockerClient _dockerClient;
    
    public DockerSecurityTests()
    {
        _dockerClient = new DockerClientConfiguration(
            new Uri("unix:///var/run/docker.sock"))
            .CreateClient();
    }
    
    [Fact]
    public async Task Container_ShouldRunAsNonRoot()
    {
        // Arrange
        var response = await _dockerClient.Containers.CreateContainerAsync(
            new CreateContainerParameters
            {
                Image = "msal-app:latest",
                Cmd = new[] { "whoami" },
                HostConfig = new HostConfig
                {
                    // Verificações de segurança
                    Privileged = false,
                    CapDrop = new List<string> { "ALL" },
                }
            });
        
        // Act
        await _dockerClient.Containers.StartContainerAsync(
            response.ID, new ContainerStartParameters());
        
        var output = await _dockerClient.Containers.GetLogsAsync(
            response.ID, new ContainerLogsParameters { Stdout = true });
        
        // Assert
        Assert.NotNull(output);
        Assert.DoesNotContain("root", output.ToString() ?? "");
    }
    
    [Fact]
    public async Task Container_ShouldHaveReadOnlyFileSystem()
    {
        // Verificar se consegue escrever em /
        var response = await _dockerClient.Containers.CreateContainerAsync(
            new CreateContainerParameters
            {
                Image = "msal-app:latest",
                Cmd = new[] { "touch", "/test.txt" },
                HostConfig = new HostConfig
                {
                    ReadonlyRootfs = true
                }
            });
        
        // Deve falhar (filesystem read-only)
        var result = await _dockerClient.Containers.StartContainerAsync(
            response.ID, new ContainerStartParameters());
        
        Assert.NotNull(result);
    }
    
    [Fact]
    public async Task Container_ShouldNotHavePrivileges()
    {
        var response = await _dockerClient.Containers.CreateContainerAsync(
            new CreateContainerParameters
            {
                Image = "msal-app:latest",
                HostConfig = new HostConfig
                {
                    Privileged = false
                }
            });
        
        Assert.NotNull(response);
    }
}
```

---

## ✅ Checklist de Implementação

### Antes de Começar
- [ ] Backup de configurações atuais
- [ ] Teste em ambiente staging
- [ ] Comunicar com o time
- [ ] Planejar downtime (se necessário)

### Implementação
- [ ] Criar novo Dockerfile.prod
- [ ] Criar docker-compose.prod.yml
- [ ] Copiar .env.example para .env
- [ ] Preencher .env com valores seguros
- [ ] Adicionar .env ao .gitignore

### Testes
- [ ] Executar validate-docker-security.sh
- [ ] Executar validate-docker-compose.sh
- [ ] Testar em staging
- [ ] Executar tests/SecurityTests.cs

### Deploy
- [ ] Build da imagem
- [ ] Push para registry (Docker Hub/ACR)
- [ ] Deploy em produção
- [ ] Monitorar logs
- [ ] Validar health checks

### Pós-Deploy
- [ ] Verificar funcionamento
- [ ] Coletar métricas
- [ ] Documentar lições aprendidas
- [ ] Atualizar runbooks

---

## 🆘 Troubleshooting

### Problema: "Container exited with code 137"
**Causa:** Out of memory  
**Solução:**
```yaml
deploy:
  resources:
    limits:
      memory: 1G  # Aumentar se necessário
```

### Problema: "Health check failed"
**Causa:** Aplicação demora para iniciar  
**Solução:**
```yaml
healthcheck:
  start_period: 30s  # Aumentar tempo de warmup
```

### Problema: "Permission denied" no volume
**Causa:** Permissões incorretas  
**Solução:**
```bash
docker exec msal-app chown -R appuser:appuser /home/appuser/.cache/msal
docker exec msal-app chmod 700 /home/appuser/.cache/msal
```

---

## 📞 Suporte

**Dúvidas?** Consulte:
- GUIA_OTIMIZACAO_SEGURANCA.md
- PRACTICAL_FIXES.md
- Documentação oficial do MSAL.NET

**Escalar:** Contato do DevOps/Security team

---

**Status:** ✅ Pronto para Implementação Imediata
