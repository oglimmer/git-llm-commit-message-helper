#!/bin/zsh
# -----------------------------------------------------------------------------
# git-llm: AI-powered commit message generator
# Uses the `llm` CLI: https://llm.datasette.io/en/stable/
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Cleanup trap ---
typeset -a _cleanup_files=()
cleanup() { for f in "${_cleanup_files[@]}"; do [[ -f "$f" ]] && rm -f "$f"; done }
trap cleanup EXIT INT TERM

# --- Helpers ---
dim()   { [[ -t 1 ]] && printf '\x1b[2m'; }
reset() { [[ -t 1 ]] && printf '\x1b[0m'; }
bold()  { [[ -t 1 ]] && printf '\x1b[1m'; }

die() { echo "error: $1" >&2; exit "${2:-1}"; }

usage() {
    cat <<'EOF'
Usage: git llm [options]

Generate an AI commit message from staged changes using the `llm` CLI.

Options:
  -y, --yes       Skip confirmation prompt; commit immediately
  -e, --edit      Go straight to editor (skip y/n/e prompt)
  -m, --model M   Use LLM model M (passed to `llm -m`)
  -h, --help      Show this help

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
llm_model=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes|--no-ask) mode=yes ;;
        -e|--edit)         mode=edit ;;
        -m|--model)
            [[ -z "${2:-}" ]] && die "--model requires an argument"
            llm_model=(-m "$2"); shift ;;
        -h|--help) usage ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

# --- Preflight checks ---
command -v llm >/dev/null 2>&1 || die "llm CLI not found. Install: https://llm.datasette.io/en/stable/"
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
- The LAST line of your response MUST be the commit message and nothing else.
- All other lines MUST start with # (they will be treated as comments).
- The commit message should be concise (ideally under 72 chars).
- Start with a lowercase verb in imperative mood (e.g. fix, add, update, refactor).
- Begin your response with # Analysis:"

# --- Generate message ---
temp_output=$(mktemp)
_cleanup_files+=("$temp_output")

dim
echo "generating commit message..."
echo
git diff --cached | llm ${llm_model[@]+"${llm_model[@]}"} "$prompt" | tee "$temp_output"
echo
reset

# --- Extract commit message (last non-empty, non-comment line) ---
commit_message=$(grep -v '^[[:space:]]*#' "$temp_output" | grep -v '^[[:space:]]*$' | tail -1)

if [[ -z "$commit_message" ]]; then
    die "LLM did not produce a usable commit message"
fi

# Strip leading/trailing whitespace
commit_message=$(echo "$commit_message" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

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
        echo "$commit_message" > "$temp_file"

        editor_cmd=$(git var GIT_EDITOR 2>/dev/null || echo "${VISUAL:-${EDITOR:-vi}}")
        eval "$editor_cmd" '"$temp_file"'

        edited=$(cat "$temp_file")
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
                    echo "$commit_message" > "$temp_file"

                    editor_cmd=$(git var GIT_EDITOR 2>/dev/null || echo "${VISUAL:-${EDITOR:-vi}}")
                    eval "$editor_cmd" '"$temp_file"'

                    edited=$(cat "$temp_file")
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
echo "$commit_message" > "$temp_msg"

if git commit -F "$temp_msg"; then
    echo "Committed."
else
    die "git commit failed"
fi
