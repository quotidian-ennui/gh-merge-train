## Review Style
- Be specific and actionable in feedback.
- Explain the "why" behind recommendations.
- Always prioritize security vulnerabilities and performance issues that could impact users.
- Never suggest changes to improve readability.
- Never suggest changes related to platform variants for GNU tooling.

## General Principles

- Use shellcheck for static analysis when available
- Prefer safe expansions: double-quote variable references (`"$var"`), use `${var}` for clarity, and avoid `eval`
- Use modern Bash features (`[[ ]]`, `local`, arrays) when portability requirements allow; fall back to POSIX constructs only when needed
- Choose reliable parsers for structured data instead of ad-hoc text processing

## Script Structure

- Start with a clear shebang: `#!/usr/bin/env bash` unless specified otherwise
- Include a header comment explaining the script's purpose
- Define default values for all variables at the top
- Use functions for reusable code blocks
- Create reusable functions instead of repeating similar blocks of code
- Keep the main execution flow clean and readable

## Working with JSON and YAML

- Prefer dedicated parsers (`jq` for JSON, `yq` for YAML—or `jq` on JSON converted via `yq`) over ad-hoc text processing with `grep`, `awk`, or shell string splitting
- Validate that required fields exist and handle missing/invalid data paths explicitly (e.g., by checking `jq` exit status or using `// empty`)
- Quote jq/yq filters to prevent shell expansion and prefer `--raw-output` when you need plain strings
- Treat parser errors as fatal: combine with `set -euo pipefail` or test command success before using results
- Document parser dependencies at the top of the script and fail fast with a helpful message if `jq`/`yq` (or alternative tools) are required but not installed

## Pull request behaviour

- When editing or creating a pull request ensure the PR title is a conventional commit message
- When editing or creating a pull request use markdown lists to write a short summary of the changes inside the `SQUASH_MERGE` markers
- Ensure the each line between the SQUASH_MERGE markers are less than 80 characters but complete.
- Ensure that a detailed summary of changes exists under a new heading `Copilot changes` that is separate to the existing `Changes` block
- When a pull request fixes an issue, ensure that it uses the phrase `resolves` and then the issue number.
