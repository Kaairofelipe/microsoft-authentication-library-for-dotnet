# 📊 Monitoramento, Alertas e Compliance

**Status:** Pronto para Produção  
**Nível:** Enterprise  

---

## 🎯 Objetivos de Monitoramento

### Segurança (Prioridade ALTA)
- ❌ Tentativas de acesso não autorizado
- ❌ Falhas de autenticação suspeitas
- ❌ Variações anormais em uso de memória/CPU
- ❌ Containers reiniciando constantemente

### Performance (Prioridade ALTA)
- ⏱️ Tempo de resposta do MSAL (target: < 100ms)
- 🔄 Taxa de cache hit (target: > 95%)
- 💾 Uso de memória (target: < 256MB)
- 🚀 Throughput (target: > 100 req/s)

### Disponibilidade (Prioridade MÉDIA)
- 📈 Uptime (target: 99.95%)
- 🔄 Restart count (target: < 1/dia)
- 🌐 Health check status
- 🔗 Dependências (Redis, D-Bus)

---

## 📈 Prometheus Metrics

**Arquivo:** `src/Monitoring/MetricsService.cs`

```csharp
using Prometheus;

public class MetricsService
{
    // Counters
    private static readonly Counter AuthenticationSuccesses = 
        Counter
            .Create("msal_auth_successes_total", 
                "Total de autenticações bem-sucedidas",
                new CounterConfiguration { LabelNames = new[] { "method" } });
    
    private static readonly Counter AuthenticationFailures = 
        Counter
            .Create("msal_auth_failures_total", 
                "Total de autenticações falhadas",
                new CounterConfiguration 
                { 
                    LabelNames = new[] { "method", "error_type" } 
                });
    
    private static readonly Counter TokenCacheHits = 
        Counter
            .Create("msal_cache_hits_total", 
                "Total de cache hits",
                new CounterConfiguration { LabelNames = new[] { "cache_type" } });
    
    private static readonly Counter TokenCacheMisses = 
        Counter
            .Create("msal_cache_misses_total", 
                "Total de cache misses",
                new CounterConfiguration { LabelNames = new[] { "cache_type" } });
    
    // Gauges
    private static readonly Gauge AuthenticationDuration = 
        Gauge
            .Create("msal_auth_duration_ms", 
                "Duração da autenticação em ms",
                new GaugeConfiguration { LabelNames = new[] { "method" } });
    
    private static readonly Gauge CacheSize = 
        Gauge
            .Create("msal_cache_size_bytes", 
                "Tamanho do cache em bytes",
                new GaugeConfiguration { LabelNames = new[] { "cache_type" } });
    
    private static readonly Gauge ActiveTokens = 
        Gauge
            .Create("msal_active_tokens", 
                "Número de tokens ativos",
                new GaugeConfiguration { LabelNames = new[] { "type" } });
    
    // Histograms
    private static readonly Histogram AuthenticationLatency = 
        Histogram
            .Create("msal_auth_latency_seconds", 
                "Latência de autenticação em segundos",
                new HistogramConfiguration 
                { 
                    LabelNames = new[] { "method" },
                    Buckets = new[] { 0.01, 0.05, 0.1, 0.5, 1.0, 2.0 }
                });
    
    // Métodos públicos
    public static void RecordAuthenticationSuccess(string method, long durationMs)
    {
        AuthenticationSuccesses.Labels(method).Inc();
        AuthenticationDuration.Labels(method).Set(durationMs);
        AuthenticationLatency.Labels(method).Observe(durationMs / 1000d);
    }
    
    public static void RecordAuthenticationFailure(string method, string errorType)
    {
        AuthenticationFailures.Labels(method, errorType).Inc();
    }
    
    public static void RecordCacheHit(string cacheType)
    {
        TokenCacheHits.Labels(cacheType).Inc();
    }
    
    public static void RecordCacheMiss(string cacheType)
    {
        TokenCacheMisses.Labels(cacheType).Inc();
    }
    
    public static void SetCacheSize(string cacheType, long sizeBytes)
    {
        CacheSize.Labels(cacheType).Set(sizeBytes);
    }
    
    public static void SetActiveTokens(string type, int count)
    {
        ActiveTokens.Labels(type).Set(count);
    }
}
```

**Integração no Program.cs:**

```csharp
// Program.cs
builder.Services.AddSingleton<MetricsService>();

// Middleware Prometheus
app.UseHttpMetrics();

// Endpoint para metrics
app.MapMetrics();

// Health checks com metrics
app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = UIResponseWriter.WriteHealthCheckUIResponse
});
```

---

## 🚨 Alertas com AlertManager

**Arquivo:** `monitoring/prometheus-rules.yml`

```yaml
groups:
  - name: msal_alerts
    interval: 30s
    rules:
      # ===== SEGURANÇA =====
      
      - alert: HighAuthenticationFailureRate
        expr: |
          rate(msal_auth_failures_total[5m]) /
          (rate(msal_auth_successes_total[5m]) + rate(msal_auth_failures_total[5m])) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Taxa alta de falhas de autenticação"
          description: "Taxa de falhas > 5% nos últimos 5 minutos"
          runbook: "https://wiki.example.com/runbooks/auth-failures"
      
      - alert: TokenCacheExhausted
        expr: msal_active_tokens > 1000
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Cache de tokens quase cheio"
          description: "{{ $value }} tokens ativos em memória"
      
      - alert: UnauthorizedAccessAttempts
        expr: |
          rate(msal_auth_failures_total{error_type="unauthorized"}[5m]) > 10
        for: 2m
        labels:
          severity: high
        annotations:
          summary: "Múltiplas tentativas de acesso não autorizado"
          description: "{{ $value }} tentativas/min detectadas"
      
      # ===== PERFORMANCE =====
      
      - alert: SlowAuthentication
        expr: histogram_quantile(0.95, msal_auth_latency_seconds) > 1.0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Autenticação lenta detectada"
          description: "p95 latência: {{ $value }}s"
          runbook: "https://wiki.example.com/runbooks/slow-auth"
      
      - alert: LowCacheHitRate
        expr: |
          rate(msal_cache_hits_total[5m]) /
          (rate(msal_cache_hits_total[5m]) + rate(msal_cache_misses_total[5m])) < 0.8
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Taxa de cache hits abaixo do esperado"
          description: "Hit rate: {{ $value | humanizePercentage }}"
      
      - alert: HighMemoryUsage
        expr: container_memory_usage_bytes{image="msal-app"} > 512000000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Uso de memória alto no container MSAL"
          description: "Memória atual: {{ $value | humanize }}B"
      
      - alert: HighCpuUsage
        expr: |
          rate(container_cpu_usage_seconds_total{image="msal-app"}[5m]) > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Uso de CPU alto no container MSAL"
          description: "CPU atual: {{ $value | humanizePercentage }}"
      
      # ===== DISPONIBILIDADE =====
      
      - alert: ContainerRestarting
        expr: |
          rate(container_last_seen{image="msal-app"}[5m]) > 0.1
        for: 1m
        labels:
          severity: high
        annotations:
          summary: "Container MSAL reiniciando constantemente"
          description: "Detectados múltiplos restarts"
      
      - alert: HealthCheckFailing
        expr: up{job="msal-app"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Health check do MSAL falhando"
          description: "Container em estado unhealthy"
      
      - alert: RedisPingFailing
        expr: redis_up{instance="redis:6379"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Redis indisponível"
          description: "Cache remoto não está respondendo"
      
      - alert: LowUptimePercentage
        expr: |
          (1 - (increase(container_restarts_total[24h]) / 1440)) < 0.9995
        labels:
          severity: warning
        annotations:
          summary: "Uptime abaixo de 99.95%"
          description: "Uptime: {{ $value | humanizePercentage }}"
```

---

## 📋 Prometheus Configuration

**Arquivo:** `monitoring/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'msal-monitor'

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

rule_files:
  - "prometheus-rules.yml"

scrape_configs:
  # MSAL App
  - job_name: 'msal-app'
    static_configs:
      - targets: ['msal-app:5000']
    metrics_path: '/metrics'
    scrape_interval: 10s
    scrape_timeout: 5s
  
  # Redis
  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']
    scrape_interval: 15s
  
  # Docker
  - job_name: 'docker'
    static_configs:
      - targets: ['unix:///var/run/docker.sock']
    scrape_interval: 30s
  
  # Node Exporter (sistema)
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
    scrape_interval: 30s
  
  # Prometheus self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
```

---

## 🔔 AlertManager Configuration

**Arquivo:** `monitoring/alertmanager.yml`

```yaml
global:
  resolve_timeout: 5m
  slack_api_url: "${SLACK_WEBHOOK_URL}"

route:
  # Root route com defaults
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'default'
  
  # Sub-routes com regras específicas
  routes:
    # Alertas críticos → PagerDuty imediato
    - match:
        severity: critical
      receiver: 'pagerduty'
      group_wait: 0s
      repeat_interval: 15m
    
    # Alertas de segurança → email + Slack
    - match:
        severity: high
      receiver: 'security-team'
      group_wait: 1m
    
    # Alertas de warning → Slack apenas
    - match:
        severity: warning
      receiver: 'slack-warnings'
      group_wait: 5m

receivers:
  - name: 'default'
    slack_configs:
      - channel: '#msal-alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
  
  - name: 'pagerduty'
    slack_configs:
      - channel: '#critical-alerts'
        title: '🚨 CRÍTICO: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
    pagerduty_configs:
      - service_key: "${PAGERDUTY_SERVICE_KEY}"
        description: '{{ .GroupLabels.alertname }}'
  
  - name: 'security-team'
    email_configs:
      - to: 'security@example.com'
        from: 'alerts@example.com'
        smarthost: 'smtp.example.com:587'
        auth_username: '${SMTP_USERNAME}'
        auth_password: '${SMTP_PASSWORD}'
        headers:
          Subject: '[SEGURANÇA] {{ .GroupLabels.alertname }}'
    slack_configs:
      - channel: '#security-alerts'
        title: '🔒 SEGURANÇA: {{ .GroupLabels.alertname }}'
  
  - name: 'slack-warnings'
    slack_configs:
      - channel: '#msal-warnings'
        title: '⚠️ {{ .GroupLabels.alertname }}'

inhibit_rules:
  # Não alertar se o container está down (óbvio que auth falha)
  - source_match:
      alertname: 'HealthCheckFailing'
    target_match:
      alertname: 'HighAuthenticationFailureRate'
    equal: ['instance']
  
  # Não alertar de cache miss se Redis está down
  - source_match:
      alertname: 'RedisPingFailing'
    target_match:
      alertname: 'LowCacheHitRate'
    equal: ['instance']
```

---

## 📊 Grafana Dashboards

**Arquivo:** `monitoring/grafana-dashboard.json`

```json
{
  "dashboard": {
    "title": "MSAL.NET Monitoring",
    "tags": ["msal", "authentication"],
    "timezone": "browser",
    "schemaVersion": 16,
    "version": 0,
    "panels": [
      {
        "title": "Autenticações bem-sucedidas/falhadas",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(msal_auth_successes_total[5m])",
            "legendFormat": "Sucesso"
          },
          {
            "expr": "rate(msal_auth_failures_total[5m])",
            "legendFormat": "Falha"
          }
        ]
      },
      {
        "title": "Taxa de cache hit",
        "type": "gauge",
        "targets": [
          {
            "expr": "rate(msal_cache_hits_total[5m]) / (rate(msal_cache_hits_total[5m]) + rate(msal_cache_misses_total[5m]))",
            "legendFormat": "Hit Rate"
          }
        ]
      },
      {
        "title": "Latência de autenticação (p95)",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(msal_auth_latency_seconds_bucket[5m]))",
            "legendFormat": "p95"
          }
        ]
      },
      {
        "title": "Uso de memória",
        "type": "graph",
        "targets": [
          {
            "expr": "container_memory_usage_bytes{image=\"msal-app\"} / 1024 / 1024",
            "legendFormat": "MB"
          }
        ]
      }
    ]
  }
}
```

---

## 📋 Compliance Checklist

### GDPR (Proteção de Dados)
- [ ] Nenhum dados pessoais em logs (emails, IPs, etc.)
- [ ] Tokens nunca armazenados em plaintext
- [ ] Retenção de logs: máximo 30 dias
- [ ] Direito ao esquecimento implementado
- [ ] Criptografia em trânsito (TLS 1.2+)

### PCI-DSS (Pagamentos)
- [ ] Nenhuma senha/token em logs
- [ ] Acesso restrito a dados sensíveis
- [ ] Firewall ativo entre redes
- [ ] Antivírus em servidores
- [ ] Auditoria de mudanças implementada

### SOC 2 (Segurança)
- [ ] Controles de acesso implementados
- [ ] Backup automático
- [ ] Disaster recovery plan
- [ ] Incidentes documentados
- [ ] Treinamento de segurança registrado

### ISO 27001 (Info Security)
- [ ] Risk assessment completado
- [ ] Política de senhas
- [ ] Backup e recovery testados
- [ ] Antecedentes dos funcionários verificados
- [ ] Auditorias internas realizadas

### Padrões Microsoft
- [ ] Seguir Azure Security Baseline
- [ ] Usar Microsoft Defender
- [ ] Habilitar Azure Policy
- [ ] Usar Managed Identity (sem secrets)
- [ ] Auditar via Azure Activity Logs

---

## 🧪 Testes de Segurança Automáticos

**Arquivo:** `tests/SecurityAuditTests.cs`

```csharp
[TestClass]
public class SecurityAuditTests
{
    [TestMethod]
    public async Task LogsAreNotExposingTokens()
    {
        // Simular autenticação e verificar logs
        var logContent = GetApplicationLogs();
        
        Assert.IsFalse(logContent.Contains("eyJ0"),  // JWT header
                      "Logs contêm tokens!");
        Assert.IsFalse(logContent.Contains("Bearer"),
                      "Logs contêm Authorization headers!");
    }
    
    [TestMethod]
    public void ConfidentialClientUsesStrongSecret()
    {
        var secret = Environment.GetEnvironmentVariable("CLIENT_SECRET");
        
        Assert.IsTrue(secret.Length >= 64,
                     "Secret deve ter pelo menos 64 caracteres");
    }
    
    [TestMethod]
    public void NoCacheCredentialsOnDisk()
    {
        var cacheFiles = Directory.GetFiles(
            Path.Combine(Environment.GetFolderPath(
                Environment.SpecialFolder.ApplicationData), "msal"));
        
        foreach (var file in cacheFiles)
        {
            var content = File.ReadAllText(file);
            // Deve estar encriptado (não json legível)
            Assert.IsFalse(content.StartsWith("{"),
                           "Cache file contém JSON legível!");
        }
    }
    
    [TestMethod]
    public async Task ApiRequiresValidToken()
    {
        using var client = new HttpClient();
        
        // Sem token
        var response = await client.GetAsync("https://api.example.com/secure");
        Assert.AreEqual(HttpStatusCode.Unauthorized, response.StatusCode);
        
        // Token inválido
        client.DefaultRequestHeaders.Authorization = 
            new AuthenticationHeaderValue("Bearer", "invalid_token_12345");
        
        response = await client.GetAsync("https://api.example.com/secure");
        Assert.AreEqual(HttpStatusCode.Unauthorized, response.StatusCode);
    }
}
```

---

## 📞 Runbooks

### Runbook: Authentication Failure Spike

```markdown
## Problema: Taxa alta de falhas de autenticação

### 1. Verificar Prometheus
```bash
curl http://prometheus:9090/api/v1/query?query=rate(msal_auth_failures_total[5m])
```

### 2. Verificar logs do container
```bash
docker logs msal-app --tail=100 | grep -i error
```

### 3. Verificar status de dependências
```bash
docker exec msal-app curl http://redis:6379/ping
dbus-send --system --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames
```

### 4. Possíveis causas
- [ ] Redis down → restart Redis
- [ ] D-Bus down → restart systemd
- [ ] Certificados expirados → renovar
- [ ] Credenciais inválidas → verificar secrets
- [ ] Rate limiting → esperar ou escalar

### 5. Ação corretiva
```bash
# Escalar horizontalmente
docker-compose up -d --scale msal-app=3

# Ou reiniciar
docker restart msal-app
```

### 6. Verificar resolução
```bash
# Esperar 5 minutos
sleep 300

# Confirmar métrica normalizada
curl http://prometheus:9090/api/v1/query?query=rate(msal_auth_failures_total[5m])
```
```

---

## 🎯 SLA (Service Level Agreement)

| Métrica | Target | Alerta |
|---------|--------|--------|
| Availability | 99.95% | < 99% em 5min |
| Auth Latency (p95) | < 100ms | > 500ms |
| Cache Hit Rate | > 95% | < 80% |
| Error Rate | < 0.5% | > 1% |
| Memory Usage | < 256MB | > 512MB |
| CPU Usage | < 50% | > 80% |

---

**Status:** ✅ Pronto para Monitoramento Enterprise
