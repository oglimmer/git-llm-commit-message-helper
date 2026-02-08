# git-llm

AI-powered commit messages using Simon Willison's [`llm`](https://llm.datasette.io/en/stable/) CLI.

## Install

Requires: [llm](https://llm.datasette.io/en/stable/), zsh, git

```sh
# Copy or symlink somewhere on your PATH as "git-llm"
cp git-llm.sh /usr/local/bin/git-llm
chmod +x /usr/local/bin/git-llm
```

## Usage

```sh
git add -p                # stage changes as usual
git llm                   # generate + review commit message
```

Options:

```
-y, --yes       Commit immediately without confirmation (alias: --no-ask)
-e, --edit      Open message in editor (skip y/n/e prompt)
-m, --model M   Use a specific LLM model
```

## Tip: git alias

Stage everything and commit in one shot:

```gitconfig
[alias]
    ai = !git add . && git llm --no-ask
```

Then just run `git ai`.
