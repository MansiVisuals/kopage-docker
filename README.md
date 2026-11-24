# Kopage Docker

Docker image for running [Kopage CMS](https://www.kopage.com) with PHP 8.5, Apache, and ionCube Loader.
Published on Docker Hub as [`crypt010/kopage`](https://hub.docker.com/r/crypt010/kopage).

Community-maintained and not affiliated with Kopage.

## Features

- **PHP 8.5** with Apache (security support until 2029-12-31). Kopage supports PHP 7.1-7.4 and 8.1-8.5 with ionCube Loaders.
- **ionCube Loader** included (required by Kopage)
- **Extensions Kopage needs**: GD (JPEG, PNG, FreeType), Zip, cURL, PDO/SQLite. No MySQL required.
- **Multi-architecture**: `linux/amd64` and `linux/arm64`
- **Production-ready** PHP configuration (4GB memory limit, optimized for video uploads)
- **Auto-installation**: on first start, the Kopage installer is extracted when `/var/www/html` has no Kopage files. An existing site is left untouched.
- **Performance optimizations**: OPcache, Brotli/gzip compression, browser caching
- **Proxy-ready**: real client IPs from the `X-Forwarded-For` header sent by a reverse proxy on a private network

## Quick Start

```bash
docker run -d \
  -p 8080:80 \
  -e PHP_SESSION_COOKIE_SECURE=0 \
  -v kopage-data:/var/www/html \
  crypt010/kopage:latest
```

Visit `http://localhost:8080/install_izkopage-setup.php` to complete the Kopage installation.

`PHP_SESSION_COOKIE_SECURE=0` is needed while the site is served over plain HTTP.
Leave it out once the site is behind HTTPS.

## Configuration

### Environment Variables

- `SERVER_NAME` - Optional Apache ServerName, e.g. `mysite.com`
- `PHP_SESSION_COOKIE_SECURE` - Default is `1`: session cookies are only sent over HTTPS. Set to `0` when the site is served over plain HTTP (local testing, or a LAN address without a reverse proxy), otherwise logging in will not work.

### Volume

Mount `/var/www/html` to persist your Kopage installation:

```bash
docker run -d \
  -p 8080:80 \
  -e SERVER_NAME="mysite.com" \
  -v /path/to/kopage:/var/www/html \
  crypt010/kopage:latest
```

### Reverse proxy

Run the container on plain HTTP and let a reverse proxy such as Caddy or Traefik
handle HTTPS. Apache takes the visitor's IP from `X-Forwarded-For` when the request
comes from a private network (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`,
`169.254.0.0/16`, `127.0.0.0/8`), so Kopage and the access logs see real visitor IPs.
Keep `PHP_SESSION_COOKIE_SECURE` at its default of `1` behind HTTPS.

## Building

A GitHub Action rebuilds and pushes `crypt010/kopage:latest` every Monday at
03:00 UTC (and on pushes to `main` that touch the Dockerfile, entrypoint or
workflow), pulling the freshest base image and Debian security updates. Each build
is smoke-tested (extensions, ionCube, Apache config, HTTP + Brotli check) before
it is pushed. It requires the `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`
repository secrets.

For local builds, use the interactive build script:

```bash
./build-and-push.sh
```

Or build a local image for testing (current architecture only, not pushed):

```bash
docker buildx build \
  --pull \
  --build-arg APT_CACHE_BUSTER="$(date -u +%Y%m%d%H%M%S)" \
  --load \
  -t kopage:local \
  .
```

> **Note:** Only the `latest` tag is published, and it always contains the current
> Kopage release plus the latest Debian security updates. There is no version to
> choose or pass in — the installer is fetched from a static URL that always serves
> the newest release, so the image carries no version label and nothing here should
> hardcode one.
>
> [`IMAGE_MANIFEST.md`](IMAGE_MANIFEST.md) records what the currently published image
> actually contains — image and base image digests, PHP and ionCube versions, the
> Kopage installer version and checksum, and the full Debian package list. CI
> regenerates and commits it on every build, so the weekly package updates are
> visible in this repo's history.

## PHP Configuration

- Memory limit: 4GB
- Max upload size: 2GB
- Max execution time: 600 seconds
- OPcache enabled with production settings

## License

This Docker image is provided as-is. Kopage CMS has its own licensing terms.
