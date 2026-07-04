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

# Set development environment
ENV RAILS_ENV=development \
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

# Normaliza CRLF->LF no healthcheck: um checkout Windows deixa \r no shebang
# (#!/bin/sh\r), fazendo o kernel procurar "/bin/sh\r" -> "not found" (exit 127)
# no HEALTHCHECK. O container fica unhealthy e o gateway responde 502.
RUN sed -i 's/\r$//' /usr/local/bin/evo-auth-healthcheck

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
