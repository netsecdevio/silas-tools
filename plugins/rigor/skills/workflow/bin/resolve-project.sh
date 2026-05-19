#!/usr/bin/env bash

set -ueE
set -o pipefail
trap 'echo "script has failed: exit_code=$?, line=${LINENO}, script=$0, command=${BASH_COMMAND}"' ERR

function die() {
  timestamp=$(date --utc "+%Y-%m-%dT%H:%M:%S%:z")
  echo -e "[level=error func=${FUNCNAME[1]} lineno=${BASH_LINENO[0]} timestamp=${timestamp}] ${1}" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
DEFAULTS_DIR="${PLUGIN_ROOT}/defaults/conventions"
ARTIFACTS_DIR="docs/sdlc"

# --- Part 1: Project Resolution ---

GIT_ROOT="$(git rev-parse --show-toplevel)" || die "not in a git repository"
RIGOR_DIR="${GIT_ROOT}/.rigor"
PROJECT_JSON="${RIGOR_DIR}/project.json"

if [[ ! -s "${PROJECT_JSON}" ]]; then
  repository_url="$(git remote get-url origin)" || die "failed to get git remote URL"
  [[ -n "${repository_url}" ]] || die "git remote 'origin' returned empty URL"

  owner="$(git config user.email)" || die "failed to get git user.email"
  [[ -n "${owner}" ]] || die "git config user.email returned empty value"

  # Derive project name from the remote URL: take the last path segment, strip .git suffix
  project_name="$(basename "${repository_url}" .git)"
  [[ -n "${project_name}" ]] || die "failed to derive project name from repository URL"

  mkdir -p "${RIGOR_DIR}"

  cat > "${PROJECT_JSON}" << EOF
{
  "project_name": "${project_name}",
  "repository_url": "${repository_url}",
  "owner": "${owner}"
}
EOF

  # Ensure .rigor/ is gitignored
  if [[ -f "${GIT_ROOT}/.gitignore" ]]; then
    grep -qxF '.rigor/' "${GIT_ROOT}/.gitignore" 2>/dev/null || echo '.rigor/' >> "${GIT_ROOT}/.gitignore"
  else
    echo '.rigor/' > "${GIT_ROOT}/.gitignore"
  fi

  # Ensure ${ARTIFACTS_DIR}/process/ is gitignored (ephemeral scratch space)
  if [[ -f "${GIT_ROOT}/.gitignore" ]]; then
    grep -qxF "${ARTIFACTS_DIR}/process/" "${GIT_ROOT}/.gitignore" 2>/dev/null || echo "${ARTIFACTS_DIR}/process/" >> "${GIT_ROOT}/.gitignore"
  else
    echo "${ARTIFACTS_DIR}/process/" > "${GIT_ROOT}/.gitignore"
  fi
fi

# --- Part 2: Convention Seeding ---

CONVENTIONS_DIR="${GIT_ROOT}/${ARTIFACTS_DIR}/deliverables/conventions"

if [[ ! -d "${CONVENTIONS_DIR}" ]] || [[ -z "$(ls -A "${CONVENTIONS_DIR}" 2>/dev/null)" ]]; then
  if [[ -d "${DEFAULTS_DIR}" ]]; then
    mkdir -p "${CONVENTIONS_DIR}"
    cp "${DEFAULTS_DIR}"/*.md "${CONVENTIONS_DIR}/"
  else
    die "defaults/conventions directory not found at ${DEFAULTS_DIR}"
  fi
fi

# --- Output ---

echo "${PROJECT_JSON}"
