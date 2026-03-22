# Kopage Docker

Docker image for running [Kopage CMS](https://www.kopage.com) with PHP 8.2, Apache, and ionCube Loader.

## Features

- **PHP 8.2** with Apache
- **ionCube Loader** support
- **Multi-architecture**: `linux/amd64` and `linux/arm64`
- **Production-ready** PHP configuration (4GB memory limit, optimized for video uploads)
- **Auto-installation**: Kopage installer automatically extracted on first run
- **Performance optimizations**: OPcache, compression, browser caching
- **Proxy-ready**: RemoteIP configuration for proper client IP detection behind reverse proxies

## Quick Start

```bash
docker run -d \
  -p 8080:80 \
  -v kopage-data:/var/www/html \
  crypt010/kopage:latest
```

Visit `http://localhost:8080/install_izkopage-setup.php` to complete the Kopage installation.

## Configuration

### Environment Variables

- `SERVER_NAME` - Optional Apache ServerName configuration
- `PHP_SESSION_COOKIE_SECURE` - Controls secure cookie setting for sessions. Default is `1` (HTTPS required). Set to `0` for localhost HTTP testing.

### Volume

Mount `/var/www/html` to persist your Kopage installation:

```bash
docker run -d \
  -p 8080:80 \
  -e SERVER_NAME="mysite.com" \
  -v /path/to/kopage:/var/www/html \
  crypt010/kopage:latest
```

## Building

Use the interactive build script:

```bash
./build-and-push.sh
```

Or build manually:

```bash
docker buildx build \
  --pull \
  --build-arg KOPAGE_VERSION=4.7.0 \
  --build-arg APT_CACHE_BUSTER="$(date -u +%Y%m%d%H%M%S)" \
  --platform linux/amd64,linux/arm64 \
  -t crypt010/kopage:latest \
  .
```

> **Note:** Only the `latest` tag is published. The Kopage version is embedded in the image labels.

## PHP Configuration

- Memory limit: 4GB
- Max upload size: 2GB
- Max execution time: 600 seconds
- OPcache enabled with production settings

## License

This Docker image is provided as-is. Kopage CMS has its own licensing terms.
