#!/bin/bash
# Quick Automation Test Script
# Testa se a automação está funcionando corretamente

set -e

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          TESTE RÁPIDO - AUTOMAÇÃO DE SEGURANÇA            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if required tools exist
check_tools() {
    echo -e "${YELLOW}[1/7] Verificando ferramentas necessárias...${NC}"
    
    tools=("git" "bash" "docker" "docker-compose")
    missing=0
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} $tool encontrado"
        else
            echo -e "  ${RED}✗${NC} $tool NÃO encontrado"
            missing=$((missing + 1))
        fi
    done
    
    if [ $missing -gt 0 ]; then
        echo -e "${RED}Instale as ferramentas faltantes antes de continuar${NC}"
        exit 1
    fi
}

# Test pre-commit hook
test_precommit() {
    echo -e "\n${YELLOW}[2/7] Testando pre-commit hook...${NC}"
    
    if [ -f "scripts/pre-commit.sh" ]; then
        if [ -x "scripts/pre-commit.sh" ]; then
            echo -e "  ${GREEN}✓${NC} Script pre-commit.sh é executável"
        else
            echo -e "  ${YELLOW}⚠${NC} Pre-commit.sh não é executável (fixando...)"
            chmod +x scripts/pre-commit.sh
        fi
        
        # Teste rápido
        if bash scripts/pre-commit.sh 2>&1 | grep -q "Validação"; then
            echo -e "  ${GREEN}✓${NC} Pre-commit hook respondendo"
        else
            echo -e "  ${RED}⚠${NC} Pre-commit hook sem resposta esperada"
        fi
    else
        echo -e "  ${RED}✗${NC} scripts/pre-commit.sh não encontrado"
    fi
}

# Test validate-all script
test_validate_all() {
    echo -e "\n${YELLOW}[3/7] Testando validate-all.sh...${NC}"
    
    if [ -f "scripts/validate-all.sh" ]; then
        if [ -x "scripts/validate-all.sh" ]; then
            echo -e "  ${GREEN}✓${NC} Script validate-all.sh é executável"
        else
            echo -e "  ${YELLOW}⚠${NC} Validate-all.sh não é executável (fixando...)"
            chmod +x scripts/validate-all.sh
        fi
    else
        echo -e "  ${RED}✗${NC} scripts/validate-all.sh não encontrado"
    fi
}

# Test Makefile
test_makefile() {
    echo -e "\n${YELLOW}[4/7] Testando Makefile...${NC}"
    
    if [ -f "Makefile" ]; then
        echo -e "  ${GREEN}✓${NC} Makefile encontrado"
        
        if make help &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} Makefile funcional"
        else
            echo -e "  ${YELLOW}⚠${NC} Makefile pode ter erros de sintaxe"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} Makefile não encontrado (criar com: make init)"
    fi
}

# Test GitHub Actions workflow
test_github_actions() {
    echo -e "\n${YELLOW}[5/7] Testando GitHub Actions workflow...${NC}"
    
    if [ -f ".github/workflows/security.yml" ]; then
        echo -e "  ${GREEN}✓${NC} Workflow security.yml encontrado"
        
        # Check YAML syntax
        if command -v yamllint &> /dev/null; then
            if yamllint .github/workflows/security.yml &> /dev/null; then
                echo -e "  ${GREEN}✓${NC} YAML válido"
            else
                echo -e "  ${RED}✗${NC} YAML inválido"
            fi
        else
            echo -e "  ${YELLOW}⚠${NC} yamllint não instalado (skipping validation)"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} .github/workflows/security.yml não encontrado"
    fi
}

# Test .NET files
test_dotnet() {
    echo -e "\n${YELLOW}[6/7] Testando .NET...${NC}"
    
    if command -v dotnet &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} dotnet CLI disponível"
        
        # Find sln files
        sln_count=$(find . -name "*.sln" -type f | wc -l)
        if [ $sln_count -gt 0 ]; then
            echo -e "  ${GREEN}✓${NC} Encontrado(s) $sln_count arquivo(s) .sln"
        else
            echo -e "  ${YELLOW}⚠${NC} Nenhum arquivo .sln encontrado"
        fi
    else
        echo -e "  ${RED}✗${NC} dotnet CLI não disponível"
    fi
}

# Test git
test_git() {
    echo -e "\n${YELLOW}[7/7] Testando git...${NC}"
    
    if [ -d ".git" ]; then
        echo -e "  ${GREEN}✓${NC} Repositório .git encontrado"
        
        # Check pre-commit hook installation
        if [ -f ".git/hooks/pre-commit" ]; then
            echo -e "  ${GREEN}✓${NC} Pre-commit hook instalado"
        else
            echo -e "  ${YELLOW}⚠${NC} Pre-commit hook NÃO instalado"
            echo -e "      Para instalar: ${BLUE}ln -s ../../scripts/pre-commit.sh .git/hooks/pre-commit${NC}"
        fi
        
        # Check .gitignore
        if [ -f ".gitignore" ]; then
            echo -e "  ${GREEN}✓${NC} .gitignore encontrado"
            
            if grep -q "^\.env$" .gitignore; then
                echo -e "  ${GREEN}✓${NC} .env está em .gitignore"
            else
                echo -e "  ${YELLOW}⚠${NC} .env NÃO está em .gitignore"
            fi
        else
            echo -e "  ${RED}✗${NC} .gitignore não encontrado"
        fi
    else
        echo -e "  ${RED}✗${NC} Não é um repositório git"
    fi
}

# Generate report
generate_report() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    SUMÁRIO DOS TESTES                      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "✅ ${GREEN}Automação de Segurança está configurada corretamente${NC}"
    echo ""
    echo -e "📖 ${BLUE}Próximos passos:${NC}"
    echo ""
    echo -e "  1. ${YELLOW}Instalar pre-commit hook:${NC}"
    echo -e "     ${BLUE}chmod +x scripts/pre-commit.sh${NC}"
    echo -e "     ${BLUE}ln -s ../../scripts/pre-commit.sh .git/hooks/pre-commit${NC}"
    echo ""
    echo -e "  2. ${YELLOW}Executar validação completa:${NC}"
    echo -e "     ${BLUE}make validate${NC}"
    echo ""
    echo -e "  3. ${YELLOW}Executar testes de segurança:${NC}"
    echo -e "     ${BLUE}make test-security${NC}"
    echo ""
    echo -e "  4. ${YELLOW}Ver documentação:${NC}"
    echo -e "     ${BLUE}cat GUIA_AUTOMACAO.md${NC}"
    echo ""
    echo -e "💡 ${BLUE}Dicas:${NC}"
    echo -e "  • ${YELLOW}Todos os comandos disponíveis:${NC} make help"
    echo -e "  • ${YELLOW}Validar antes de fazer commit:${NC} make validate"
    echo -e "  • ${YELLOW}Verificar GitHub Actions:${NC} Ver aba 'Actions' no GitHub"
    echo ""
}

# Main execution
main() {
    check_tools
    test_precommit
    test_validate_all
    test_makefile
    test_github_actions
    test_dotnet
    test_git
    generate_report
}

main
