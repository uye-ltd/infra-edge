FROM nginx:1.27-alpine

# Install curl for healthcheck
RUN apk add --no-cache curl

# Copy main nginx config
COPY nginx/nginx.conf /etc/nginx/nginx.conf

# Copy static modular configs
COPY nginx/conf.d/ /etc/nginx/conf.d/

# Copy reusable server/location snippets (included by templates)
COPY nginx/snippets/ /etc/nginx/snippets/

# Copy envsubst templates (processed at container startup by official entrypoint)
COPY nginx/templates/ /etc/nginx/templates/

# Render templates outside conf.d/ so the root filesystem can stay read-only
# (docker-compose.yml mounts a tmpfs here) and conf.d/ can be bind-mounted :ro.
ENV NGINX_ENVSUBST_OUTPUT_DIR=/etc/nginx/generated
RUN mkdir -p /etc/nginx/generated

# Mount point for local-only sites (docker-compose.local.yml); empty in production
RUN mkdir -p /etc/nginx/local-sites

# Certbot webroot challenge directory
RUN mkdir -p /var/www/certbot

# TLS certificate directory (mounted at runtime)
RUN mkdir -p /etc/nginx/ssl

# Non-root log directory ownership
RUN chown -R nginx:nginx /var/log/nginx

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -fsS http://localhost/healthz > /dev/null || exit 1

EXPOSE 80 443
