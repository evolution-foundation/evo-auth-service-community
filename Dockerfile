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

# Create non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails /rails

# Switch to non-root user
USER rails:rails

# Expose port
EXPOSE 3001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3001/health || exit 1
