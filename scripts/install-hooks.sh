#!/bin/bash

# Installation script for git hooks
# Similar to Husky's installation process

set -e

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
RESET="\033[0m"

echo ""
echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║         🔧 Installing Git Hooks                        ║${RESET}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${RESET}"
echo ""

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo -e "${YELLOW}⚠️  Not a git repository. Skipping hook installation.${RESET}"
    exit 0
fi

# Check if forge is installed
if ! command -v forge &> /dev/null; then
    echo -e "${YELLOW}⚠️  Foundry (forge) not found. Please install Foundry first:${RESET}"
    echo -e "${YELLOW}   curl -L https://foundry.paradigm.xyz | bash${RESET}"
    echo -e "${YELLOW}   foundryup${RESET}"
    exit 1
fi

echo -e "${BLUE}📦 Setting up git hooks directory...${RESET}"

# Configure git to use custom hooks directory
git config core.hooksPath .githooks

echo -e "${GREEN}✓ Git hooks directory configured${RESET}"
echo ""

# Make hook scripts executable
echo -e "${BLUE}🔐 Making hook scripts executable...${RESET}"

if [ -f ".githooks/pre-commit" ]; then
    chmod +x .githooks/pre-commit
    echo -e "${GREEN}✓ pre-commit hook enabled${RESET}"
fi

if [ -f ".githooks/pre-push" ]; then
    chmod +x .githooks/pre-push
    echo -e "${GREEN}✓ pre-push hook enabled${RESET}"
fi

if [ -f "scripts/validate.sh" ]; then
    chmod +x scripts/validate.sh
    echo -e "${GREEN}✓ validation script enabled${RESET}"
fi

echo ""

# Create default config if it doesn't exist
if [ ! -f ".forge-hooks.json" ]; then
    echo -e "${BLUE}📝 Creating default configuration...${RESET}"
    cat > .forge-hooks.json << 'EOF'
{
  "autoFormat": true,
  "skipTests": false,
  "skipCoverage": false,
  "skipGasSnapshot": false,
  "skipBuildOnCommit": false,
  "minCoverage": 80
}
EOF
    echo -e "${GREEN}✓ Configuration file created: .forge-hooks.json${RESET}"
    echo ""
fi

# Show configuration
echo -e "${BOLD}${CYAN}Current Configuration:${RESET}"
echo ""
cat .forge-hooks.json | while read line; do
    echo -e "${CYAN}  $line${RESET}"
done
echo ""

# Success message
echo -e "${BOLD}${GREEN}✓ Git hooks installed successfully!${RESET}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}What happens now:${RESET}"
echo ""
echo -e "${GREEN}  pre-commit:${RESET}  Auto-formats code and checks compilation"
echo -e "${GREEN}  pre-push:${RESET}    Runs full test suite, coverage, and gas checks"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Useful commands:${RESET}"
echo ""
echo -e "  ${YELLOW}./scripts/validate.sh${RESET}         Run all checks manually"
echo -e "  ${YELLOW}./scripts/validate.sh -v${RESET}      Run with verbose output"
echo -e "  ${YELLOW}./scripts/validate.sh --help${RESET}  Show all options"
echo ""
echo -e "  ${YELLOW}git commit --no-verify${RESET}        Skip pre-commit hook"
echo -e "  ${YELLOW}git push --no-verify${RESET}          Skip pre-push hook"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Configuration:${RESET}"
echo ""
echo -e "  Edit ${YELLOW}.forge-hooks.json${RESET} to customize behavior"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
