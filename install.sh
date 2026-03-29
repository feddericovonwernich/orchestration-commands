#!/usr/bin/env bash
set -euo pipefail

SCOPE="ask"
PROJECT_PATH=""
COMMAND_NAME="orchestrate"
MAX_LOOPS="3"
FORCE="0"
DRY_RUN="0"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

DEFAULT_SOURCE_REPO="feddericovonwernich/orchestration-commands"
DEFAULT_SOURCE_REF="${ORCHESTRATION_COMMANDS_SOURCE_REF:-main}"
SOURCE_BASE_URL="${ORCHESTRATION_COMMANDS_SOURCE_BASE_URL:-https://raw.githubusercontent.com/${DEFAULT_SOURCE_REPO}/${DEFAULT_SOURCE_REF}/.opencode}"

usage() {
  cat <<'EOF'
Usage:
  ./install.sh [options]

Options:
  --scope <project|global|ask>   Install scope (default: ask)
  --path <project-dir>           Project directory for project scope (default: current directory)
  --command-name <name>          Slash command name (default: orchestrate)
  --max-loops <n>                Maximum implementation/review loops (default: 3)
  --force                        Overwrite files without backups
  --dry-run                      Show actions without writing files
  -h, --help                     Show this help

Environment variables:
  ORCHESTRATION_COMMANDS_SOURCE_REF       Git ref for remote source fallback (default: main)
  ORCHESTRATION_COMMANDS_SOURCE_BASE_URL  Full base URL for remote source fallback

Examples:
  ./install.sh --scope project
  ./install.sh --scope project --path /path/to/repo --command-name ship --max-loops 4
  ./install.sh --scope global --force
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

validate_positive_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

validate_command_name() {
  [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

resolve_script_dir() {
  local src
  src="${BASH_SOURCE[0]:-}"
  if [[ -n "$src" && "$src" != "-" && -f "$src" ]]; then
    (cd "$(dirname "$src")" && pwd)
    return 0
  fi

  return 1
}

detect_local_source_dir() {
  local script_dir
  local candidate

  if script_dir="$(resolve_script_dir 2>/dev/null)"; then
    candidate="$script_dir/.opencode"
    if [[ -f "$candidate/agents/orchestrator-loop.md" && -f "$candidate/agents/impl-worker.md" && -f "$candidate/agents/reviewer.md" && -f "$candidate/commands/orchestrate.md" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  return 1
}

fetch_remote_source() {
  local source_rel="$1"
  local output="$2"
  local source_url

  source_url="${SOURCE_BASE_URL}/${source_rel}"

  if ! command -v curl >/dev/null 2>&1; then
    die "curl is required for remote source fallback but is not available"
  fi

  if ! curl -fsSL "$source_url" >"$output"; then
    die "Failed to fetch source file: $source_url"
  fi
}

render_source_file() {
  local source_rel="$1"
  local output="$2"

  if [[ -n "$LOCAL_SOURCE_DIR" ]]; then
    cp "$LOCAL_SOURCE_DIR/$source_rel" "$output"
    return 0
  fi

  fetch_remote_source "$source_rel" "$output"
}

apply_max_loops_replacements() {
  local file="$1"

  sed -E \
    -e "s/(Max loops: )[0-9]+/\\1${MAX_LOOPS}/g" \
    -e "s/(Stop when loops reach )[0-9]+/\\1${MAX_LOOPS}/g" \
    -e "s|(LOOPS_USED: n/)[0-9]+|\\1${MAX_LOOPS}|g" \
    -e "s/(max loops )[0-9]+/\\1${MAX_LOOPS}/g" \
    "$file" >"${file}.tmp"

  mv "${file}.tmp" "$file"
}

install_from_source() {
  local target="$1"
  local source_rel="$2"
  local apply_max_loops="$3"
  local tmp_rendered

  tmp_rendered="$(mktemp)"
  render_source_file "$source_rel" "$tmp_rendered"

  if [[ "$apply_max_loops" == "1" ]]; then
    apply_max_loops_replacements "$tmp_rendered"
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] Would write: $target"
    if [[ -e "$target" && "$FORCE" == "0" ]]; then
      log "[dry-run] Would backup existing file: ${target}.bak.${TIMESTAMP}"
    fi
  else
    mkdir -p "$(dirname "$target")"
    if [[ -e "$target" && "$FORCE" == "0" ]]; then
      local backup
      backup="${target}.bak.${TIMESTAMP}"
      cp "$target" "$backup"
      log "Backed up: $target -> $backup"
    fi
    cp "$tmp_rendered" "$target"
    log "Installed: $target"
  fi

  rm -f "$tmp_rendered"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      [[ $# -ge 2 ]] || die "--scope requires a value"
      SCOPE="$2"
      shift 2
      ;;
    --path)
      [[ $# -ge 2 ]] || die "--path requires a value"
      PROJECT_PATH="$2"
      shift 2
      ;;
    --command-name)
      [[ $# -ge 2 ]] || die "--command-name requires a value"
      COMMAND_NAME="$2"
      shift 2
      ;;
    --max-loops)
      [[ $# -ge 2 ]] || die "--max-loops requires a value"
      MAX_LOOPS="$2"
      shift 2
      ;;
    --force)
      FORCE="1"
      shift
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

case "$SCOPE" in
  project|global|ask)
    ;;
  *)
    die "Invalid --scope value '$SCOPE'. Expected project, global, or ask."
    ;;
esac

validate_command_name "$COMMAND_NAME" || die "Invalid command name '$COMMAND_NAME'. Use letters, numbers, dashes, or underscores."
validate_positive_int "$MAX_LOOPS" || die "Invalid --max-loops '$MAX_LOOPS'. Use a positive integer."

if [[ "$SCOPE" == "ask" ]]; then
  if [[ -t 0 ]]; then
    log "Choose install scope:"
    log "  1) project (.opencode in a repository)"
    log "  2) global (~/.config/opencode)"
    read -r -p "Enter choice [1/2]: " choice
    case "$choice" in
      1) SCOPE="project" ;;
      2) SCOPE="global" ;;
      *) die "Invalid choice '$choice'" ;;
    esac
  else
    SCOPE="project"
    log "Non-interactive mode detected; defaulting --scope to project"
  fi
fi

if [[ "$SCOPE" == "project" ]]; then
  if [[ -z "$PROJECT_PATH" ]]; then
    PROJECT_PATH="$PWD"
  fi
  [[ -d "$PROJECT_PATH" ]] || die "Project path does not exist: $PROJECT_PATH"
  BASE_DIR="$PROJECT_PATH/.opencode"
else
  BASE_DIR="$HOME/.config/opencode"
fi

AGENTS_DIR="$BASE_DIR/agents"
COMMANDS_DIR="$BASE_DIR/commands"
COMMAND_FILE="$COMMANDS_DIR/${COMMAND_NAME}.md"

LOCAL_SOURCE_DIR=""
if LOCAL_SOURCE_DIR="$(detect_local_source_dir 2>/dev/null)"; then
  SOURCE_MODE="local"
else
  SOURCE_MODE="remote"
fi

if [[ "$DRY_RUN" == "1" ]]; then
  log "[dry-run] Target base: $BASE_DIR"
  log "[dry-run] Scope: $SCOPE"
  log "[dry-run] Command name: /$COMMAND_NAME"
  log "[dry-run] Max loops: $MAX_LOOPS"
else
  mkdir -p "$AGENTS_DIR" "$COMMANDS_DIR"
fi

if [[ "$SOURCE_MODE" == "local" ]]; then
  log "Using local source templates from: $LOCAL_SOURCE_DIR"
else
  log "Using remote source templates from: $SOURCE_BASE_URL"
fi

install_from_source "$AGENTS_DIR/orchestrator-loop.md" "agents/orchestrator-loop.md" "1"
install_from_source "$AGENTS_DIR/impl-worker.md" "agents/impl-worker.md" "0"
install_from_source "$AGENTS_DIR/reviewer.md" "agents/reviewer.md" "0"
install_from_source "$COMMAND_FILE" "commands/orchestrate.md" "1"

if [[ "$DRY_RUN" == "1" ]]; then
  log ""
  log "Dry run complete. No files were written."
else
  log ""
  log "Install complete."
fi

log ""
log "Installed command: /$COMMAND_NAME"
log "Try:"
log "  /$COMMAND_NAME Build a feature to ..."
log "  /$COMMAND_NAME exec <approved plan text>"
