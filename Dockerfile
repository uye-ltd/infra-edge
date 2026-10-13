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

# Directories:
#   generated/   envsubst output (see above)
#   local-sites/ mount point for local-only sites (docker-compose.local.yml); empty in production
#   certbot      webroot for ACME challenges
#   ssl/         TLS certificates (mounted at runtime)
# plus non-root ownership of the log directory.
RUN mkdir -p /etc/nginx/generated /etc/nginx/local-sites /var/www/certbot /etc/nginx/ssl \
    && chown -R nginx:nginx /var/log/nginx

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD ["curl", "-fsS", "-o", "/dev/null", "http://localhost/healthz"]

EXPOSE 80 443
