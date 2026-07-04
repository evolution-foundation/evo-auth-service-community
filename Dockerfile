# =============================================================================
# EVO-AUTH-SERVICE - Development Dockerfile
# =============================================================================

# Use Ruby 3.4.4 as specified in the project
ARG RUBY_VERSION=3.4.4
FROM ruby:$RUBY_VERSION-slim

# Set working directory
WORKDIR /rails

# Install system dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    curl \
    git \
    libpq-dev \
    libyaml-dev \
    pkg-config \
    postgresql-client \
    libjemalloc2 \
    libvips \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# RAILS_ENV configuravel no build: default 'development' (mantem o compose local),
# passe --build-arg RAILS_ENV=production para as imagens de deploy (CapRover).
ARG RAILS_ENV=development
ENV RAILS_ENV=${RAILS_ENV} \
    BUNDLE_PATH="/usr/local/bundle"

# Copy Gemfile and install dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy application code (excluding problematic files)
COPY --chown=1000:1000 . .

# Remove production-specific files that might cause issues
RUN rm -f bin/thrust bin/docker-entrypoint

# Install role-aware healthcheck before switching to the non-root user.
COPY --chown=1000:1000 bin/healthcheck /usr/local/bin/evo-auth-healthcheck
RUN chmod +x /usr/local/bin/evo-auth-healthcheck

# EVO-1999: entrypoint que roda migrations no boot da imagem, para que qualquer
# orquestrador (incl. CapRover, que ignora o command do compose) suba o schema
# atualizado. Instalado antes do USER para poder dar permissão como root.
COPY --chown=1000:1000 docker-entrypoint.sh /usr/local/bin/evo-auth-entrypoint
RUN chmod +x /usr/local/bin/evo-auth-entrypoint

# Normaliza CRLF->LF no entrypoint: um checkout Windows deixa \r no shebang, o
# que faz o kernel procurar "/bin/bash\r" -> "not found" (exit 127) ao subir.
RUN sed -i 's/\r$//' /usr/local/bin/evo-auth-entrypoint

# Create non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails /rails

# Switch to non-root user
USER rails:rails

# Expose port
EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["/usr/local/bin/evo-auth-healthcheck"]

# EVO-1999: a imagem migra sozinha no boot (gate RUN_MIGRATIONS, default true) e
# sobe o server. Orquestradores que passam um command próprio (ex.: sidekiq) ainda
# passam pelo entrypoint — defina RUN_MIGRATIONS=false nesses para não migrar.
ENTRYPOINT ["/usr/local/bin/evo-auth-entrypoint"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3001"]
