FROM nginx:alpine

ARG HUGO_VERSION
ENV HUGO_VERSION=${HUGO_VERSION}
ENV HUGO_DEST=/usr/share/nginx/html

# Install git and curl
RUN apk add --no-cache git curl

# Download Hugo
RUN curl -sSL https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz \
    | tar -xz -C /usr/local/bin hugo

# Add entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf
# Nginx serves on port 80
EXPOSE 80

# Set default entrypoint
ENTRYPOINT ["/entrypoint.sh"]