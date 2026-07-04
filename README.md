# git-llm

AI-powered commit messages using either Simon Willison's [`llm`](https://llm.datasette.io/en/stable/) CLI or Anthropic's [`claude`](https://claude.com/claude-code) CLI (Claude Code in headless mode).

## Install

Requires: zsh, git, and at least one backend ([llm](https://llm.datasette.io/en/stable/) or [claude](https://claude.com/claude-code))

```sh
# Copy or symlink somewhere on your PATH as "git-llm"
cp git-llm.sh /usr/local/bin/git-llm
chmod +x /usr/local/bin/git-llm
```

## Usage

```sh
git add -p                # stage changes as usual
git llm                   # generate + review commit message
git llm -b claude         # use the claude CLI instead of llm
```

Options:

```
-y, --yes         Commit immediately without confirmation (alias: --no-ask)
-e, --edit        Open message in editor (skip y/n/e prompt)
-b, --backend B   Backend: llm | claude
-m, --model M     Use a specific model (llm -m / claude --model)
```

The backend defaults to `$GIT_LLM_BACKEND` if set, otherwise whichever of
`llm` / `claude` is installed (in that order). With `-b claude` the model
flag accepts Claude aliases like `sonnet`, `opus`, or `haiku`.

## Tip: git alias

Stage everything and commit in one shot:

```gitconfig
[alias]
    ai = !git add . && git llm --no-ask
```

Then just run `git ai`.

## AI code review (GitHub Actions)

`.github/workflows/ai-review.yml` reviews pull requests via
[oglimmer/review-action](https://github.com/oglimmer/review-action).
It requires an `OPENAI_API_KEY` repository secret.
