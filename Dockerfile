# Base image: PHP 8.2 + Apache (official, multi-architecture)
# Pin to Debian bookworm for newer security patches
FROM php:8.2-apache-bookworm

# Build argument for Kopage version
ARG KOPAGE_VERSION=4.7.10

# Cache-buster for APT layers (useful when building with buildx cache enabled)
ARG APT_CACHE_BUSTER=0

# Install PHP extensions with proper dependency management.
# Note: curl, pdo, pdo_sqlite and sqlite3 extensions are already bundled with
# the official php image - only gd and zip need to be compiled.
# Security updates (apt-get upgrade) are applied here and again in the final
# APT layer, so a separate upgrade-only layer is not needed.
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
        sqlite3 \
    ; \
    # Ensure newly installed packages also pick up latest security updates (e.g. libpng via -security)
    apt-get upgrade -y --no-install-recommends; \
    \
    docker-php-ext-configure gd --with-jpeg --with-freetype; \
    docker-php-ext-install -j "$(nproc)" \
        gd \
        zip \
    ; \
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
    apt-mark manual unzip sqlite3; \
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

# PHP configuration: error logging + security hardening, performance limits,
# and production OPcache settings
RUN set -eux; \
    docker-php-ext-enable opcache; \
    { \
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
    } > /usr/local/etc/php/conf.d/error-logging.ini; \
    \
    # Performance: 4GB RAM, video support, fast execution
    { \
    echo 'memory_limit = 4096M'; \
    echo 'max_execution_time = 600'; \
    echo 'max_input_time = 600'; \
    echo 'post_max_size = 2048M'; \
    echo 'upload_max_filesize = 2048M'; \
    echo 'max_input_vars = 10000'; \
    echo 'max_file_uploads = 100'; \
    echo 'default_socket_timeout = 600'; \
    echo ''; \
    echo '; Cache resolved file paths to avoid repeated filesystem stat calls'; \
    echo 'realpath_cache_size = 4096K'; \
    echo 'realpath_cache_ttl = 600'; \
    } > /usr/local/etc/php/conf.d/performance.ini; \
    \
    # OPcache for production
    { \
        echo 'opcache.enable=1'; \
        echo 'opcache.memory_consumption=256'; \
        echo 'opcache.interned_strings_buffer=32'; \
        echo 'opcache.max_accelerated_files=20000'; \
        echo '; Only re-stat changed files once per minute (code rarely changes in production)'; \
        echo 'opcache.revalidate_freq=60'; \
        echo 'opcache.validate_timestamps=1'; \
        echo 'opcache.enable_cli=0'; \
        echo 'opcache.save_comments=1'; \
        echo 'opcache.max_wasted_percentage=10'; \
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
    a2enmod deflate expires brotli; \
    { \
        echo '# Brotli preferred for clients that support it (better ratio than gzip)'; \
        echo '<IfModule mod_brotli.c>'; \
        echo '  AddOutputFilterByType BROTLI_COMPRESS text/html text/plain text/xml text/css text/javascript'; \
        echo '  AddOutputFilterByType BROTLI_COMPRESS application/javascript application/json application/xml application/rss+xml application/xhtml+xml'; \
        echo '  AddOutputFilterByType BROTLI_COMPRESS image/svg+xml font/ttf application/vnd.ms-fontobject'; \
        echo '  BrotliCompressionQuality 5'; \
        echo '</IfModule>'; \
        echo ''; \
        echo '<IfModule mod_deflate.c>'; \
        echo '  AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript'; \
        echo '  AddOutputFilterByType DEFLATE application/javascript application/json application/xml application/rss+xml application/xhtml+xml'; \
        echo '  AddOutputFilterByType DEFLATE image/svg+xml font/ttf application/vnd.ms-fontobject'; \
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
        echo '  ExpiresByType image/avif "access plus 1 year"'; \
        echo '  ExpiresByType image/svg+xml "access plus 1 year"'; \
        echo '  ExpiresByType image/x-icon "access plus 1 year"'; \
        echo '  ExpiresByType video/mp4 "access plus 1 year"'; \
        echo '  ExpiresByType video/webm "access plus 1 year"'; \
        echo '  ExpiresByType font/woff2 "access plus 1 year"'; \
        echo '  ExpiresByType font/woff "access plus 1 year"'; \
        echo '  ExpiresByType font/ttf "access plus 1 year"'; \
        echo '  ExpiresByType application/vnd.ms-fontobject "access plus 1 year"'; \
        echo '  ExpiresByType text/css "access plus 1 month"'; \
        echo '  ExpiresByType application/javascript "access plus 1 month"'; \
        echo '  ExpiresByType application/pdf "access plus 1 month"'; \
        echo '  ExpiresByType text/html "access plus 0 seconds"'; \
        echo '</IfModule>'; \
        echo ''; \
        echo '# Media and fonts never change in place; skip revalidation entirely'; \
        echo '<IfModule mod_headers.c>'; \
        echo '  <FilesMatch "\.(?i:jpe?g|png|gif|webp|avif|ico|mp4|webm|woff2?|ttf|eot)$">'; \
        echo '    Header append Cache-Control "immutable"'; \
        echo '  </FilesMatch>'; \
        echo '</IfModule>'; \
        echo ''; \
        echo '# Serve static files via kernel sendfile/mmap'; \
        echo 'EnableSendfile On'; \
        echo 'EnableMMAP On'; \
        echo ''; \
        echo '# Allow large video uploads'; \
        echo 'LimitRequestBody 2147483648'; \
        echo ''; \
        echo '# Better connection handling'; \
        echo 'KeepAlive On'; \
        echo 'MaxKeepAliveRequests 1000'; \
        echo 'KeepAliveTimeout 5'; \
        echo ''; \
        echo '# Batch access-log writes instead of one syscall per request'; \
        echo 'BufferedLogs On'; \
        echo ''; \
        echo '# Recycle PHP workers periodically to keep memory usage flat'; \
        echo '<IfModule mpm_prefork_module>'; \
        echo '  StartServers 4'; \
        echo '  MinSpareServers 4'; \
        echo '  MaxSpareServers 12'; \
        echo '  MaxRequestWorkers 150'; \
        echo '  MaxConnectionsPerChild 2048'; \
        echo '</IfModule>'; \
    } > /etc/apache2/conf-available/performance.conf; \
    a2enconf performance

# Strip Apache down to essentials: every disabled module is memory saved per
# prefork worker and less work per request (mod_status's ExtendedStatus alone
# adds timing syscalls to every request)
RUN set -eux; \
    a2dismod -f status autoindex negotiation auth_basic authn_file authz_user access_compat; \
    a2disconf serve-cgi-bin; \
    # Disable directory listings (also a security win); keep FollowSymLinks so
    # Apache skips per-component symlink ownership checks
    sed -ri 's/Options Indexes FollowSymLinks/Options FollowSymLinks/' /etc/apache2/apache2.conf; \
    # Validate the full config still parses with modules removed
    apache2ctl configtest 2>&1 | grep -q 'Syntax OK'

# Pre-download Kopage installer, then remove build-time packages not needed at runtime
RUN set -eux; \
    curl -fsSL "https://www.kopage.com/installer.zip" -o /usr/local/kopage-installer.zip; \
    for pkg in autoconf binutils binutils-common cpp cpp-12 curl dpkg-dev file \
               g++ g++-12 gcc gcc-12 libc6-dev m4 make patch pkg-config re2c; do \
        apt-get purge -y "$pkg" 2>/dev/null || true; \
    done; \
    apt-get -y autoremove --purge; \
    apt-get update; \
    apt-get upgrade -y --no-install-recommends; \
    rm -rf /var/lib/apt/lists/*

# Copy entrypoint script
COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/

# Environment variables for configuration
ENV SERVER_NAME="" \
    PHP_SESSION_COOKIE_SECURE="1"

# Metadata labels - version matches Kopage version (kept last so version bumps
# don't invalidate the build cache of the layers above)
LABEL maintainer="Kopage" \
      org.opencontainers.image.title="Kopage Docker" \
      org.opencontainers.image.description="PHP 8.2 with Apache and ionCube for Kopage CMS" \
      org.opencontainers.image.version="${KOPAGE_VERSION}" \
      kopage.version="${KOPAGE_VERSION}"

# Expose port 80
EXPOSE 80

# Use custom entrypoint that installs Kopage if volume empty
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
