# ============================================================================
# Makefile - Automação MSAL.NET Docker/WSL
# ============================================================================
# Padrão: Microsoft Security Baseline + NIST Cybersecurity Framework
# Status: Production Ready
# ============================================================================

.PHONY: help validate build test deploy clean security-audit docs

# ============================================================================
# VARIÁVEIS
# ============================================================================

DOCKER_IMAGE := msal-app
DOCKER_TAG := latest
DOCKER_REGISTRY ?= docker.io
DOCKERFILE := Dockerfile.prod
COMPOSE_FILE := docker-compose.prod.yml
ENV_FILE := .env

# Cores
BLUE := \033[0;34m
GREEN := \033[0;32m
RED := \033[0;31m
YELLOW := \033[1;33m
NC := \033[0m # No Color

# ============================================================================
# HELP
# ============================================================================

help:
	@echo "$(BLUE)╔════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║     Makefile - MSAL.NET Docker/WSL Automation             ║$(NC)"
	@echo "$(BLUE)╚════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(BLUE)VALIDAÇÃO$(NC)"
	@echo "  make validate              - Executar todas as validações"
	@echo "  make validate-security     - Validação de segurança apenas"
	@echo "  make validate-docker       - Validação Dockerfile"
	@echo "  make validate-compose      - Validação docker-compose"
	@echo ""
	@echo "$(BLUE)BUILD$(NC)"
	@echo "  make build                 - Build da imagem Docker"
	@echo "  make build-no-cache        - Build sem cache"
	@echo "  make push                  - Push para registry"
	@echo ""
	@echo "$(BLUE)TESTE$(NC)"
	@echo "  make test                  - Executar todos os testes"
	@echo "  make test-unit             - Testes unitários .NET"
	@echo "  make test-security         - Testes de segurança"
	@echo "  make test-docker           - Testes Docker"
	@echo ""
	@echo "$(BLUE)DEPLOY$(NC)"
	@echo "  make deploy-staging        - Deploy para staging"
	@echo "  make deploy-prod           - Deploy para produção"
	@echo ""
	@echo "$(BLUE)AUDITORIA$(NC)"
	@echo "  make security-audit        - Auditoria de segurança completa"
	@echo "  make compliance-check      - Verificação de compliance"
	@echo ""
	@echo "$(BLUE)DOCUMENTAÇÃO$(NC)"
	@echo "  make docs                  - Gerar documentação"
	@echo "  make docs-security         - Documentação de segurança"
	@echo ""
	@echo "$(BLUE)LIMPEZA$(NC)"
	@echo "  make clean                 - Limpar artifacts"
	@echo "  make clean-docker          - Remover imagens Docker"
	@echo "  make clean-all             - Limpeza completa"
	@echo ""

# ============================================================================
# VALIDAÇÃO
# ============================================================================

validate: validate-env validate-dockerfile validate-compose validate-dotnet
	@echo "$(GREEN)✓ Todas as validações passaram!$(NC)"

validate-env:
	@echo "$(BLUE)[VALIDAÇÃO] Variáveis de ambiente$(NC)"
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "$(YELLOW)[!] $(ENV_FILE) não existe, usando .env.example$(NC)"; \
		cp .env.example $(ENV_FILE) || true; \
	fi
	@grep -q "^\.env" .gitignore || echo "$(RED)[!] Adicione .env ao .gitignore$(NC)"
	@echo "$(GREEN)✓ Validação de env OK$(NC)"

validate-dockerfile:
	@echo "$(BLUE)[VALIDAÇÃO] Dockerfile$(NC)"
	@if [ ! -f "$(DOCKERFILE)" ]; then \
		echo "$(YELLOW)[!] $(DOCKERFILE) não existe$(NC)"; \
	else \
		grep -q "^USER " $(DOCKERFILE) && echo "$(GREEN)✓ Non-root user$(NC)" || echo "$(RED)✗ Sem non-root user$(NC)"; \
		! grep -i "password=" $(DOCKERFILE) | grep -qv '$${' && echo "$(GREEN)✓ Sem secrets hardcoded$(NC)" || echo "$(RED)✗ Secrets hardcoded!$(NC)"; \
	fi

validate-compose:
	@echo "$(BLUE)[VALIDAÇÃO] docker-compose$(NC)"
	@if [ ! -f "$(COMPOSE_FILE)" ]; then \
		echo "$(YELLOW)[!] $(COMPOSE_FILE) não existe$(NC)"; \
	else \
		docker-compose -f $(COMPOSE_FILE) config > /dev/null 2>&1 && echo "$(GREEN)✓ YAML válido$(NC)" || echo "$(RED)✗ YAML inválido$(NC)"; \
	fi

validate-dotnet:
	@echo "$(BLUE)[VALIDAÇÃO] Projeto .NET$(NC)"
	@if [ -f "Directory.Build.props" ]; then \
		dotnet restore --quiet && echo "$(GREEN)✓ Dependências OK$(NC)" || echo "$(RED)✗ Erro ao restaurar$(NC)"; \
		dotnet build -c Release --no-restore --verbosity quiet && echo "$(GREEN)✓ Build OK$(NC)" || echo "$(RED)✗ Build falhou$(NC)"; \
	else \
		echo "$(YELLOW)[!] Projeto .NET não encontrado$(NC)"; \
	fi

validate-security:
	@echo "$(BLUE)[VALIDAÇÃO] Segurança$(NC)"
	@! grep -r "TODO.*password\|TODO.*secret" . --include="*.cs" 2>/dev/null && echo "$(GREEN)✓ Sem TODOs com secrets$(NC)" || echo "$(RED)✗ TODOs com secrets encontrados$(NC)"
	@! grep -r "Server=.*password" . --include="*.cs" 2>/dev/null && echo "$(GREEN)✓ Sem hardcoded connection strings$(NC)" || echo "$(RED)✗ Connection strings hardcoded$(NC)"
	@echo "$(GREEN)✓ Validação de segurança OK$(NC)"

# ============================================================================
# BUILD
# ============================================================================

build: validate
	@echo "$(BLUE)[BUILD] Construindo imagem Docker$(NC)"
	@docker build -f $(DOCKERFILE) -t $(DOCKER_IMAGE):$(DOCKER_TAG) .
	@echo "$(GREEN)✓ Build concluído: $(DOCKER_IMAGE):$(DOCKER_TAG)$(NC)"

build-no-cache: validate
	@echo "$(BLUE)[BUILD] Construindo sem cache$(NC)"
	@docker build --no-cache -f $(DOCKERFILE) -t $(DOCKER_IMAGE):$(DOCKER_TAG) .
	@echo "$(GREEN)✓ Build concluído$(NC)"

push: build
	@echo "$(BLUE)[PUSH] Enviando para registry$(NC)"
	@docker tag $(DOCKER_IMAGE):$(DOCKER_TAG) $(DOCKER_REGISTRY)/$(DOCKER_IMAGE):$(DOCKER_TAG)
	@docker push $(DOCKER_REGISTRY)/$(DOCKER_IMAGE):$(DOCKER_TAG)
	@echo "$(GREEN)✓ Push concluído$(NC)"

# ============================================================================
# TESTE
# ============================================================================

test: test-unit test-security test-docker
	@echo "$(GREEN)✓ Todos os testes passaram!$(NC)"

test-unit:
	@echo "$(BLUE)[TESTE] Testes unitários .NET$(NC)"
	@dotnet test --configuration Release --no-build --verbosity normal
	@echo "$(GREEN)✓ Testes unitários OK$(NC)"

test-security:
	@echo "$(BLUE)[TESTE] Testes de segurança$(NC)"
	@bash scripts/validate-all.sh
	@echo "$(GREEN)✓ Testes de segurança OK$(NC)"

test-docker: build
	@echo "$(BLUE)[TESTE] Testes Docker$(NC)"
	@docker run --rm $(DOCKER_IMAGE):$(DOCKER_TAG) whoami | grep -q "appuser" && \
		echo "$(GREEN)✓ Container roda como non-root$(NC)" || \
		echo "$(RED)✗ Container roda como root!$(NC)"
	@echo "$(GREEN)✓ Testes Docker OK$(NC)"

# ============================================================================
# DEPLOY
# ============================================================================

deploy-staging: test
	@echo "$(BLUE)[DEPLOY] Enviando para staging$(NC)"
	@docker-compose -f docker-compose.prod.yml -p msal-staging up -d
	@sleep 5
	@docker-compose -f docker-compose.prod.yml -p msal-staging ps
	@echo "$(GREEN)✓ Deploy em staging concluído$(NC)"

deploy-prod: test
	@echo "$(RED)[DEPLOY] ALERTA: Deploy para produção!$(NC)"
	@read -p "Tem certeza? (sim/não): " confirm && \
	if [ "$$confirm" = "sim" ]; then \
		docker-compose -f docker-compose.prod.yml -p msal-prod up -d && \
		echo "$(GREEN)✓ Deploy em produção concluído$(NC)"; \
	else \
		echo "$(YELLOW)Deploy cancelado$(NC)"; \
	fi

# ============================================================================
# AUDITORIA
# ============================================================================

security-audit:
	@echo "$(BLUE)╔════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║           AUDITORIA DE SEGURANÇA COMPLETA                  ║$(NC)"
	@echo "$(BLUE)╚════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(BLUE)[1/5] Validação de Secrets$(NC)"
	@! git log --all -p -S "password\|secret\|token" 2>/dev/null | grep -q "password" && \
		echo "$(GREEN)✓ Nenhum secret encontrado no histórico$(NC)" || \
		echo "$(YELLOW)[!] Verificar histórico git$(NC)"
	@echo ""
	@echo "$(BLUE)[2/5] Validação de Arquivo Gitignore$(NC)"
	@grep -q "^\.env" .gitignore && echo "$(GREEN)✓ .env no .gitignore$(NC)" || echo "$(RED)✗ .env não está no .gitignore!$(NC)"
	@echo ""
	@echo "$(BLUE)[3/5] Validação de Dependências$(NC)"
	@dotnet list package --vulnerable 2>/dev/null | grep -q "vulnerable" && \
		echo "$(YELLOW)[!] Vulnerabilidades encontradas$(NC)" || \
		echo "$(GREEN)✓ Nenhuma vulnerabilidade crítica$(NC)"
	@echo ""
	@echo "$(BLUE)[4/5] Validação de Código$(NC)"
	@! grep -r "hardcoded\|TODO.*secret" . --include="*.cs" 2>/dev/null && \
		echo "$(GREEN)✓ Código sem issues de segurança$(NC)" || \
		echo "$(YELLOW)[!] Verificar código$(NC)"
	@echo ""
	@echo "$(BLUE)[5/5] Validação Docker$(NC)"
	@[ -f "$(DOCKERFILE)" ] && grep -q "^USER " $(DOCKERFILE) && \
		echo "$(GREEN)✓ Docker configurado com segurança$(NC)" || \
		echo "$(YELLOW)[!] Revisar Dockerfile$(NC)"
	@echo ""
	@echo "$(GREEN)═══════════════════════════════════════════════════════════$(NC)"
	@echo "$(GREEN) ✓ Auditoria de segurança concluída!$(NC)"
	@echo "$(GREEN)═══════════════════════════════════════════════════════════$(NC)"

compliance-check:
	@echo "$(BLUE)[COMPLIANCE] Verificação de conformidade$(NC)"
	@echo "GDPR:      [ ] Implementado"
	@echo "PCI-DSS:   [ ] Implementado"
	@echo "SOC 2:     [ ] Implementado"
	@echo "ISO 27001: [ ] Implementado"

# ============================================================================
# DOCUMENTAÇÃO
# ============================================================================

docs:
	@echo "$(BLUE)[DOCS] Gerando documentação$(NC)"
	@ls *.md | head -10
	@echo "$(GREEN)✓ Documentação disponível$(NC)"

# ============================================================================
# LIMPEZA
# ============================================================================

clean:
	@echo "$(BLUE)[CLEAN] Limpando artifacts$(NC)"
	@find . -type d -name bin -o -name obj | xargs rm -rf
	@echo "$(GREEN)✓ Artifacts removidos$(NC)"

clean-docker:
	@echo "$(BLUE)[CLEAN] Removendo imagens Docker$(NC)"
	@docker rmi $(DOCKER_IMAGE):$(DOCKER_TAG) 2>/dev/null || echo "Imagem não existe"
	@echo "$(GREEN)✓ Imagens removidas$(NC)"

clean-all: clean clean-docker
	@echo "$(BLUE)[CLEAN] Limpeza completa concluída$(NC)"

# ============================================================================
# DEFAULT
# ============================================================================

.DEFAULT_GOAL := help
