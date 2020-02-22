#!/usr/bin/env sh

set -e

CI_BUILDX_ARCHS="linux/amd64"

if [ "${ENABLE_ARM64:-false}" = "true" ]; then
  CI_BUILDX_ARCHS="${CI_BUILDX_ARCHS},linux/arm64"
fi

if [ "${ENABLE_ARMv7:-false}" = "true" ]; then
  CI_BUILDX_ARCHS="${CI_BUILDX_ARCHS},linux/arm/v7"
fi

if [ "${ENABLE_ARMv6:-false}" = "true" ]; then
  CI_BUILDX_ARCHS="${CI_BUILDX_ARCHS},linux/arm/v6"
fi
echo "${CI_BUILDX_ARCHS}" > "/tmp/${CI_PROJECT_NAME}-${CI_COMMIT_SHA}-platforms"

BUILDX_NAME="buildx-${CI_COMMIT_SHA}"

docker context create "${BUILDX_NAME}"

update-binfmts --enable # Important: Ensures execution of other binary formats is enabled in the kernel

docker buildx create --driver docker-container \
        --name "${BUILDX_NAME}" \
        --use "${BUILDX_NAME}"
docker buildx inspect --bootstrap
docker buildx ls
