# Base image: PHP 8.2 + Apache (official, multi-architecture)
# Pin to Debian bookworm for newer security patches
FROM php:8.2-apache-bookworm

# Build argument for Kopage version
ARG KOPAGE_VERSION=4.7.0

# Cache-buster for APT layers (useful when building with buildx cache enabled)
ARG APT_CACHE_BUSTER=0

# Apply all available security updates immediately after base image
# This fixes HIGH and MEDIUM CVEs with available patches (curl, libxml2)
RUN set -eux; \
    echo "APT_CACHE_BUSTER=$APT_CACHE_BUSTER" > /dev/null; \
    apt-get update; \
    apt-get upgrade -y --no-install-recommends; \
    rm -rf /var/lib/apt/lists/*

# Metadata labels - version matches Kopage version
LABEL maintainer="Kopage" \
      org.opencontainers.image.title="Kopage Docker" \
      org.opencontainers.image.description="PHP 8.2 with Apache and ionCube for Kopage CMS" \
      org.opencontainers.image.version="${KOPAGE_VERSION}" \
      kopage.version="${KOPAGE_VERSION}"

# Install PHP extensions with proper dependency management
RUN set -eux; \
    echo "APT_CACHE_BUSTER=$APT_CACHE_BUSTER" > /dev/null; \
    savedAptMark="$(apt-mark showmanual)"; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libpng-dev \
        libjpeg-dev \
        libfreetype6-dev \
        libzip-dev \
        unzip \
        curl \
        sqlite3 \
        libsqlite3-dev \
        libcurl4-openssl-dev \
    ; \
    # Ensure newly installed packages also pick up latest security updates (e.g. libpng via -security)
    apt-get upgrade -y --no-install-recommends; \
    \
    docker-php-ext-configure gd --with-jpeg --with-freetype; \
    docker-php-ext-install -j "$(nproc)" \
        gd \
        zip \
        pdo \
        pdo_sqlite \
        curl \
    ; \
    docker-php-ext-enable pdo_sqlite zip curl; \
    \
    # Validate extensions loaded correctly
    extDir="$(php -r 'echo ini_get("extension_dir");')"; \
    [ -d "$extDir" ]; \
    \
    # Find runtime dependencies and mark them as manual to keep them
    runDeps="$( \
        ldd "$extDir"/*.so \
            | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); print so }' \
            | sort -u \
            | xargs -r dpkg-query --search \
            | cut -d: -f1 \
            | sort -u \
    )"; \
    \
    # Clean up build dependencies but keep runtime libraries
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    apt-mark manual unzip curl sqlite3; \
    apt-mark manual $runDeps; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    \
    # Remove linux-libc-dev to eliminate kernel CVE warnings (headers only, not needed at runtime)
    apt-get remove -y linux-libc-dev || true; \
    apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/*; \
    \
    # Final validation
    ! { ldd "$extDir"/*.so | grep 'not found'; }; \
    err="$(php --version 3>&1 1>&2 2>&3)"; \
    [ -z "$err" ]

# Install ionCube Loader for PHP 8.2 (multi-architecture support)
# Downloaded over HTTPS from official ionCube CDN
RUN set -eux; \
    ARCH=$(uname -m); \
    echo "Detected architecture: $ARCH"; \
    if [ "$ARCH" = "x86_64" ]; then \
        IONCUBE_ARCH="x86-64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        IONCUBE_ARCH="aarch64"; \
    else \
        echo "Unsupported architecture: $ARCH"; \
        echo "Supported: x86_64, aarch64"; \
        exit 1; \
    fi; \
    echo "Using ionCube architecture: $IONCUBE_ARCH"; \
    curl -fsSL https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_${IONCUBE_ARCH}.tar.gz -o /tmp/ioncube.tar.gz; \
    tar -xzf /tmp/ioncube.tar.gz -C /tmp/; \
    PHP_EXT_DIR=$(php-config --extension-dir); \
    echo "Installing ionCube to: $PHP_EXT_DIR"; \
    cp /tmp/ioncube/ioncube_loader_lin_8.2.so $PHP_EXT_DIR/; \
    echo "zend_extension=$PHP_EXT_DIR/ioncube_loader_lin_8.2.so" > /usr/local/etc/php/conf.d/00-ioncube.ini; \
    rm -rf /tmp/ioncube*; \
    php -v | grep -i ioncube; \
    echo "ionCube installation complete"

# Set production-ready PHP configuration with security hardening
RUN { \
    echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
    echo 'display_errors = Off'; \
    echo 'display_startup_errors = Off'; \
    echo 'log_errors = On'; \
    echo 'error_log = /dev/stderr'; \
    echo 'log_errors_max_len = 1024'; \
    echo 'ignore_repeated_errors = On'; \
    echo 'ignore_repeated_source = Off'; \
    echo 'html_errors = Off'; \
    echo ''; \
    echo '; Security hardening'; \
    echo 'expose_php = Off'; \
    echo 'allow_url_fopen = On'; \
    echo 'allow_url_include = Off'; \
    echo 'disable_functions = exec,passthru,shell_exec,system,proc_open,popen,pcntl_exec,pcntl_fork,pcntl_signal,pcntl_waitpid,pcntl_wexitstatus,pcntl_wifexited,pcntl_wifsignaled,pcntl_wifstopped,pcntl_wstopsig,pcntl_wtermsig'; \
    echo 'session.cookie_httponly = 1'; \
    echo 'session.cookie_samesite = Strict'; \
    echo 'session.use_strict_mode = 1'; \
    echo '; session.cookie_secure is configured at runtime via entrypoint (see PHP_SESSION_COOKIE_SECURE env var)'; \
} > /usr/local/etc/php/conf.d/error-logging.ini

# Performance optimization: 4GB RAM, video support, fast execution
RUN { \
    echo 'memory_limit = 4096M'; \
    echo 'max_execution_time = 600'; \
    echo 'max_input_time = 600'; \
    echo 'post_max_size = 2048M'; \
    echo 'upload_max_filesize = 2048M'; \
    echo 'max_input_vars = 10000'; \
    echo 'max_file_uploads = 100'; \
    echo 'default_socket_timeout = 600'; \
} > /usr/local/etc/php/conf.d/performance.ini

# Enable and configure OPcache for production
RUN set -eux; \
    docker-php-ext-enable opcache; \
    { \
        echo 'opcache.enable=1'; \
        echo 'opcache.memory_consumption=256'; \
        echo 'opcache.interned_strings_buffer=16'; \
        echo 'opcache.max_accelerated_files=10000'; \
        echo 'opcache.revalidate_freq=2'; \
        echo 'opcache.fast_shutdown=1'; \
        echo 'opcache.validate_timestamps=1'; \
        echo 'opcache.enable_cli=0'; \
        echo 'opcache.save_comments=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini

# Enable Apache modules for reverse proxy/CDN usage and security
RUN set -eux; \
    a2enmod rewrite headers; \
    \
    # Configure RemoteIP for proper client IP detection behind proxies
    a2enmod remoteip; \
    { \
        echo 'RemoteIPHeader X-Forwarded-For'; \
        echo 'RemoteIPHeader X-Real-IP'; \
        echo 'RemoteIPInternalProxy 10.0.0.0/8'; \
        echo 'RemoteIPInternalProxy 172.16.0.0/12'; \
        echo 'RemoteIPInternalProxy 192.168.0.0/16'; \
        echo 'RemoteIPInternalProxy 169.254.0.0/16'; \
        echo 'RemoteIPInternalProxy 127.0.0.0/8'; \
    } > /etc/apache2/conf-available/remoteip.conf; \
    a2enconf remoteip; \
    \
    # Fix LogFormat to show real client IPs instead of proxy IPs
    find /etc/apache2 -type f -name '*.conf' -exec sed -ri 's/([[:space:]]*LogFormat[[:space:]]+"[^"]*)%h([^"]*")/\1%a\2/g' '{}' +; \
    \
    # Security hardening: Hide Apache version and OS info
    { \
        echo 'ServerTokens Prod'; \
        echo 'ServerSignature Off'; \
        echo 'TraceEnable Off'; \
    } >> /etc/apache2/conf-available/security.conf

# Enable compression and caching for faster page loads
RUN set -eux; \
    a2enmod deflate expires; \
    { \
        echo '<IfModule mod_deflate.c>'; \
        echo '  AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript'; \
        echo '  AddOutputFilterByType DEFLATE application/javascript application/json application/xml'; \
        echo '  AddOutputFilterByType DEFLATE image/svg+xml'; \
        echo '  DeflateCompressionLevel 6'; \
        echo '</IfModule>'; \
        echo ''; \
        echo '<IfModule mod_expires.c>'; \
        echo '  ExpiresActive On'; \
        echo '  ExpiresByType image/jpg "access plus 1 year"'; \
        echo '  ExpiresByType image/jpeg "access plus 1 year"'; \
        echo '  ExpiresByType image/gif "access plus 1 year"'; \
        echo '  ExpiresByType image/png "access plus 1 year"'; \
        echo '  ExpiresByType image/webp "access plus 1 year"'; \
        echo '  ExpiresByType image/svg+xml "access plus 1 year"'; \
        echo '  ExpiresByType video/mp4 "access plus 1 year"'; \
        echo '  ExpiresByType video/webm "access plus 1 year"'; \
        echo '  ExpiresByType text/css "access plus 1 month"'; \
        echo '  ExpiresByType application/javascript "access plus 1 month"'; \
        echo '  ExpiresByType application/pdf "access plus 1 month"'; \
        echo '  ExpiresByType text/html "access plus 0 seconds"'; \
        echo '</IfModule>'; \
        echo ''; \
        echo '# Allow large video uploads'; \
        echo 'LimitRequestBody 2147483648'; \
        echo ''; \
        echo '# Better connection handling'; \
        echo 'KeepAlive On'; \
        echo 'MaxKeepAliveRequests 100'; \
        echo 'KeepAliveTimeout 5'; \
    } > /etc/apache2/conf-available/performance.conf; \
    a2enconf performance

# Pre-download Kopage installer into the image
# Then remove all build-time packages no longer needed at runtime
# This eliminates 65+ CVEs from binutils, gcc, m4, patch, re2c etc.
RUN set -eux; \
    curl -fsSL "https://www.kopage.com/installer.zip" -o /usr/local/kopage-installer.zip; \
    echo "Kopage installer pre-downloaded to /usr/local/kopage-installer.zip"; \
    apt-get update; \
    apt-get purge -y --auto-remove \
        autoconf \
        binutils \
        binutils-common \
        cpp \
        cpp-12 \
        curl \
        dpkg-dev \
        file \
        gcc \
        gcc-12 \
        libasan8 \
        libbinutils \
        libcc1-0 \
        libctf-nobfd0 \
        libctf0 \
        libdpkg-perl \
        libgcc-12-dev \
        libgprofng0 \
        libhwasan0 \
        libisl23 \
        libitm1 \
        liblsan0 \
        libmagic-mgc \
        libmagic1 \
        libmpc3 \
        libmpfr6 \
        libtsan2 \
        libubsan1 \
        m4 \
        make \
        patch \
        re2c \
    ; \
    rm -rf /var/lib/apt/lists/*

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Environment variables for configuration
ENV SERVER_NAME="" \
    PHP_SESSION_COOKIE_SECURE="1"

# Expose port 80
EXPOSE 80

# Use custom entrypoint that installs Kopage if volume empty
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
