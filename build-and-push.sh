#!/bin/bash
# Interactive Docker build and push script for Kopage
set -e

IMAGE_NAME="crypt010/kopage"

echo "=========================================="
echo "  Kopage Docker Build & Push Tool"
echo "=========================================="
echo ""

# Function to clean up Docker resources
cleanup_docker() {
    echo "Cleaning up Docker resources..."

    # Remove old Kopage images (keep latest)
    echo "→ Removing old ${IMAGE_NAME} images..."
    docker images "${IMAGE_NAME}" --format "{{.ID}} {{.Tag}}" | grep -v "latest" | awk '{print $1}' | xargs -r docker rmi -f 2>/dev/null || true

    # Clean build cache
    echo "→ Pruning build cache..."
    docker buildx prune -f

    # Clean dangling images
    echo "→ Removing dangling images..."
    docker image prune -f

    # Clean stopped containers
    echo "→ Removing stopped containers..."
    docker container prune -f

    echo "✓ Cleanup complete!"
    echo ""
}

# Ask if user wants to clean up first
read -p "Clean up old images and build cache? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cleanup_docker
fi

# Get version number from user
echo "Enter Kopage version number (e.g., 4.7.0):"
read -r VERSION

if [ -z "$VERSION" ]; then
    echo "Error: Version number is required!"
    exit 1
fi

echo ""
echo "Configuration:"
echo "  Version: ${VERSION}"
echo "  Image: ${IMAGE_NAME}"
echo "  Tags: ${VERSION}, latest"
echo "  Platforms: linux/amd64, linux/arm64"
echo ""

# Confirm before building
read -p "Proceed with build? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Build cancelled."
    exit 0
fi

echo ""
echo "Building multi-architecture Docker image..."

# Create buildx builder if it doesn't exist
docker buildx create --name kopage-builder --use 2>/dev/null || docker buildx use kopage-builder

# Build and push multi-architecture image
docker buildx build \
    --build-arg KOPAGE_VERSION="${VERSION}" \
    --platform linux/amd64,linux/arm64 \
    -t "${IMAGE_NAME}:${VERSION}" \
    -t "${IMAGE_NAME}:latest" \
    --push \
    .

echo ""
echo "=========================================="
echo "  ✓ Successfully built and pushed!"
echo "=========================================="
echo "  ${IMAGE_NAME}:${VERSION}"
echo "  ${IMAGE_NAME}:latest"
echo ""
echo "Platforms: linux/amd64, linux/arm64"
echo ""

# Ask if user wants to clean up after build
read -p "Clean up build cache after successful build? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker buildx prune -f
    echo "✓ Build cache cleaned!"
fi

echo ""
echo "Done!"
