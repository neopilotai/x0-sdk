#!/usr/bin/env bash
set -Eeuo pipefail

# Usage:
#   ./scripts/vercel-deploy.sh check
#   ./scripts/vercel-deploy.sh deploy web preview
#   ./scripts/vercel-deploy.sh deploy web production
#   ./scripts/vercel-deploy.sh deploy preview-proxy preview
#   ./scripts/vercel-deploy.sh deploy preview-proxy production
#
# Requirements:
#   - Run from the repository root.
#   - Bun and the Vercel CLI must be installed.
#   - Each app must be linked to its own Vercel project.
#   - Configure each Vercel project's Root Directory correctly.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  scripts/vercel-deploy.sh check
  scripts/vercel-deploy.sh deploy <web|preview-proxy> <preview|production>

Environment:
  VERCEL_TOKEN       Required for CI deployments
  VERCEL_ORG_ID      Optional if project linking already provides it
  VERCEL_PROJECT_ID  Optional if project linking already provides it
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    die "Required command not found: $1"
}

check_environment() {
  require_command bun
  require_command vercel

  [[ -f bun.lock || -f bun.lockb ]] ||
    die "Bun lockfile not found in repository root."

  [[ -d packages/v0-sdk ]] ||
    die "Expected packages/v0-sdk; run this script from the v0-sdk repository."
}

check_project() {
  local app="$1"
  local app_dir="$ROOT_DIR/$app"

  [[ -d "$app_dir" ]] || die "Application directory not found: $app"
  [[ -f "$app_dir/package.json" ]] ||
    die "Missing package.json in $app"

  [[ -f "$app_dir/vercel.json" ]] ||
    log "No app-specific vercel.json found in $app; using Vercel project settings."

  [[ -f "$app_dir/.vercel/project.json" ]] ||
    die "$app is not linked to a Vercel project. Run: vercel link --cwd $app"
}

build_repository() {
  log "Installing Bun workspace dependencies"
  bun install --frozen-lockfile

  log "Building repository and local SDK packages"
  bun run build

  log "Repository build completed"
}

deploy_app() {
  local app_name="$1"
  local environment="$2"
  local app_dir

  case "$app_name" in
    web)
      app_dir="apps/web"
      ;;
    preview-proxy)
      app_dir="apps/preview-proxy"
      ;;
    *)
      die "Unknown app '$app_name'. Use web or preview-proxy."
      ;;
  esac

  case "$environment" in
    preview|production)
      ;;
    *)
      die "Unknown environment '$environment'. Use preview or production."
      ;;
  esac

  check_project "$app_dir"

  local -a vercel_args=()
  if [[ -n "${VERCEL_TOKEN:-}" ]]; then
    vercel_args+=(--token "$VERCEL_TOKEN")
  fi

  log "Pulling Vercel $environment configuration for $app_name"
  vercel pull 
    --yes 
    --environment="$environment" 
    --cwd "$app_dir" 
    "${vercel_args[@]}"

  log "Building $app_name with Vercel"
  if [[ "$environment" == "production" ]]; then
    vercel build --prod --cwd "$app_dir" "${vercel_args[@]}"
  else
    vercel build --cwd "$app_dir" "${vercel_args[@]}"
  fi

  log "Deploying $app_name to $environment"
  if [[ "$environment" == "production" ]]; then
    vercel deploy 
      --prebuilt 
      --prod 
      --cwd "$app_dir" 
      "${vercel_args[@]}"
  else
    vercel deploy 
      --prebuilt 
      --cwd "$app_dir" 
      "${vercel_args[@]}"
  fi

  log "Deployment command completed for $app_name ($environment)"
}

main() {
  check_environment

  local action="${1:-}"
  shift || true

  case "$action" in
    check)
      log "Validating repository build"
      build_repository
      ;;
    deploy)
      [[ $# -eq 2 ]] || {
        usage
        exit 2
      }

      local app_name="$1"
      local environment="$2"

      require_command vercel
      [[ -n "${VERCEL_TOKEN:-}" ]] ||
        log "VERCEL_TOKEN is unset; Vercel CLI must already be authenticated."

      build_repository
      deploy_app "$app_name" "$environment"
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
