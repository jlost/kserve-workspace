# Multi-Fork Development Workflow for KServe

This guide covers workflow patterns for managing changes across the KServe fork hierarchy:

- **Upstream**: kserve/kserve
- **Midstream**: opendatahub-io/kserve
- **Downstream**: red-hat-data-services/kserve
- **Personal**: $GITHUB_USER/kserve

---

## Remote Setup

Extend the existing ODH guidance to include all four forks:

```bash
# Clone your personal fork
git clone git@github.com:$GITHUB_USER/kserve.git
cd kserve

# Add all remotes
git remote add upstream git@github.com:kserve/kserve.git
git remote add odh git@github.com:opendatahub-io/kserve.git  
git remote add downstream git@github.com:red-hat-data-services/kserve.git

# Verify setup
git remote -v
```

Expected result:

```
downstream  git@github.com:red-hat-data-services/kserve.git
odh         git@github.com:opendatahub-io/kserve.git
origin      git@github.com:$GITHUB_USER/kserve.git
upstream    git@github.com:kserve/kserve.git
```

---

## Key Branch Tracking Strategy

Keep local tracking branches for the important branches from each fork:

```bash
# Fetch all remotes
git fetch --all --tags

# Create local tracking branches (optional but useful)
git branch --track upstream-master upstream/master
git branch --track odh-master odh/master
git branch --track odh-release-v0.15 odh/release-v0.15   # or current release
git branch --track downstream-main downstream/main       # adjust branch name
```

---

## PR Workflow Patterns

### 1. Contributing to Upstream (kserve/kserve)

```bash
git fetch upstream
git checkout -b feature/my-upstream-change upstream/master
# ... make changes ...
git push -u origin feature/my-upstream-change
# Create PR: $GITHUB_USER/kserve -> kserve/kserve (master)
```

### 2. Contributing to Midstream (opendatahub-io/kserve)

```bash
git fetch odh
git checkout -b feature/my-odh-change odh/master  # or odh/release-vX.Y
# ... make changes ...
git push -u origin feature/my-odh-change
# Create PR: $GITHUB_USER/kserve -> opendatahub-io/kserve (master or release-vX.Y)
```

### 3. Contributing to Downstream (red-hat-data-services/kserve)

```bash
git fetch downstream
git checkout -b feature/my-downstream-change downstream/main
# ... make changes ...
git push -u origin feature/my-downstream-change
# Create PR: $GITHUB_USER/kserve -> red-hat-data-services/kserve (main)
```

---

## Cherry-Pick Workflow Patterns

### Upstream -> Midstream (common pattern)

```bash
git fetch upstream odh
git checkout -b cherrypick-to-odh odh/master

# Cherry-pick specific commits from upstream
git cherry-pick <upstream-commit-sha>

# Or cherry-pick a merged PR's merge commit
MERGE_SHA=$(gh api repos/kserve/kserve/pulls/<PR-NUMBER> | jq -r .merge_commit_sha)
git cherry-pick $MERGE_SHA

git push -u origin cherrypick-to-odh
# Create PR: $GITHUB_USER/kserve -> opendatahub-io/kserve
```

### Midstream -> Downstream

```bash
git fetch odh downstream
git checkout -b cherrypick-to-downstream downstream/main
git cherry-pick <odh-commit-sha>
git push -u origin cherrypick-to-downstream
# Create PR: $GITHUB_USER/kserve -> red-hat-data-services/kserve
```

### Downstream -> Midstream (backport bug fixes)

```bash
git fetch downstream odh
git checkout -b backport-to-odh odh/master
git cherry-pick <downstream-commit-sha>
git push -u origin backport-to-odh
# Create PR: $GITHUB_USER/kserve -> opendatahub-io/kserve
```

---

## Useful Git Aliases

Add these to `~/.gitconfig` to simplify common operations:

```ini
[alias]
    # Fetch all forks
    fall = fetch --all --tags
    
    # Show divergence between forks
    odh-vs-upstream = log upstream/master..odh/master --oneline --first-parent
    downstream-vs-odh = log odh/master..downstream/main --oneline --first-parent
    
    # Find merge commit for a PR
    pr-merge = "!f() { gh api repos/$1/pulls/$2 | jq -r .merge_commit_sha; }; f"
    
    # Cherry-pick from upstream PR
    cp-upstream-pr = "!f() { git cherry-pick $(gh api repos/kserve/kserve/pulls/$1 | jq -r .merge_commit_sha); }; f"
```

---

## Branch Naming Conventions

Use prefixes to indicate the target fork:

| Prefix | Target | Example |
|--------|--------|---------|
| `upstream/` | kserve/kserve | `upstream/fix-validation-bug` |
| `odh/` | opendatahub-io/kserve | `odh/add-authorino-support` |
| `downstream/` | red-hat-data-services/kserve | `downstream/rhods-config` |
| `cp-odh/` | Cherry-pick to ODH | `cp-odh/pr-1234-fix` |
| `cp-downstream/` | Cherry-pick to downstream | `cp-downstream/hotfix-xyz` |

---

## Tracking Cherry-Picks

Create a simple tracking file or use a spreadsheet:

| Upstream PR | Commit SHA | ODH PR | Downstream PR | Notes |
|-------------|------------|--------|---------------|-------|
| kserve#1234 | abc123 | odh#567 | rhods#89 | Critical bugfix |

Consider proposing a label convention (e.g., `cherrypick-approved`, `cherrypicked`)
for tracking cherry-pick status across ODH and downstream repos.

---

## Pro Tips

1. **Always fetch before branching**: `git fetch --all` ensures you're working
   from the latest state.

2. **Use `--first-parent` for cleaner history**: When reviewing merge commits:

   ```bash
   git log odh/master --first-parent --oneline
   ```

3. **Check commit containment**: Before cherry-picking, verify the commit isn't
   already present:

   ```bash
   git branch -a --contains <commit-sha>
   ```

4. **Use `gh` CLI for PR management**:

   ```bash
   # Create PR to specific fork
   gh pr create --repo opendatahub-io/kserve --base master
   ```

5. **Rebase vs merge for cherry-picks**: For single commits, `cherry-pick` is
   cleaner. For multiple commits, consider:

   ```bash
   git rebase --onto odh/master upstream/master~3 upstream/master
   ```

6. **Document the flow**: Keep notes in your PR descriptions about the source of
   cherry-picks (e.g., "Cherry-pick of kserve/kserve#1234").

---

## Git Worktrees

**Always use worktrees for tasks.** Keep the main repo as a clean fetch-only hub.

Benefits:
- No stashing, no WIP commits, no lost work
- Clean task isolation
- Parallel work across forks
- Clear lifecycle: create -> work -> PR merged -> remove

### Task-Based Worktree Workflow

Create a worktree per task, named after the JIRA:

```bash
# Main repo stays clean - primarily for fetching
cd ~/projects/odh-kserve
git fetch --all

# Create worktree for a task, based on the right remote branch
git worktree add ../odh-kserve-RHOAIENG-1234 -b RHOAIENG-1234/fix-validation odh/release-v0.15

# Work in task directory
cd ../odh-kserve-RHOAIENG-1234
# ... make changes, commit, push, create PR ...

# After PR merges, cleanup
cd ~/projects/odh-kserve
git worktree remove ../odh-kserve-RHOAIENG-1234
```

### Directory Structure

```
~/projects/
  odh-kserve/                    # Main repo (fetch-only, no uncommitted changes)
  odh-kserve-RHOAIENG-1234/      # Active task targeting ODH
  odh-kserve-RHOAIENG-5678/      # Active task targeting downstream
  odh-kserve-cp-upstream-9999/   # Cherry-pick to upstream
```

### What's Shared vs. What's Not

**Shared across worktrees:**
- Git object database (`.git` directory)
- Go module cache (`$GOMODCACHE`)
- Docker images
- System tools

**Not shared (must be recreated per worktree):**
- Python virtual environment
- IDE indexing
- Local config files (`.env`, etc.)
- Pre-commit hooks

### Venv Setup

**When opening worktree in Cursor/VS Code**: The "Setup Dev Environment" task runs automatically (`runOn: folderOpen`), creating the venv if missing.

**When creating worktree via terminal** (e.g., agents): Run the setup script manually:

```bash
cd ../odh-kserve-RHOAIENG-1234
.vscode/scripts/setup-dev-env.sh
```

The script:
- Creates venv at `python/kserve/.venv` using `uv`
- Installs test dependencies
- Exits silently if venv already exists
- Use `--force` to recreate

VS Code settings auto-activate the venv in terminals via `python.terminal.activateEnvironment`.

### Listing and Cleaning Worktrees

```bash
# List all worktrees
git worktree list

# Remove a worktree (after PR merged)
git worktree remove ../odh-kserve-RHOAIENG-1234

# Prune stale worktree references
git worktree prune
```

---

## Related Documentation

- [CONTRIBUTING.md](../CONTRIBUTING.md) - ODH contribution guidelines
- [docs/odh/fetch-upstream-release.md](../docs/odh/fetch-upstream-release.md) - Branch cut process

