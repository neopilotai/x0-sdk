#!/usr/bin/env bash
set -Eeuo pipefail

# v0-clone environment, build, and Vercel deployment
#
# Usage:
#   ./scripts/v0-clone-deploy.sh env
#   ./scripts/v0-clone-deploy.sh build
#   ./scripts/v0-clone-deploy.sh deploy web preview
#   ./scripts/v0-clone-deploy.sh deploy proxy preview
#   ./scripts/v0-clone-deploy.sh deploy all production
#
# Required for deployment:
#   VERCEL_TOKEN
#   VERCEL_ORG_ID
#   VERCEL_WEB_PROJECT_ID (for web or all)
#   VERCEL_PROXY_PROJECT_ID (for proxy or all)
#
# Optional:
#   V0_API_KEY
#   V0_PREVIEW_PROXY_URL
#   V0_CLONE_ORIGIN
#   V0_CLONE_DIR
#
# Run from any directory; default paths are resolved from this script.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"

# Relative overrides are resolved from the caller's working directory.
V0_CLONE_DIR="${V0_CLONE_DIR:-$REPO_ROOT/examples/v0-clone}"
if [[ "$V0_CLONE_DIR" != /* ]]; then
  V0_CLONE_DIR="$(pwd -P)/$V0_CLONE_DIR"
fi

WEB_DIR="$V0_CLONE_DIR/apps/web"
PROXY_DIR="$V0_CLONE_DIR/apps/preview-proxy"
ENV_EXAMPLE="$V0_CLONE_DIR/.env.example"
ENV_LOCAL="$V0_CLONE_DIR/.env.local"

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
v0-clone deployment

Usage:
  ./scripts/v0-clone-deploy.sh env
  ./scripts/v0-clone-deploy.sh build
  ./scripts/v0-clone-deploy.sh deploy <web|proxy|all> [preview|production]

The deploy environment defaults to preview. Deploying all runs proxy before web.

Required for deployment:
  VERCEL_TOKEN
  VERCEL_ORG_ID
  VERCEL_WEB_PROJECT_ID (for web or all)
  VERCEL_PROXY_PROJECT_ID (for proxy or all)

Optional:
  V0_API_KEY
  V0_PREVIEW_PROXY_URL
  V0_CLONE_ORIGIN
  V0_CLONE_DIR
EOF
}

usage_error() {
  printf 'ERROR: %s\n\n' "$*" >&2
  usage >&2
  exit 2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    die "Required command not found: $1"
}

require_variable() {
  local variable_name="$1"

  [[ -n "${!variable_name:-}" ]] ||
    die "Set $variable_name before deploying."
}

check_layout() {
  [[ -f "$REPO_ROOT/package.json" ]] ||
    die "Repository root package.json not found: $REPO_ROOT"

  [[ -f "$REPO_ROOT/bun.lock" || -f "$REPO_ROOT/bun.lockb" ]] ||
    die "Bun lockfile not found in $REPO_ROOT"

  [[ -f "$V0_CLONE_DIR/package.json" ]] ||
    die "Missing v0-clone package.json: $V0_CLONE_DIR/package.json"

  [[ -f "$ENV_EXAMPLE" ]] ||
    die "Missing environment template: $ENV_EXAMPLE"

  [[ -f "$WEB_DIR/package.json" ]] ||
    die "Missing web package.json: $WEB_DIR/package.json"

  [[ -f "$WEB_DIR/vercel.json" ]] ||
    die "Missing web Vercel configuration: $WEB_DIR/vercel.json"

  [[ -f "$PROXY_DIR/package.json" ]] ||
    die "Missing proxy package.json: $PROXY_DIR/package.json"

  [[ -f "$PROXY_DIR/vercel.json" ]] ||
    die "Missing proxy Vercel configuration: $PROXY_DIR/vercel.json"
}

generate_env() {
  if [[ -e "$ENV_LOCAL" || -L "$ENV_LOCAL" ]]; then
    die "$ENV_LOCAL already exists. Back it up before regenerating."
  fi

  # Preserve the official template and never print secret values.
  cp "$ENV_EXAMPLE" "$ENV_LOCAL"
  chmod 600 "$ENV_LOCAL"

  log "Created $ENV_LOCAL from .env.example"
  log "Edit it to configure local development."
  log "Production variables must also be configured in Vercel."
}

build_workspace() {
  require_command bun

  log "Installing monorepo dependencies"
  (
    cd "$REPO_ROOT"
    bun install --frozen-lockfile
  )

  log "Building the workspace as documented by v0-clone"
  (
    cd "$REPO_ROOT"
    bun run build
  )

  log "Workspace build completed"
}

check_deploy_config() {
  local target="$1"

  require_variable VERCEL_TOKEN
  require_variable VERCEL_ORG_ID

  case "$target" in
    web)
      require_variable VERCEL_WEB_PROJECT_ID
      ;;
    proxy)
      require_variable VERCEL_PROXY_PROJECT_ID
      ;;
    *)
      die "Invalid target: $target"
      ;;
  esac
}

deploy_one() {
  local target="$1"
  local environment="$2"
  local app_dir
  local project_id

  case "$target" in
    web)
      app_dir="$WEB_DIR"
      project_id="$VERCEL_WEB_PROJECT_ID"
      ;;
    proxy)
      app_dir="$PROXY_DIR"
      project_id="$VERCEL_PROXY_PROJECT_ID"
      ;;
    *)
      die "Unknown target: $target"
      ;;
  esac

  case "$environment" in
    preview|production) ;;
    *) die "Environment must be preview or production." ;;
  esac

  [[ -d "$app_dir" ]] || die "App directory missing: $app_dir"

  # Supply project identity directly to Vercel CLI.
  # This avoids interactive `vercel link` and repo.json discovery.
  export VERCEL_PROJECT_ID="$project_id"

  local -a cli_args=(--cwd "$app_dir" --token "$VERCEL_TOKEN")

  log "Pulling $environment configuration for $target"
  vercel pull --yes "--environment=$environment" "${cli_args[@]}"

  log "Building $target"
  if [[ "$environment" == "production" ]]; then
    vercel build --prod "${cli_args[@]}"
  else
    vercel build "${cli_args[@]}"
  fi

  log "Deploying $target to $environment"
  if [[ "$environment" == "production" ]]; then
    vercel deploy --prebuilt --prod "${cli_args[@]}"
  else
    vercel deploy --prebuilt "${cli_args[@]}"
  fi

  log "$target deployment command completed"
}

main() {
  local action="${1:-help}"
  if (($# > 0)); then
    shift
  fi

  case "$action" in
    env)
      (($# == 0)) || usage_error "The env command does not accept arguments."
      check_layout
      generate_env
      ;;

    build)
      (($# == 0)) || usage_error "The build command does not accept arguments."
      check_layout
      build_workspace
      ;;

    deploy)
      if (($# < 1 || $# > 2)); then
        usage_error "Usage: $0 deploy <web|proxy|all> [preview|production]"
      fi

      local target="$1"
      local environment="${2:-preview}"

      case "$environment" in
        preview|production) ;;
        *) usage_error "Environment must be preview or production." ;;
      esac

      check_layout
      require_command vercel

      case "$target" in
        web|proxy)
          check_deploy_config "$target"
          ;;
        all)
          check_deploy_config proxy
          check_deploy_config web
          ;;
        *)
          usage_error "Target must be web, proxy, or all."
          ;;
      esac

      build_workspace
      if [[ "$target" == "all" ]]; then
        deploy_one proxy "$environment"
        deploy_one web "$environment"
      else
        deploy_one "$target" "$environment"
      fi
      ;;

    help|-h|--help)
      (($# == 0)) || usage_error "Help does not accept arguments."
      usage
      ;;

    *)
      usage_error "Unknown command: $action"
      ;;
  esac
}

main "$@"
