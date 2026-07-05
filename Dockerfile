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

# RAILS_ENV is configurable at build time: defaults to 'development' (keeps the
# local compose working); pass --build-arg RAILS_ENV=production for deploy images.
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

# EVO-1999: entrypoint that runs migrations on image boot, so any orchestrator
# (incl. CapRover, which ignores the compose command) brings up an up-to-date
# schema. Installed before USER so we can set permissions as root.
COPY --chown=1000:1000 docker-entrypoint.sh /usr/local/bin/evo-auth-entrypoint
RUN chmod +x /usr/local/bin/evo-auth-entrypoint

# Normalize CRLF->LF in the entrypoint: a Windows checkout leaves \r in the
# shebang, making the kernel look for "/bin/bash\r" -> "not found" (exit 127) on boot.
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

# EVO-1999: the image migrates on boot (RUN_MIGRATIONS gate, default true) and
# starts the server. Orchestrators that pass their own command (e.g. sidekiq)
# still go through the entrypoint — set RUN_MIGRATIONS=false on those to skip it.
ENTRYPOINT ["/usr/local/bin/evo-auth-entrypoint"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3001"]
