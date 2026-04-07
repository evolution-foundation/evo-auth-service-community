# EvoAuth Service - Makefile
# Common commands for development, testing, and deployment

.PHONY: help install start stop restart test lint security setup clean deploy

# Default target
.DEFAULT_GOAL := help

# Colors for output
RED=\033[0;31m
GREEN=\033[0;32m
YELLOW=\033[1;33m
BLUE=\033[0;34m
NC=\033[0m # No Color

# Help target
help: ## Show this help message
	@echo "$(BLUE)EvoAuth Service - Available Commands$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "$(GREEN)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Quick Start (Evolution Style):$(NC)"
	@echo "  1. $(GREEN)pnpm install$(NC)    - Install dependencies"
	@echo "  2. $(GREEN)pnpm dev$(NC)        - Start development mode"
	@echo "  3. $(GREEN)pnpm health$(NC)     - Check if everything is working"
	@echo ""
	@echo "$(YELLOW)Alternative (Makefile):$(NC)"
	@echo "  1. $(GREEN)make setup$(NC)      - Install dependencies and setup database"
	@echo "  2. $(GREEN)make start$(NC)      - Start the development server"
	@echo "  3. $(GREEN)make health$(NC)     - Check if everything is working"

# =============================================================================
# PADRÃO PADRONIZADO - COMANDOS PRINCIPAIS
# =============================================================================

# Setup completo do projeto (install + db-setup)
setup: install db-setup
	@echo "$(GREEN)✅ Setup completo concluído!$(NC)"

# Instalar dependências
install: ## Instalar dependências
	@echo "$(YELLOW)📦 Instalando dependências...$(NC)"
	bundle install
	@if [ -f package.json ]; then \
		echo "$(YELLOW)Instalando dependências pnpm...$(NC)"; \
		pnpm install || true; \
	fi
	@echo "$(GREEN)✅ Dependências instaladas!$(NC)"

setup-env: ## Copy .env.example to .env if it doesn't exist
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "$(YELLOW)Created .env file from .env.example$(NC)"; \
		echo "$(RED)⚠️  Please update .env with your configuration$(NC)"; \
	else \
		echo "$(GREEN).env file already exists$(NC)"; \
	fi

generate-keys: ## Generate security keys for production
	@echo "$(YELLOW)Generating security keys...$(NC)"
	@echo "SECRET_KEY_BASE=$$(rails secret)"
	@echo ""
	@echo "$(YELLOW)Generating encryption keys...$(NC)"
	@rails db:encryption:init
	@echo "$(GREEN)✓ Keys generated! Add them to your .env file$(NC)"

# =============================================================================
# DEVELOPMENT
# =============================================================================

# Rodar em modo desenvolvimento
dev: ## Rodar em modo desenvolvimento
	@echo "$(YELLOW)🔧 Iniciando EvoAuth Service em modo desenvolvimento...$(NC)"
	@if [ -f ./.overmind.sock ]; then \
		echo "$(YELLOW)Overmind já está rodando. Use 'make force_run' para iniciar uma nova instância.$(NC)"; \
	elif command -v overmind >/dev/null 2>&1 && [ -f Procfile.dev ]; then \
		overmind start -f Procfile.dev; \
	else \
		echo "$(YELLOW)Iniciando Rails server na porta 3001...$(NC)"; \
		rails server -p 3001; \
	fi

# Rodar em modo produção
run: ## Rodar em modo produção
	@echo "$(YELLOW)🚀 Iniciando EvoAuth Service em modo produção...$(NC)"
	RAILS_ENV=production rails server -p 3001

start: dev ## Alias para dev (compatibilidade)

force_run: ## Forçar início com Overmind (limpa sockets e processos)
	@echo "$(YELLOW)🔄 Forçando início do serviço...$(NC)"
	rm -f ./.overmind.sock
	rm -f tmp/pids/*.pid
	overmind start -f Procfile.dev

start-simple: ## Start server without overmind
	@echo "$(YELLOW)Starting Rails server on port 3001...$(NC)"
	rails server -p 3001 &
	@echo "$(YELLOW)Starting Sidekiq...$(NC)"
	bundle exec sidekiq &
	@echo "$(GREEN)✓ Services started$(NC)"

stop: ## Stop all services
	@echo "$(YELLOW)Stopping services...$(NC)"
	@pkill -f "rails server" || true
	@pkill -f "sidekiq" || true
	@pkill -f "overmind" || true
	@echo "$(GREEN)✓ Services stopped$(NC)"

restart: stop dev ## Restart all services

pnpm-install: ## Install pnpm dependencies
	@echo "$(YELLOW)Installing pnpm dependencies...$(NC)"
	@pnpm install
	@echo "$(GREEN)✓ pnpm dependencies installed$(NC)"

pnpm-setup: ## Setup pnpm and install dependencies
	@echo "$(YELLOW)Setting up pnpm...$(NC)"
	@if ! command -v pnpm >/dev/null 2>&1; then \
		echo "$(BLUE)Installing pnpm...$(NC)"; \
		npm install -g pnpm; \
	fi
	@pnpm install
	@echo "$(GREEN)✓ pnpm setup complete$(NC)"

logs: ## Show application logs
	tail -f log/development.log

console: ## Open Rails console
	rails console

routes: ## Show all routes
	rails routes

# =============================================================================
# DATABASE (PADRÃO PADRONIZADO)
# =============================================================================

# Setup do banco de dados (create + migrate)
db-setup: ## Setup inicial do banco (create + migrate)
	@echo "$(YELLOW)🗄️  Configurando banco de dados...$(NC)"
	rails db:create || true
	rails db:migrate
	@echo "$(GREEN)✅ Banco de dados configurado!$(NC)"

# Rodar migrações pendentes
db-migrate: ## Rodar migrações pendentes
	@echo "$(YELLOW)🚀 Rodando migrações pendentes...$(NC)"
	rails db:migrate
	@echo "$(GREEN)✅ Migrações aplicadas!$(NC)"

# Rodar seeds
db-seed: ## Rodar seeds
	@echo "$(YELLOW)🌱 Rodando seeds...$(NC)"
	rails db:seed
	@echo "$(GREEN)✅ Seeds executados!$(NC)"

# Resetar banco completo
db-reset: ## Resetar banco completo
	@echo "$(YELLOW)🔄 Resetando banco de dados...$(NC)"
	@echo "$(RED)⚠️  ATENÇÃO: Isso irá apagar todos os dados!$(NC)"
	@read -p "Tem certeza? [y/N]: " confirm && [ "$$confirm" = "y" ] || exit 1
	rails db:environment:set RAILS_ENV=development 2>/dev/null; rails db:drop db:create db:migrate
	@rm -f .runtime.dat .instance
	@echo "$(GREEN)✅ Banco de dados resetado!$(NC)"

db-rollback: ## Rollback last migration
	rails db:rollback

db-console: ## Open database console
	rails dbconsole

db-backup: ## Create database backup
	@echo "$(YELLOW)Creating database backup...$(NC)"
	@mkdir -p backups
	pg_dump $$(grep DATABASE_URL .env | cut -d '=' -f2) > backups/backup_$$(date +%Y%m%d_%H%M%S).sql
	@echo "$(GREEN)✓ Backup created in backups/$(NC)"

db-restore: ## Restore database from backup (usage: make db-restore BACKUP=filename)
	@if [ -z "$(BACKUP)" ]; then \
		echo "$(RED)Error: Please specify BACKUP=filename$(NC)"; \
		echo "Available backups:"; \
		ls -la backups/; \
		exit 1; \
	fi
	@echo "$(YELLOW)Restoring database from $(BACKUP)...$(NC)"
	rails db:drop db:create
	psql $$(grep DATABASE_URL .env | cut -d '=' -f2) < backups/$(BACKUP)
	@echo "$(GREEN)✓ Database restored$(NC)"

# =============================================================================
# TESTING
# =============================================================================

test: ## Run all tests
	@echo "$(YELLOW)Running tests...$(NC)"
	bundle exec rspec

test-unit: ## Run unit tests only
	bundle exec rspec spec/models spec/services spec/lib

test-integration: ## Run integration tests only
	bundle exec rspec spec/requests spec/controllers

test-coverage: ## Run tests with coverage report
	COVERAGE=true bundle exec rspec

test-watch: ## Run tests in watch mode
	bundle exec guard

# =============================================================================
# CODE QUALITY
# =============================================================================

lint: ## Run code linters
	@echo "$(YELLOW)Running RuboCop...$(NC)"
	bundle exec rubocop

lint-fix: ## Auto-fix linting issues
	@echo "$(YELLOW)Auto-fixing RuboCop issues...$(NC)"
	bundle exec rubocop -A

format: lint-fix ## Alias for lint-fix

check: lint test ## Run linting and tests

# =============================================================================
# SECURITY
# =============================================================================

security: ## Run security checks
	@echo "$(YELLOW)Running security checks...$(NC)"
	@echo "$(BLUE)Checking for vulnerabilities...$(NC)"
	bundle exec bundle-audit check --update
	@echo "$(BLUE)Checking for security issues...$(NC)"
	bundle exec brakeman -q --no-pager

security-update: ## Update security databases
	bundle exec bundle-audit update

audit: security ## Alias for security

# =============================================================================
# DEPENDENCIES
# =============================================================================

deps-install: ## Install/update dependencies
	bundle install

deps-update: ## Update all dependencies
	bundle update

deps-outdated: ## Show outdated dependencies
	bundle outdated

deps-clean: ## Clean unused dependencies
	bundle clean

# =============================================================================
# DEPLOYMENT
# =============================================================================

deploy-staging: ## Deploy to staging environment
	@echo "$(YELLOW)Deploying to staging...$(NC)"
	@echo "$(RED)⚠️  Implement your staging deployment process$(NC)"

deploy-production: ## Deploy to production environment
	@echo "$(YELLOW)Deploying to production...$(NC)"
	@echo "$(RED)⚠️  Implement your production deployment process$(NC)"

build: ## Build production assets
	@echo "$(YELLOW)Building production assets...$(NC)"
	RAILS_ENV=production rails assets:precompile

# =============================================================================
# DOCKER
# =============================================================================

docker-build: ## Build Docker image
	@echo "$(YELLOW)Building Docker image...$(NC)"
	docker build -t evo-auth-service .

docker-run: ## Run Docker container
	@echo "$(YELLOW)Running Docker container...$(NC)"
	docker run -p 3001:3001 --env-file .env evo-auth-service

docker-compose-up: ## Start with docker-compose
	docker-compose up -d

docker-compose-down: ## Stop docker-compose services
	docker-compose down

docker-compose-logs: ## Show docker-compose logs
	docker-compose logs -f

# =============================================================================
# MONITORING & MAINTENANCE
# =============================================================================

health: ## Check application health
	@echo "$(YELLOW)Checking application health...$(NC)"
	@curl -s http://localhost:3001/health | jq . || echo "$(RED)Health check failed$(NC)"

status: ## Show service status
	@echo "$(BLUE)Service Status:$(NC)"
	@pgrep -f "rails server" > /dev/null && echo "$(GREEN)✓ Rails server running$(NC)" || echo "$(RED)✗ Rails server not running$(NC)"
	@pgrep -f "sidekiq" > /dev/null && echo "$(GREEN)✓ Sidekiq running$(NC)" || echo "$(RED)✗ Sidekiq not running$(NC)"
	@redis-cli ping > /dev/null 2>&1 && echo "$(GREEN)✓ Redis running$(NC)" || echo "$(RED)✗ Redis not running$(NC)"
	@pg_isready -q && echo "$(GREEN)✓ PostgreSQL running$(NC)" || echo "$(RED)✗ PostgreSQL not running$(NC)"

monitor: ## Show real-time logs
	@echo "$(YELLOW)Monitoring logs... (Press Ctrl+C to stop)$(NC)"
	tail -f log/development.log | grep --line-buffered -E "(ERROR|WARN|INFO)"

stats: ## Show application statistics
	@echo "$(BLUE)Application Statistics:$(NC)"
	@rails runner "puts \"Users: #{User.count}\""
	@rails runner "puts \"Accounts: #{Account.count}\""
	@rails runner "puts \"Active Sessions: #{User.joins(:access_tokens).distinct.count}\""

# =============================================================================
# UTILITIES
# =============================================================================

clean: ## Clean temporary files and logs
	@echo "$(YELLOW)Cleaning temporary files...$(NC)"
	rm -rf tmp/cache/*
	rm -rf log/*.log
	rm -rf coverage/
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

reset: clean db-reset ## Full reset (database + cleanup)

seed-demo: ## Load demo data for development
	@echo "$(YELLOW)Loading demo data...$(NC)"
	rails runner "DemoDataSeeder.seed!"
	@echo "$(GREEN)✓ Demo data loaded$(NC)"

create-admin: ## Create admin user interactively
	@echo "$(YELLOW)Creating admin user...$(NC)"
	rails runner "AdminUserCreator.create_interactive"

# =============================================================================
# DOCUMENTATION
# =============================================================================

docs: ## Generate API documentation
	@echo "$(YELLOW)Generating API documentation...$(NC)"
	bundle exec yard doc
	@echo "$(GREEN)✓ Documentation generated in doc/$(NC)"

docs-serve: ## Serve documentation locally
	bundle exec yard server --reload

# =============================================================================
# DEVELOPMENT TOOLS
# =============================================================================

annotate: ## Annotate models with schema information
	bundle exec annotate --models --routes --show-indexes --show-foreign-keys

credentials-edit: ## Edit Rails credentials
	EDITOR=nano rails credentials:edit

credentials-show: ## Show Rails credentials
	rails credentials:show

# =============================================================================
# EXAMPLES & TESTING
# =============================================================================

example-requests: ## Show example API requests
	@echo "$(BLUE)Example API Requests:$(NC)"
	@echo ""
	@echo "$(YELLOW)Sign In:$(NC)"
	@echo "curl -X POST http://localhost:3001/auth/sign_in \\"
	@echo "  -H 'Content-Type: application/json' \\"
	@echo "  -d '{\"email\":\"admin@example.com\",\"password\":\"password123\"}'"
	@echo ""
	@echo "$(YELLOW)Validate Token:$(NC)"
	@echo "curl -X GET http://localhost:3001/auth/validate_token \\"
	@echo "  -H 'access-token: YOUR_TOKEN' \\"
	@echo "  -H 'client: YOUR_CLIENT' \\"
	@echo "  -H 'uid: admin@example.com'"
	@echo ""
	@echo "$(YELLOW)Password Reset:$(NC)"
	@echo "curl -X POST http://localhost:3001/auth/password \\"
	@echo "  -H 'Content-Type: application/json' \\"
	@echo "  -d '{\"email\":\"admin@example.com\",\"redirect_url\":\"http://localhost:5173/reset-password\"}'"

test-email: ## Test email configuration
	@echo "$(YELLOW)Testing email configuration...$(NC)"
	@rails runner "ActionMailer::Base.mail(from: ENV['MAILER_SENDER_EMAIL'], to: 'test@example.com', subject: 'EvoAuth Test Email', body: 'Email configuration is working!').deliver_now"
	@echo "$(GREEN)✓ Test email sent$(NC)"

test-bms: ## Test BMS email provider
	@echo "$(YELLOW)Testing BMS email provider...$(NC)"
	@if [ -z "$(BMS_API_KEY)" ]; then \
		echo "$(RED)❌ BMS_API_KEY not set. Please configure BMS_API_KEY environment variable.$(NC)"; \
		exit 1; \
	fi
	@rails runner "ActionMailer::Base.delivery_method = :bms; ActionMailer::Base.mail(from: ENV['MAILER_SENDER_EMAIL'], to: 'test@example.com', subject: 'EvoAuth BMS Test Email', body: 'BMS email provider is working!').deliver_now"
	@echo "$(GREEN)✓ BMS test email sent$(NC)"

test-resend: ## Test Resend email provider
	@echo "$(YELLOW)Testing Resend email provider...$(NC)"
	@if [ -z "$(RESEND_API_KEY)" ]; then \
		echo "$(RED)❌ RESEND_API_KEY not set. Please configure RESEND_API_KEY environment variable.$(NC)"; \
		exit 1; \
	fi
	@rails runner "ActionMailer::Base.delivery_method = :resend; ActionMailer::Base.mail(from: ENV['MAILER_SENDER_EMAIL'], to: 'test@example.com', subject: 'EvoAuth Resend Test Email', body: 'Resend email provider is working!').deliver_now"
	@echo "$(GREEN)✓ Resend test email sent$(NC)"

email-preview: ## Open email previews in browser (development only)
	@echo "$(YELLOW)Starting email preview server...$(NC)"
	@echo "$(BLUE)Visit: http://localhost:3001/rails/mailers$(NC)"

load-test: ## Run basic load test
	@echo "$(YELLOW)Running basic load test...$(NC)"
	@echo "$(RED)⚠️  Install 'ab' (Apache Bench) to run load tests$(NC)"
	# ab -n 100 -c 10 http://localhost:3001/health

# =============================================================================
# INFORMATION
# =============================================================================

info: ## Show project information
	@echo "$(BLUE)EvoAuth Service Information:$(NC)"
	@echo "Ruby Version: $$(ruby --version)"
	@echo "Rails Version: $$(rails --version)"
	@echo "Bundler Version: $$(bundle --version)"
	@echo "Database: PostgreSQL"
	@echo "Cache: Redis"
	@echo "Background Jobs: Sidekiq"
	@echo "Port: 3001"

version: ## Show application version
	@rails runner "puts Rails.application.class.module_parent_name + ' v' + (File.read('VERSION').strip rescue '1.0.0')"

# =============================================================================
# ALIASES
# =============================================================================

s: start ## Alias for start
c: console ## Alias for console
t: test ## Alias for test
l: lint ## Alias for lint
