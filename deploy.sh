#!/bin/bash

# SCOUT Build Script
# - Builds Flutter web app for manual deployment
# - Files will be ready in build/web for upload via FileZilla

SKIP_BUILD=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --skip-build) SKIP_BUILD=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# -----------------------------
# Build step
# -----------------------------
PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="${PROJECT_ROOT}/build/web"

# Define colors
CYAN='\033[0;36m'
GRAY='\033[1;30m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${CYAN}🚀 SCOUT Build Script${NC}"
echo -e "${GRAY}Project Root: ${PROJECT_ROOT}${NC}"
echo -e "${GRAY}Build Directory: ${BUILD_DIR}${NC}\n"

if [ "$SKIP_BUILD" = false ]; then
    echo -e "${YELLOW}📦 Building Flutter web app...${NC}"
    pushd "${PROJECT_ROOT}" > /dev/null
    
    if flutter build web --release; then
        echo -e "${GREEN}✅ Build completed successfully${NC}"
    else
        echo -e "${RED}Build failed!${NC}" >&2
        popd > /dev/null
        exit 1
    fi
    
    popd > /dev/null
else
    echo -e "${YELLOW}⏭️  Skipping build step${NC}"
fi

if [ ! -d "${BUILD_DIR}" ]; then
    echo -e "${RED}Build directory not found: ${BUILD_DIR}${NC}" >&2
    exit 1
fi

echo -e "\n${GREEN}📁 Build files are ready in: ${BUILD_DIR}${NC}"
echo -e "${CYAN}📤 Upload these files manually using FileZilla to your web server${NC}"
echo -e "\n${CYAN}🎉 Build completed! Ready for manual deployment.${NC}"
