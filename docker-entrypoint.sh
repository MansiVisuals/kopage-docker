#!/bin/bash
set -Eeuo pipefail

WEBROOT=/var/www/html
INSTALLER_ZIP="/usr/local/kopage-installer.zip"

# Configure Apache ServerName if provided via environment variable
if [ -n "${SERVER_NAME:-}" ]; then
    echo "ServerName ${SERVER_NAME}" > /etc/apache2/conf-available/servername.conf
    a2enconf servername > /dev/null 2>&1
    echo "Apache ServerName set to: ${SERVER_NAME}"
fi

if [[ "$1" == apache2* ]] || [ "$1" = 'apache2-foreground' ]; then
    uid="$(id -u)"
    gid="$(id -g)"

    if [ "$uid" = '0' ]; then
        # Running as root - use www-data
        user="${APACHE_RUN_USER:-www-data}"
        group="${APACHE_RUN_GROUP:-www-data}"
        # strip off any '#' symbol ('#1000' is valid syntax for Apache)
        pound='#'
        user="${user#$pound}"
        group="${group#$pound}"
    else
        # Running as non-root - use current UID/GID
        user="$uid"
        group="$gid"
    fi
    
    # Check what we have in the webroot and provide appropriate messages
    if [ ! -f "$WEBROOT/index.php" ] && [ ! -f "$WEBROOT/free_install.php" ]; then
        # if the directory exists and Kopage doesn't appear to be installed AND the permissions of it are root:root, let's chown it (likely a Docker-created directory)
        if [ "$uid" = '0' ] && [ "$(stat -c '%u:%g' "$WEBROOT")" = '0:0' ]; then
            chown "$user:$group" "$WEBROOT"
        fi
        
        echo "No Kopage installation detected in $WEBROOT"
        if [ -n "$(find "$WEBROOT" -mindepth 1 -maxdepth 1 -not -name lost+found)" ]; then
            echo >&2 "WARNING: $WEBROOT is not empty! (installing Kopage anyhow)"
        fi

        echo "Installing Kopage from pre-downloaded installer..."

        # Extract to staging directory for tar processing
        mkdir -p /tmp/kopage-staging
        unzip -o -q "$INSTALLER_ZIP" -d /tmp/kopage-staging
        
        # Use tar to copy with proper ownership
        sourceTarArgs=(
            --create --file - --directory /tmp/kopage-staging
            --owner "$user" --group "$group"
        )
        targetTarArgs=(
            --extract --file - --directory "$WEBROOT"
        )
        if [ "$uid" != '0' ]; then
            # avoid "tar: .: Cannot utime: Operation not permitted" and "tar: .: Cannot change mode to rwxr-xr-x: Operation not permitted"
            targetTarArgs+=( --no-overwrite-dir )
        fi
        
        tar "${sourceTarArgs[@]}" . | tar "${targetTarArgs[@]}"

        # Clean up
        rm -rf /tmp/kopage-staging
        chmod -R 755 "$WEBROOT"
        echo "Kopage installer extracted successfully!"
        echo "Visit http://localhost:<YOUR_PORT>/free_install.php to complete installation"
        
    elif [ -f "$WEBROOT/free_install.php" ] && [ ! -f "$WEBROOT/index.php" ]; then
        echo "Kopage installer detected - installation not yet completed"
        echo "Visit http://localhost:<YOUR_PORT>/free_install.php to complete installation"
        
        # attempt to ensure that existing files are owned by the run user (could be on a filesystem that doesn't allow chown like some NFS setups)
        if [ "$uid" = '0' ]; then
            chown -R "$user:$group" "$WEBROOT" || echo >&2 "WARNING: Could not change ownership (possibly NFS mount)"
        fi
        
    else
        # We have index.php or other PHP files - assume Kopage is installed
        php_files=$(find "$WEBROOT" -maxdepth 1 -name "*.php" | wc -l)
        echo "Kopage installation detected ($php_files PHP files found)"
        echo "Visit http://localhost:<YOUR_PORT>/ to access your Kopage website"
        
        # attempt to ensure that existing files are owned by the run user
        if [ "$uid" = '0' ]; then
            chown -R "$user:$group" "$WEBROOT" || echo >&2 "WARNING: Could not change ownership (possibly NFS mount)"
        fi
    fi
fi

# Start Apache
exec "$@"
