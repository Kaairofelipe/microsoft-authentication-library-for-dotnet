#!/bin/bash
# ============================================================================
# Pre-commit Hook - Validação Antes de Commit
# ============================================================================
# Padrão: NIST Cybersecurity Framework
# Instalação: ln -s scripts/pre-commit.sh .git/hooks/pre-commit
# ============================================================================

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FAILED=0

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; ((FAILED++)); }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

# ============================================================================
# VALIDAÇÕES
# ============================================================================

header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# 1. Validar que .env não está sendo commitado
validate_env_not_committed() {
    header "Validação 1: .env não deve ser commitado"
    
    if git diff --cached --name-only | grep -q "^\.env$"; then
        log_error ".env está sendo commitado!"
        return 1
    fi
    log_success ".env não será commitado"
}

# 2. Validar que nenhum secret está sendo commitado
validate_no_secrets() {
    header "Validação 2: Procurando secrets..."
    
    # Patterns de secret
    PATTERNS=(
        "password.*=.*['\"]"
        "api_key.*=.*['\"]"
        "secret.*=.*['\"]"
        "token.*=.*['\"]"
        "private.*key"
        "BEGIN RSA PRIVATE KEY"
        "begin.*certificate"
    )
    
    for pattern in "${PATTERNS[@]}"; do
        if git diff --cached | grep -iE "$pattern" | grep -qv "example\|fake\|TODO\|your_"; then
            log_error "Padrão potencialmente sensível encontrado: $pattern"
            git diff --cached | grep -iE "$pattern" | head -3
            return 1
        fi
    done
    
    log_success "Nenhum secret potencial encontrado"
}

# 3. Validar Dockerfile.prod se foi modificado
validate_dockerfile() {
    header "Validação 3: Dockerfile.prod"
    
    if git diff --cached --name-only | grep -q "Dockerfile.prod"; then
        if [ ! -f "Dockerfile.prod" ]; then
            log_error "Dockerfile.prod deletado!"
            return 1
        fi
        
        # Checks
        if ! grep -q "^USER " Dockerfile.prod; then
            log_warning "Dockerfile.prod sem USER configurado"
        fi
        
        if grep -iE "password=|secret=" Dockerfile.prod | grep -qv '${'; then
            log_error "Dockerfile.prod tem secrets hardcoded!"
            return 1
        fi
        
        log_success "Dockerfile.prod validado"
    fi
}

# 4. Validar docker-compose.prod.yml se foi modificado
validate_compose() {
    header "Validação 4: docker-compose.prod.yml"
    
    if git diff --cached --name-only | grep -q "docker-compose.prod.yml"; then
        if [ ! -f "docker-compose.prod.yml" ]; then
            log_error "docker-compose.prod.yml deletado!"
            return 1
        fi
        
        # Validar YAML
        if ! docker-compose -f docker-compose.prod.yml config > /dev/null 2>&1; then
            log_error "docker-compose.prod.yml tem YAML inválido!"
            return 1
        fi
        
        # Validar secrets
        if grep "password:" docker-compose.prod.yml | grep -qv '\${'; then
            log_error "docker-compose.prod.yml tem secrets hardcoded!"
            return 1
        fi
        
        log_success "docker-compose.prod.yml validado"
    fi
}

# 5. Validar código .NET se foi modificado
validate_dotnet_code() {
    header "Validação 5: Código .NET"
    
    if git diff --cached --name-only | grep -q "\.cs$"; then
        log_info "Verificando código C#..."
        
        # Procurar por padrões perigosos
        if git diff --cached -- "*.cs" | grep -iE "password.*=|secret.*=|server.*=.*;" | grep -qv "example\|fake\|TODO"; then
            log_warning "Possível hardcoded connection string ou credential"
        fi
        
        # Procurar por logging perigoso
        if git diff --cached -- "*.cs" | grep -iE "Console.WriteLine.*password|Logger.*secret"; then
            log_warning "Possível logging de sensitive data"
        fi
        
        log_success "Análise de código .NET concluída"
    fi
}

# 6. Validar .gitignore
validate_gitignore() {
    header "Validação 6: .gitignore"
    
    if [ ! -f ".gitignore" ]; then
        log_warning ".gitignore não existe"
        return
    fi
    
    REQUIRED_PATTERNS=(
        "\.env"
        "bin/"
        "obj/"
    )
    
    for pattern in "${REQUIRED_PATTERNS[@]}"; do
        if ! grep -q "^$pattern" .gitignore; then
            log_warning "Padrão não encontrado em .gitignore: $pattern"
        fi
    done
    
    log_success ".gitignore validado"
}

# 7. Validar Markdown files (documentação)
validate_markdown() {
    header "Validação 7: Documentação"
    
    if git diff --cached --name-only | grep -q "\.md$"; then
        log_info "Verificando documentação..."
        
        # Procurar por secrets em markdown
        if git diff --cached -- "*.md" | grep -iE "password.*=|api_key.*=|secret_key" | grep -qv "example\|fake"; then
            log_error "Secrets encontrados em documentação!"
            return 1
        fi
        
        log_success "Documentação validada"
    fi
}

# ============================================================================
# EXECUÇÃO
# ============================================================================

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          PRE-COMMIT VALIDATION HOOKS                      ║${NC}"
    echo -e "${BLUE}║                                                            ║${NC}"
    echo -e "${BLUE}║     Padrão: NIST Cybersecurity Framework                  ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    
    # Executar validações
    validate_env_not_committed || true
    validate_no_secrets || true
    validate_dockerfile || true
    validate_compose || true
    validate_dotnet_code || true
    validate_gitignore || true
    validate_markdown || true
    
    # Resultado
    echo ""
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  ✓ PRÉ-COMMIT VALIDAÇÕES PASSARAM - PERMITINDO COMMIT${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
        echo ""
        exit 0
    else
        echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}  ✗ VALIDAÇÕES FALHARAM - BLOQUEANDO COMMIT${NC}"
        echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "Para fazer commit mesmo assim (não recomendado):"
        echo "  git commit --no-verify"
        echo ""
        exit 1
    fi
}

main "$@"
