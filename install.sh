#!/usr/bin/env bash
set -euo pipefail

SCOPE="ask"
PROJECT_PATH=""
CLONE_DIR=""
FORCE="0"
CLEAN="0"
DRY_RUN="0"
NO_PROMPT="0"

DEFAULT_SOURCE_REPO="feddericovonwernich/orchestration-commands"
DEFAULT_SOURCE_REF="main"
REPO="${DEFAULT_SOURCE_REPO}"
REF="${DEFAULT_SOURCE_REF}"
BACKUP_DIR_OVERRIDE="${ORCHESTRATION_COMMANDS_BACKUP_DIR:-}"

usage() {
  cat <<'EOF'
Usage:
  ./install.sh [options]

Options:
  --scope <project|global|ask>   Install scope (default: ask)
  --path <project-dir>           Project directory for project scope (default: current directory)
  --clone-dir <path>             Local checkout path (default: prompt or ~/.local/share/opencode/sources/orchestration-commands)
  --repo <owner/name>            GitHub repository to clone (default: feddericovonwernich/orchestration-commands)
  --ref <git-ref>                Git branch/tag/commit for first clone (default: main)
  --force                        Replace files that already exist
  --clean                        Remove current install targets and backup directory before linking
  --dry-run                      Show actions without writing files
  --no-prompt                    Never prompt; use defaults for omitted values
  -h, --help                     Show this help

Environment variables:
  ORCHESTRATION_COMMANDS_BACKUP_DIR   Override backup directory path for --clean

Examples:
  ./install.sh --scope project --path /path/to/repo
  ./install.sh --scope global
  ./install.sh --scope project --path /path/to/repo --clean
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

abs_path() {
  python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$1"
}

default_clone_dir() {
  local repo_name
  repo_name="${REPO##*/}"
  printf '%s\n' "${HOME}/.local/share/opencode/sources/${repo_name}"
}

resolve_clone_dir() {
  local default_dir
  default_dir="$(default_clone_dir)"

  if [[ -n "${CLONE_DIR}" ]]; then
    CLONE_DIR="$(abs_path "${CLONE_DIR}")"
    return
  fi

  if [[ "${NO_PROMPT}" == "1" || ! -t 0 ]]; then
    CLONE_DIR="$(abs_path "${default_dir}")"
    return
  fi

  log ""
  log "Clone location for ${REPO}:"
  read -r -p "Directory [${default_dir}]: " CLONE_DIR
  if [[ -z "${CLONE_DIR}" ]]; then
    CLONE_DIR="${default_dir}"
  fi
  CLONE_DIR="$(abs_path "${CLONE_DIR}")"
}

ensure_clone_repo() {
  command -v git >/dev/null 2>&1 || die "git is required"

  if [[ -d "${CLONE_DIR}" ]]; then
    [[ -d "${CLONE_DIR}/.git" ]] || die "Clone directory exists but is not a git repository: ${CLONE_DIR}"
    log "Using existing clone: ${CLONE_DIR}"
    log "Update later with: git -C ${CLONE_DIR} pull"
    return
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "[dry-run] Would clone https://github.com/${REPO}.git -> ${CLONE_DIR}"
    return
  fi

  mkdir -p "$(dirname "${CLONE_DIR}")"
  git clone --branch "${REF}" "https://github.com/${REPO}.git" "${CLONE_DIR}"
  log "Cloned ${REPO}@${REF} to ${CLONE_DIR}"
}

remove_path() {
  local path="$1"
  local label="$2"

  if [[ ! -e "${path}" && ! -L "${path}" ]]; then
    return
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "[dry-run] Would remove ${label}: $path"
    return
  fi

  rm -rf "$path"
  log "Removed ${label}: $path"
}

ensure_link() {
  local source="$1"
  local target="$2"

  if [[ "$source" == "$target" ]]; then
    die "Source and target are identical ($target). Choose a different --path or --clone-dir."
  fi

  if [[ "${DRY_RUN}" != "1" ]]; then
    [[ -f "$source" ]] || die "Source file not found: $source"
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    if [[ -L "$target" ]]; then
      local current_link
      current_link="$(readlink "$target")"
      if [[ "$current_link" == "$source" ]]; then
        log "Already linked: $target"
        return
      fi
    fi

    if [[ "$FORCE" != "1" ]]; then
      die "Target already exists. Re-run with --force or --clean: $target"
    fi

    remove_path "$target" "existing install"
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] Would link: $source -> $target"
    return
  fi

  mkdir -p "$(dirname "$target")"
  ln -s "$source" "$target"
  log "Linked: $target"
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
    --clone-dir)
      [[ $# -ge 2 ]] || die "--clone-dir requires a value"
      CLONE_DIR="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || die "--repo requires a value"
      REPO="$2"
      shift 2
      ;;
    --ref)
      [[ $# -ge 2 ]] || die "--ref requires a value"
      REF="$2"
      shift 2
      ;;
    --force)
      FORCE="1"
      shift
      ;;
    --clean)
      CLEAN="1"
      shift
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    --no-prompt)
      NO_PROMPT="1"
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
  DEFAULT_BACKUP_DIR="$PROJECT_PATH/.opencode-install-backups"
else
  BASE_DIR="$HOME/.config/opencode"
  DEFAULT_BACKUP_DIR="$HOME/.config/opencode-install-backups"
fi

if [[ -n "$BACKUP_DIR_OVERRIDE" ]]; then
  BACKUP_DIR="$BACKUP_DIR_OVERRIDE"
else
  BACKUP_DIR="$DEFAULT_BACKUP_DIR"
fi

resolve_clone_dir
ensure_clone_repo

SOURCE_BASE_DIR="$CLONE_DIR/.opencode"
if [[ "$DRY_RUN" != "1" ]]; then
  [[ -f "$SOURCE_BASE_DIR/agents/orchestrator-loop.md" ]] || die "Missing source file: $SOURCE_BASE_DIR/agents/orchestrator-loop.md"
  [[ -f "$SOURCE_BASE_DIR/agents/impl-worker.md" ]] || die "Missing source file: $SOURCE_BASE_DIR/agents/impl-worker.md"
  [[ -f "$SOURCE_BASE_DIR/agents/reviewer.md" ]] || die "Missing source file: $SOURCE_BASE_DIR/agents/reviewer.md"
  [[ -f "$SOURCE_BASE_DIR/commands/orchestrate.md" ]] || die "Missing source file: $SOURCE_BASE_DIR/commands/orchestrate.md"
fi

AGENTS_DIR="$BASE_DIR/agents"
COMMANDS_DIR="$BASE_DIR/commands"

TARGET_ORCHESTRATOR="$AGENTS_DIR/orchestrator-loop.md"
TARGET_IMPL="$AGENTS_DIR/impl-worker.md"
TARGET_REVIEWER="$AGENTS_DIR/reviewer.md"
TARGET_COMMAND="$COMMANDS_DIR/orchestrate.md"

SOURCE_ORCHESTRATOR="$SOURCE_BASE_DIR/agents/orchestrator-loop.md"
SOURCE_IMPL="$SOURCE_BASE_DIR/agents/impl-worker.md"
SOURCE_REVIEWER="$SOURCE_BASE_DIR/agents/reviewer.md"
SOURCE_COMMAND="$SOURCE_BASE_DIR/commands/orchestrate.md"

if [[ "$DRY_RUN" == "1" ]]; then
  log "[dry-run] Target base: $BASE_DIR"
  log "[dry-run] Backup dir: $BACKUP_DIR"
  log "[dry-run] Scope: $SCOPE"
fi

if [[ "$CLEAN" == "1" ]]; then
  log ""
  log "Cleaning existing installation and backups..."
  remove_path "$TARGET_ORCHESTRATOR" "existing install"
  remove_path "$TARGET_IMPL" "existing install"
  remove_path "$TARGET_REVIEWER" "existing install"
  remove_path "$TARGET_COMMAND" "existing install"
  remove_path "$BACKUP_DIR" "backup directory"
  FORCE="1"
fi

log ""
ensure_link "$SOURCE_ORCHESTRATOR" "$TARGET_ORCHESTRATOR"
ensure_link "$SOURCE_IMPL" "$TARGET_IMPL"
ensure_link "$SOURCE_REVIEWER" "$TARGET_REVIEWER"
ensure_link "$SOURCE_COMMAND" "$TARGET_COMMAND"

if [[ "$DRY_RUN" == "1" ]]; then
  log ""
  log "Dry run complete. No files were written."
else
  log ""
  log "Install complete."
fi

log ""
log "Installed command: /orchestrate"
log "Try:"
log "  /orchestrate Build a feature to ..."
log "  /orchestrate exec <approved plan text>"
