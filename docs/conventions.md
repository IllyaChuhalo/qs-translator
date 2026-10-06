# Project Conventions & Workflow

This document outlines the branching, commit, pull request, and code quality standards for this repository.

---

## 1. Branch Flow

Branches must be created from `main` and follow this naming format:

```text
<issue-number>-<type>-<short-desc>
```

### Allowed types:

- `feat` — new feature
- `fix` — bug fix
- `chore` — maintenance, tooling, linters, dependencies
- `docs` — documentation changes
- `refactor` — code restructuring without behavior changes
- `perf` — performance improvements

### Examples:

- `2-chore-code-cleanup-and-linters`
- `5-feat-add-auto-polish-toggle`
- `8-fix-popup-position`

---

## 2. Commit Flow

We strictly adhere to [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0).

```text
<type>(<scope>): <description>
```

_(scope is optional, but recommended for clarity)_

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

- `chore(config): add ruff, commitlint, and git hooks`
- `refactor(qs): clean comments and format shell.qml`
- `feat(stt): dynamic CUDA runtime fallback`
- `docs: update setup instructions for linters`

Commits are automatically validated on `git commit` via `commitlint`.

---

## 3. Pull Request Flow

Pull request titles must follow the conventional format and reference the target issue:

```text
<type>(<scope>): <title> #<issue-number>
```

or

```text
<type>: <title> #<issue-number>
```

### Examples:

- `chore(config): code cleanup, linters, and git hooks #2`
- `feat(qs): add auto polish toggle icon inside input #5`
- `fix(qs): fix gradient stop alpha syntax in shell #8`

---

## 4. Code & Comment Guidelines

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
   - `commit-msg`: Runs `commitlint` to ensure the commit message follows Conventional Commits.
   - Installed automatically via `npm install` (powered by `simple-git-hooks`).
