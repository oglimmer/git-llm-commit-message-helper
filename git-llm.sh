#!/bin/zsh
# -----------------------------------------------------------------------------
# git-llm: AI-powered commit message generator
# Backends:
#   llm    - Simon Willison's `llm` CLI: https://llm.datasette.io/en/stable/
#   claude - Anthropic's Claude Code CLI in headless mode (`claude -p`)
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Cleanup trap ---
typeset -a _cleanup_files=()
cleanup() { for f in "${_cleanup_files[@]}"; do [[ -f "$f" ]] && rm -f "$f"; done }
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# --- Helpers ---
dim()   { [[ -t 1 ]] && printf '\x1b[2m'; return 0; }
reset() { [[ -t 1 ]] && printf '\x1b[0m'; return 0; }
bold()  { [[ -t 1 ]] && printf '\x1b[1m'; return 0; }

die() { echo "error: $1" >&2; exit "${2:-1}"; }

# Open $1 (a file) in the user's editor, then echo its contents.
edit_message() {
    local file="$1"
    local editor_cmd
    editor_cmd=$(git var GIT_EDITOR 2>/dev/null || echo "${VISUAL:-${EDITOR:-vi}}")
    eval "$editor_cmd" '"$file"'
    cat "$file"
}

usage() {
    cat <<'EOF'
Usage: git llm [options]

Generate an AI commit message from staged changes.

Options:
  -y, --yes         Skip confirmation prompt; commit immediately (alias: --no-ask)
  -e, --edit        Go straight to editor (skip y/n/e prompt)
  -b, --backend B   Backend to use: llm | claude
                    (default: $GIT_LLM_BACKEND, else first of llm/claude found)
  -m, --model M     Model to use (passed to `llm -m` or `claude --model`)
  -h, --help        Show this help

Workflow:
  1. Stage changes with `git add`
  2. Run `git llm`
  3. Review the suggested message
  4. Choose: [y]es to commit, [e]dit to refine, [n]o to abort
EOF
    exit 0
}

# --- Parse arguments ---
mode=prompt   # prompt | yes | edit
model=""
backend="${GIT_LLM_BACKEND:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes|--no-ask) mode=yes ;;
        -e|--edit)         mode=edit ;;
        -b|--backend)
            [[ -z "${2:-}" ]] && die "--backend requires an argument"
            backend="$2"; shift ;;
        -m|--model)
            [[ -z "${2:-}" ]] && die "--model requires an argument"
            model="$2"; shift ;;
        -h|--help) usage ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

# --- Resolve backend ---
if [[ -z "$backend" ]]; then
    if command -v llm >/dev/null 2>&1; then
        backend=llm
    elif command -v claude >/dev/null 2>&1; then
        backend=claude
    else
        die "no backend found. Install llm (https://llm.datasette.io/en/stable/) or claude (https://claude.com/claude-code)"
    fi
fi

case "$backend" in
    llm)
        command -v llm >/dev/null 2>&1 || die "llm CLI not found. Install: https://llm.datasette.io/en/stable/" ;;
    claude)
        command -v claude >/dev/null 2>&1 || die "claude CLI not found. Install: https://claude.com/claude-code" ;;
    *)
        die "unknown backend: $backend (expected: llm, claude)" ;;
esac

# --- Preflight checks ---
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"

if [[ -z "$(git diff --cached --name-only)" ]]; then
    die "no staged changes. Stage files with 'git add' first."
fi

# --- Diff size check ---
diff_stat=$(git diff --cached --stat | tail -1)
diff_lines=$(git diff --cached | wc -l | tr -d ' ')
if (( diff_lines > 5000 )); then
    echo "warning: large diff ($diff_lines lines). LLM may truncate. Consider committing in smaller chunks." >&2
fi

# --- Build prompt ---
last_commits=$(git log -5 --pretty=format:"- %s" 2>/dev/null || true)
staged_files=$(git diff --cached --name-only)

prompt="Below is a diff of all staged changes.

Staged files:
$staged_files

Diff stat: $diff_stat

For context, here are recent commit messages from this repo:
$last_commits

Generate a commit message for these changes following the style of the previous commits.

Rules:
- Begin your response with # Analysis:
- All analysis lines MUST start with # (they will be treated as comments).
- The LAST line of your response MUST be the commit message WITHOUT a # prefix.
- The commit message should be concise (ideally under 72 chars).
- Start with a lowercase verb in imperative mood (e.g. fix, add, update, refactor).
- IMPORTANT: The final commit message line must NOT start with #."

# --- Generate message ---
temp_output=$(mktemp)
_cleanup_files+=("$temp_output")

# Build the backend command. Both read the diff on stdin and take the prompt
# as an argument; `claude -p` is Claude Code's non-interactive print mode.
typeset -a backend_cmd
case "$backend" in
    llm)    backend_cmd=(llm);       [[ -n "$model" ]] && backend_cmd+=(-m "$model") ;;
    claude) backend_cmd=(claude -p); [[ -n "$model" ]] && backend_cmd+=(--model "$model") ;;
esac

dim
echo "generating commit message ($backend)..."
echo
git diff --cached | "${backend_cmd[@]}" "$prompt" | tee "$temp_output"
echo
reset

# --- Extract commit message (last non-empty, non-comment line) ---
# `|| true` so that grep finding no match (exit 1) doesn't trip `set -e`/pipefail
commit_message=$(grep -v '^[[:space:]]*#' "$temp_output" | grep -v '^[[:space:]]*$' | tail -1) || true

if [[ -z "$commit_message" ]]; then
    die "LLM did not produce a usable commit message"
fi

# Strip leading/trailing whitespace
commit_message=$(printf '%s\n' "$commit_message" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# --- Confirm / edit / abort ---
bold
echo "Commit message: $commit_message"
reset
echo

case "$mode" in
    yes)
        echo "Committing (--yes)..."
        ;;
    edit)
        temp_file=$(mktemp)
        _cleanup_files+=("$temp_file")
        printf '%s\n' "$commit_message" > "$temp_file"

        edited=$(edit_message "$temp_file")
        if [[ -z "$edited" ]]; then
            echo "Empty message — commit cancelled."
            exit 1
        fi
        commit_message="$edited"
        ;;
    prompt)
        while true; do
            printf "[y]es, commit  [e]dit  [n]o, abort: "
            read -r choice
            case "${choice:l}" in  # :l = zsh lowercase
                y|yes)
                    break ;;
                e|edit)
                    temp_file=$(mktemp)
                    _cleanup_files+=("$temp_file")
                    printf '%s\n' "$commit_message" > "$temp_file"

                    edited=$(edit_message "$temp_file")
                    if [[ -z "$edited" ]]; then
                        echo "Empty message — commit cancelled."
                        exit 1
                    fi
                    commit_message="$edited"

                    bold
                    echo "Commit message: $commit_message"
                    reset
                    echo
                    ;;
                n|no|q|quit)
                    echo "Aborted."
                    exit 1 ;;
                *)
                    echo "Please choose y, e, or n." ;;
            esac
        done
        ;;
esac

# --- Commit (use -F to handle multi-line messages properly) ---
temp_msg=$(mktemp)
_cleanup_files+=("$temp_msg")
printf '%s\n' "$commit_message" > "$temp_msg"

if git commit -F "$temp_msg"; then
    echo "Committed."
else
    die "git commit failed"
fi
