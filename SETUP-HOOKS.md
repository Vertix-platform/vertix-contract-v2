# Quick Setup Guide for Git Hooks

## One-Command Installation

```bash
chmod +x scripts/install-hooks.sh && ./scripts/install-hooks.sh
```

This will:
- Configure git to use custom hooks
- Make all scripts executable
- Create configuration file
- Show current settings

## What You Get

### Pre-Commit Hook
Runs on `git commit`:
- Auto-formats your Solidity code
- Checks if code compiles
- Warns about console.log imports
- Flags TODO comments

### Pre-Push Hook
Runs on `git push`:
- Validates code formatting
- Builds all contracts
- Runs full test suite
- Checks test coverage (minimum 80%)
- Compares gas usage

## Configuration

Edit `.forge-hooks.json` to customize:

```json
{
  "autoFormat": true,        // Auto-format on commit
  "skipTests": false,         // Skip tests on push
  "skipCoverage": false,      // Skip coverage check
  "minCoverage": 80           // Minimum coverage %
}
```

## Usage

### Normal workflow
```bash
git add .
git commit -m "feat: add feature"  # pre-commit runs
git push origin main               # pre-push runs
```

### Skip hooks (when needed)
```bash
git commit --no-verify -m "WIP"
git push --no-verify origin main
```

### Run checks manually
```bash
./scripts/validate.sh           # Full validation
./scripts/validate.sh -v        # Verbose output
./scripts/validate.sh --help    # Show all options
```

## Manual Setup (if script fails)

```bash
# 1. Make scripts executable
chmod +x scripts/install-hooks.sh
chmod +x scripts/validate.sh
chmod +x .githooks/pre-commit
chmod +x .githooks/pre-push

# 2. Configure git
git config core.hooksPath .githooks

# 3. Done!
```

## Current Test Status

**Note**: Your tests are currently failing (38 failed out of 344). You should fix these before enabling pre-push hooks, or temporarily configure:

```json
{
  "skipTests": true,
  "skipCoverage": true
}
```
