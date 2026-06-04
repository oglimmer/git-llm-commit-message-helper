# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`git-llm` is a single-file zsh script (`git-llm.sh`) that generates AI-powered git commit messages. It pipes `git diff --cached` into Simon Willison's [`llm` CLI](https://llm.datasette.io/en/stable/) and presents the suggested message for review.

## Installation

The script is meant to be installed as a git subcommand. When placed on `$PATH` as `git-llm` (or symlinked), it can be invoked as `git llm`.

## How It Works

1. Validates prerequisites: `llm` CLI installed, inside a git repo, staged changes exist
2. Warns if diff exceeds 5000 lines
3. Builds a prompt including: staged file list, diff stat, last 5 commit messages, and formatting rules
4. Pipes the full staged diff to `llm` with the prompt, streaming output to terminal
5. Extracts the commit message (last non-empty, non-comment line from LLM output); if every line was `#`-prefixed, falls back to the last comment line with the `#` stripped
6. Based on mode (`--yes`, `--edit`, or default interactive prompt), either commits directly, opens an editor, or asks user to confirm/edit/abort

## Key Design Decisions

- **zsh-only**: Uses zsh features like `${choice:l}` for lowercase conversion and `typeset -a` arrays
- **Temp file cleanup**: Uses a trap-based cleanup pattern with `_cleanup_files` array
- **Multi-line commit support**: Final commit uses `git commit -F` with a temp file rather than `-m` to handle multi-line messages
- **LLM prompt structure**: Instructs the LLM to prefix analysis with `#` comments and put the actual commit message on the last line, making extraction reliable via `grep -v '^#'`
