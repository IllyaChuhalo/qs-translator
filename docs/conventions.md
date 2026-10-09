# Project Conventions & Workflow

This document outlines the branching, commit, pull request, and code quality standards for this repository.

---

## 1. Issues

Every change starts with an issue. Use one of the issue templates (**New issue** button):

- **Bug report** — something is broken or behaves unexpectedly.
- **Suggestion / Proposal** — a feature, improvement, or change.
- **Chore** — maintenance work: docs, tooling, refactoring, dependency updates.

The issue number is then used in the branch name, every commit, and the pull request.

---

## 2. Branch Flow

Branches must be created from `main` and follow this naming format:

```text
<type>/<optional_scope>-<issue_number>-<description>
```

Only lowercase letters, digits, and hyphens are allowed in scope and description.

### Allowed types:

- `feat` — new feature
- `fix` — bug fix
- `chore` — maintenance, tooling, linters, dependencies
- `docs` — documentation changes
- `refactor` — code restructuring without behavior changes
- `perf` — performance improvements
- `ci` — CI/CD workflows and repository templates
- `style`, `test`, `build`, `revert` — as defined by Conventional Commits

### Examples:

- `feat/qs-5-add-auto-polish-toggle`
- `fix/8-popup-position`
- `chore/config-2-code-cleanup-and-linters`

---

## 3. Commit Flow

We strictly adhere to [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0), with the issue number appended to the message:

```text
<type>(<optional_scope>): <message> #<issue_number>
```

The issue number must be the same as in the branch name.

### Allowed scopes:

- `qs` — Quickshell UI and QML files (`qs/*.qml`)
- `stt` — Speech-to-text and AI polishing backend (`stt/*.py`)
- `scripts` — Setup and installation bash scripts (`scripts/*.sh`)
- `tools` — Testing and debugging utilities (`tools/`)
- `docs` — Documentation and guides (`docs/`, `README.md`)
- `config` — Configuration files (`.editorconfig`, `pyproject.toml`, `package.json`, etc.)
- `ci` — CI/CD workflows (`.github/`)
- `deps` — Dependency updates

### Examples:

- `chore(config): add ruff, commitlint, and git hooks #2`
- `refactor(qs): clean comments and format shell.qml #2`
- `feat(stt): dynamic CUDA runtime fallback #5`
- `docs: update setup instructions for linters #7`

Commits are validated locally on `git commit` via `commitlint`, and again on every pull request.

---

## 4. Pull Request Flow

Opening a PR (**Create pull request**) pre-fills the description from [`.github/PULL_REQUEST_TEMPLATE.md`](../.github/PULL_REQUEST_TEMPLATE.md). Fill in every section.

The PR title uses the same format as commits:

```text
<type>(<optional_scope>): <title> #<issue_number>
```

The description must contain `Closes #<issue_number>` for the same issue.

### Examples:

- `chore(config): code cleanup, linters, and git hooks #2`
- `feat(qs): add auto polish toggle icon inside input #5`
- `fix(qs): fix gradient stop alpha syntax in shell #8`

### Automated checks

The [`PR Checks`](../.github/workflows/pr-checks.yml) workflow runs on every PR and fails when:

- the branch name does not match the pattern from section 2;
- the PR title does not match the format above;
- the issue number differs between the branch, the PR title, the `Closes #N` line, and any commit message;
- any commit message is not a valid conventional commit with an issue number (`commitlint`).

The [`CI`](../.github/workflows/ci.yml) workflow additionally runs the linters. The branch/title/issue logic lives in [`scripts/validate-pr.mjs`](../scripts/validate-pr.mjs).

---

## 5. Code & Comment Guidelines

1. **Comments**:
   - Write or keep **only** single-sentence descriptions for complex, non-obvious functions where understanding without the comment would require extensive reverse engineering.
   - Avoid self-evident comments (e.g. `// increment counter`, `// return result`).
   - Never keep commented-out dead code or abandoned debug traces.

2. **Formatting & Linting**:
   - Python: Checked and formatted via **Ruff** (`ruff check .` / `ruff format .`).
   - QML: Formatted according to Qt conventions via **qmlformat** (`qmlformat -i qs/*.qml`).
   - Markdown & JSON: Formatted via **Prettier** (`prettier --write`).
   - Run all checks locally:
     ```bash
     npm run lint
     ```
   - Automatically format everything:
     ```bash
     npm run format
     ```

3. **Git Hooks**:
   - `pre-commit`: Runs `./scripts/lint.sh` to ensure all staged code adheres to lint and format rules.
   - `commit-msg`: Runs `commitlint` to ensure the commit message follows Conventional Commits and ends with an issue number.
   - Installed automatically via `npm install` (powered by `simple-git-hooks`).
