#!/usr/bin/env sh

set -e

mkdir -p ~/.docker

echo "$CI_REGISTRY_PASSWORD" | docker login -u "${CI_REGISTRY_USER}" --password-stdin "${CI_REGISTRY}"

if [ -n "${DOCKERHUB_USERNAME}" ]  && [ -n "${DOCKERHUB_PASSWORD}" ]; then
  echo "${DOCKERHUB_PASSWORD}" | docker login -u "${DOCKERHUB_USERNAME}" --password-stdin
fi
