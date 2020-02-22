#!/usr/bin/env sh

set -e

docker context rm "buildx-${CI_COMMIT_SHA}" || true
