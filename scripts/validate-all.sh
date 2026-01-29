#!/bin/bash
# ============================================================================
# validate-all.sh - Validação Completa de Segurança e Qualidade
# ============================================================================
# Status: Production Ready
# Padrão: Microsoft Security Baseline
# ============================================================================

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Contadores
PASSED=0
FAILED=0
WARNINGS=0

# ============================================================================
# FUNÇÕES AUXILIARES
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((PASSED++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
    ((WARNINGS++))
}

header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ============================================================================
# VALIDAÇÕES DOCKERFILE
# ============================================================================

validate_dockerfile() {
    header "1. VALIDAÇÃO DOCKERFILE"
    
    if [ ! -f "Dockerfile.prod" ]; then
        log_warning "Dockerfile.prod não existe (opcional na Fase 0)"
        return
    fi
    
    # Check: Tem FROM
    if grep -q "^FROM" Dockerfile.prod; then
        log_success "Tem declaração FROM"
    else
        log_error "Declaração FROM não encontrada"
        return 1
    fi
    
    # Check: Não executa como root
    if grep -q "^USER " Dockerfile.prod && ! grep "^USER root" Dockerfile.prod; then
        log_success "Executa como non-root"
    else
        log_error "Container executa como root!"
        return 1
    fi
    
    # Check: Sem hardcoded passwords
    if ! grep -i "password=\|secret=\|token=" Dockerfile.prod | grep -qv '${'; then
        log_success "Sem secrets hardcoded"
    else
        log_error "Secrets hardcoded encontrados!"
        return 1
    fi
    
    # Check: Limpeza de cache apt
    if grep -q "rm -rf /var/lib/apt/lists" Dockerfile.prod; then
        log_success "Cache apt limpo"
    else
        log_warning "Cache apt não limpo (aumenta imagem)"
    fi
    
    # Check: Health check
    if grep -q "HEALTHCHECK" Dockerfile.prod; then
        log_success "HEALTHCHECK configurado"
    else
        log_warning "HEALTHCHECK não configurado (recomendado)"
    fi
}

# ============================================================================
# VALIDAÇÕES DOCKER-COMPOSE
# ============================================================================

validate_docker_compose() {
    header "2. VALIDAÇÃO DOCKER-COMPOSE"
    
    if [ ! -f "docker-compose.prod.yml" ]; then
        log_warning "docker-compose.prod.yml não existe (opcional na Fase 0)"
        return
    fi
    
    # Check: Sintaxe YAML válida
    if docker-compose -f docker-compose.prod.yml config > /dev/null 2>&1; then
        log_success "Sintaxe YAML válida"
    else
        log_error "Erro na sintaxe YAML!"
        return 1
    fi
    
    # Check: Não tem secrets hardcoded
    if ! grep "password:" docker-compose.prod.yml | grep -qv '\${'; then
        log_success "Sem secrets hardcoded"
    else
        log_error "Secrets hardcoded encontrados!"
        return 1
    fi
    
    # Check: Tem read_only
    if grep -q "read_only: true" docker-compose.prod.yml; then
        log_success "Filesystem read-only ativado"
    else
        log_warning "Filesystem read-only não configurado"
    fi
    
    # Check: Tem cap_drop
    if grep -q "cap_drop:" docker-compose.prod.yml; then
        log_success "Capabilities removidas"
    else
        log_warning "Capabilities não removidas (security risk)"
    fi
    
    # Check: Tem resource limits
    if grep -q "memory:" docker-compose.prod.yml; then
        log_success "Resource limits configurados"
    else
        log_warning "Resource limits não configurados"
    fi
}

# ============================================================================
# VALIDAÇÕES .ENV
# ============================================================================

validate_env() {
    header "3. VALIDAÇÃO VARIÁVEIS DE AMBIENTE"
    
    # Check: .env está no .gitignore
    if grep -q "^\.env" .gitignore 2>/dev/null; then
        log_success ".env no .gitignore"
    else
        log_error ".env NÃO está no .gitignore!"
        return 1
    fi
    
    # Check: Existe .env.example
    if [ -f ".env.example" ]; then
        log_success ".env.example existe"
    else
        log_warning ".env.example não existe (recomendado)"
    fi
    
    # Check: .env.example não tem valores sensíveis
    if [ -f ".env.example" ]; then
        if ! grep -i "password=\|secret=\|token=" .env.example | grep -qv "example\|fake\|your_"; then
            log_success ".env.example sem valores sensíveis"
        else
            log_error ".env.example contém valores sensíveis!"
            return 1
        fi
    fi
}

# ============================================================================
# VALIDAÇÕES GIT
# ============================================================================

validate_git() {
    header "4. VALIDAÇÃO GIT"
    
    # Check: Tem .gitignore
    if [ -f ".gitignore" ]; then
        log_success ".gitignore existe"
    else
        log_warning ".gitignore não existe"
    fi
    
    # Check: Não tem secrets commitados
    if ! git log --all -p --diff-filter=A -S "BEGIN RSA PRIVATE KEY" 2>/dev/null | grep -q "BEGIN RSA PRIVATE KEY"; then
        log_success "Nenhuma private key commitada"
    else
        log_error "PRIVATE KEY encontrada no git!"
        return 1
    fi
    
    # Check: Não tem .env commitado
    if ! git ls-files | grep -q "\.env$"; then
        log_success ".env não está no git"
    else
        log_error ".env está commitado no git!"
        return 1
    fi
}

# ============================================================================
# VALIDAÇÕES CÓDIGO .NET
# ============================================================================

validate_dotnet() {
    header "5. VALIDAÇÃO CÓDIGO .NET"
    
    if [ ! -f "Directory.Build.props" ]; then
        log_warning "Projeto .NET não encontrado"
        return
    fi
    
    # Check: Restaurar dependências
    log_info "Restaurando dependências..."
    if dotnet restore --quiet 2>/dev/null; then
        log_success "Dependências restauradas"
    else
        log_error "Erro ao restaurar dependências"
        return 1
    fi
    
    # Check: Build sem erros
    log_info "Compilando projeto..."
    if dotnet build -c Release --no-restore --verbosity quiet 2>/dev/null; then
        log_success "Build bem-sucedido"
    else
        log_error "Build falhou"
        return 1
    fi
    
    # Check: Vulnerabilidades em dependências
    log_info "Verificando vulnerabilidades..."
    VULN_COUNT=$(dotnet list package --vulnerable 2>/dev/null | grep -c "vulnerable" || echo "0")
    if [ "$VULN_COUNT" -eq 0 ]; then
        log_success "Nenhuma vulnerabilidade crítica"
    else
        log_error "Encontradas $VULN_COUNT vulnerabilidades!"
        return 1
    fi
}

# ============================================================================
# VALIDAÇÕES SEGURANÇA
# ============================================================================

validate_security() {
    header "6. VALIDAÇÃO SEGURANÇA"
    
    # Check: Não tem TODO secrets
    if grep -r "TODO.*password\|TODO.*secret\|TODO.*token" . --include="*.cs" 2>/dev/null; then
        log_error "TODOs com secrets encontrados"
    else
        log_success "Sem TODOs com secrets"
    fi
    
    # Check: Não tem hardcoded connection strings
    if grep -r "Server=.*password\|User Id=.*password" . --include="*.cs" 2>/dev/null; then
        log_error "Connection strings hardcoded encontradas"
    else
        log_success "Sem connection strings hardcoded"
    fi
    
    # Check: Tem HTTPS em URLs
    if grep -r "http://" . --include="*.cs" --include="*.md" 2>/dev/null | grep -v "localhost\|127.0.0.1" | head -5; then
        log_warning "URLs HTTP encontradas (não-localhost)"
    else
        log_success "URLs HTTPS configuradas"
    fi
}

# ============================================================================
# VALIDAÇÕES DOCKER IMAGE (se build estiver feito)
# ============================================================================

validate_docker_image() {
    header "7. VALIDAÇÃO DOCKER IMAGE"
    
    if [ ! -f "Dockerfile.prod" ]; then
        log_info "Pulando validação de imagem (Dockerfile.prod não existe)"
        return
    fi
    
    log_info "Construindo imagem para teste..."
    
    # Build com tag temporária
    if docker build -f Dockerfile.prod -t msal-validate:test . > /tmp/docker-build.log 2>&1; then
        log_success "Build Docker bem-sucedido"
        
        # Check: Usuário non-root
        USER=$(docker run --rm msal-validate:test whoami 2>/dev/null || echo "unknown")
        if [ "$USER" != "root" ] && [ "$USER" != "unknown" ]; then
            log_success "Container roda como $USER (não-root)"
        else
            log_error "Container roda como root!"
        fi
        
        # Check: Image size
        SIZE=$(docker images msal-validate:test --format "{{.Size}}")
        log_success "Tamanho da imagem: $SIZE"
        
        # Cleanup
        docker rmi msal-validate:test > /dev/null 2>&1 || true
    else
        log_error "Build Docker falhou (ver /tmp/docker-build.log)"
    fi
}

# ============================================================================
# VALIDAÇÕES DOCUMENTAÇÃO
# ============================================================================

validate_documentation() {
    header "8. VALIDAÇÃO DOCUMENTAÇÃO"
    
    # Check: README.md existe
    if [ -f "README.md" ]; then
        log_success "README.md existe"
    else
        log_warning "README.md não existe"
    fi
    
    # Check: Documentação de setup existe
    if ls *.md | grep -iq "setup\|install\|readme"; then
        log_success "Documentação de setup encontrada"
    else
        log_warning "Documentação de setup não encontrada"
    fi
    
    # Check: Não tem senhas em docs
    if ! grep -r "password=\|secret=" . --include="*.md" | grep -qv "example\|fake\|your_"; then
        log_success "Docs sem senhas expostas"
    else
        log_error "Senhas encontradas em documentação!"
    fi
}

# ============================================================================
# RESUMO FINAL
# ============================================================================

summary() {
    header "RESUMO FINAL"
    
    TOTAL=$((PASSED + FAILED + WARNINGS))
    PASS_RATE=$((PASSED * 100 / TOTAL))
    
    echo "Total de Verificações: $TOTAL"
    echo "Passou: $PASSED ✓"
    echo "Falhou: $FAILED ✗"
    echo "Avisos: $WARNINGS !"
    echo ""
    echo "Taxa de Sucesso: $PASS_RATE%"
    echo ""
    
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  ✓ TODAS AS VALIDAÇÕES PASSARAM!${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
        return 0
    else
        echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}  ✗ ALGUMAS VALIDAÇÕES FALHARAM!${NC}"
        echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
        return 1
    fi
}

# ============================================================================
# EXECUÇÃO PRINCIPAL
# ============================================================================

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     VALIDAÇÃO COMPLETA - MSAL.NET Docker/WSL             ║${NC}"
    echo -e "${BLUE}║                                                            ║${NC}"
    echo -e "${BLUE}║     Padrão: Microsoft Security Baseline                   ║${NC}"
    echo -e "${BLUE}║     Data: $(date '+%d/%m/%Y %H:%M:%S')                          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Executar validações
    validate_dockerfile || true
    validate_docker_compose || true
    validate_env || true
    validate_git || true
    validate_dotnet || true
    validate_security || true
    validate_docker_image || true
    validate_documentation || true
    
    # Resumo
    summary
}

# Executar
main "$@"
exit $FAILED
