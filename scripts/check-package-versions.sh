#!/usr/bin/env bash
set -euo pipefail

# Read package versions
get_package_version() {
  local package_dir="$1"
  (cd "$package_dir" && bun pm pkg get version | tr -d '"')
}

get_v0_dependency_version() {
  local package_dir="$1"
  (cd "$package_dir" && bun pm pkg get dependencies.v0 | tr -d '"')
}

SDK_VERSION=$(get_package_version "packages/v0-sdk")
AI_TOOLS_VERSION=$(get_package_version "packages/ai-tools")
REACT_VERSION=$(get_package_version "packages/react")
CREATE_APP_VERSION=$(get_package_version "packages/create-v0-sdk-app")

AI_TOOLS_SDK_VERSION=$(get_v0_dependency_version "packages/ai-tools")
REACT_SDK_VERSION=$(get_v0_dependency_version "packages/react")

# Validate that all package versions match
if [[ "$SDK_VERSION" != "$AI_TOOLS_VERSION" ]] ||
   [[ "$SDK_VERSION" != "$REACT_VERSION" ]] ||
   [[ "$SDK_VERSION" != "$CREATE_APP_VERSION" ]]; then
  echo "::error::v0, @v0-sdk/ai-tools, @v0-sdk/react, and create-v0-sdk-app versions must match (${SDK_VERSION}, ${AI_TOOLS_VERSION}, ${REACT_VERSION}, ${CREATE_APP_VERSION})."
  exit 1
fi

# Validate that internal v0 dependency versions match
if [[ "$SDK_VERSION" != "$AI_TOOLS_SDK_VERSION" ]] ||
   [[ "$SDK_VERSION" != "$REACT_SDK_VERSION" ]]; then
  echo "::error::Published package dependencies on v0 must match ${SDK_VERSION} (@v0-sdk/ai-tools: ${AI_TOOLS_SDK_VERSION}, @v0-sdk/react: ${REACT_SDK_VERSION})."
  exit 1
fi

echo "All package versions are consistent: ${SDK_VERSION}"
