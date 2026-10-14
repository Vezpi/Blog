FROM nginx:stable

ARG HUGO_VERSION
ENV HUGO_VERSION=${HUGO_VERSION}
ENV HUGO_DEST=/usr/share/nginx/html
ENV DART_SASS_VERSION=1.105.1
ENV PATH="/opt/dart-sass:${PATH}"

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download Hugo
RUN curl -sSL https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz \
    | tar -xz -C /usr/local/bin hugo

# Download Dart Sass
RUN curl -fsSL https://github.com/sass/dart-sass/releases/download/${DART_SASS_VERSION}/dart-sass-${DART_SASS_VERSION}-linux-x64.tar.gz \
    | tar -xz -C /opt

# Add entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf
# Nginx serves on port 80
EXPOSE 80

# Set default entrypoint
ENTRYPOINT ["/entrypoint.sh"]