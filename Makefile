
.PHONY: help install test build coverage validate fmt clean snapshot

help:
	@echo ""
	@echo "╔════════════════════════════════════════════════════════╗"
	@echo "║         Vertix Contract - Development Tasks           ║"
	@echo "╚════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Setup:"
	@echo "  make install          Install git hooks"
	@echo ""
	@echo "Development:"
	@echo "  make fmt              Format all Solidity files"
	@echo "  make build            Compile contracts"
	@echo "  make test             Run all tests"
	@echo "  make test-v           Run tests with verbose output"
	@echo "  make coverage         Generate coverage report"
	@echo "  make snapshot         Update gas snapshot"
	@echo ""
	@echo "Validation:"
	@echo "  make validate         Run all validation checks"
	@echo "  make validate-v       Run validation with verbose output"
	@echo "  make check            Quick check (fmt + build)"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean            Clean build artifacts"
	@echo "  make clean-all        Clean everything (including deps)"
	@echo ""

install:
	@echo "Installing git hooks..."
	@chmod +x scripts/install-hooks.sh
	@chmod +x scripts/validate.sh
	@chmod +x .githooks/pre-commit
	@chmod +x .githooks/pre-push
	@./scripts/install-hooks.sh

fmt:
	@echo "Formatting Solidity files..."
	@forge fmt

fmt-check:
	@echo "Checking formatting..."
	@forge fmt --check

build:
	@echo "Building contracts..."
	@forge build

build-sizes:
	@echo "Building contracts with size report..."
	@forge build --sizes

test:
	@echo "Running tests..."
	@forge test

test-v:
	@echo "Running tests (verbose)..."
	@forge test -vvv

test-vv:
	@echo "Running tests (very verbose)..."
	@forge test -vvvv

test-match:
	@echo "Running specific test..."
	@forge test --match-test $(TEST) -vvv

# Coverage
coverage:
	@echo "Generating coverage report..."
	@forge coverage

coverage-report:
	@echo "Generating detailed coverage report..."
	@forge coverage --report lcov
	@echo "Coverage report saved to lcov.info"

# Gas
snapshot:
	@echo "Updating gas snapshot..."
	@forge snapshot

snapshot-check:
	@echo "Checking gas snapshot..."
	@forge snapshot --check

snapshot-diff:
	@echo "Comparing gas snapshot..."
	@forge snapshot --diff

gas-report:
	@echo "Generating gas report..."
	@forge test --gas-report | tee gas-report.txt

# Validation
validate:
	@chmod +x scripts/validate.sh
	@./scripts/validate.sh

validate-v:
	@chmod +x scripts/validate.sh
	@./scripts/validate.sh -v

check: fmt-check build
	@echo "✓ Quick check passed!"

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@forge clean

clean-all: clean
	@echo "Cleaning all generated files..."
	@rm -f lcov.info gas-report.txt
	@rm -f .gas-snapshot
	@rm -rf coverage/

# Deployment helpers
deploy-local:
	@echo "Deploying to local network..."
	@forge script script/Deploy.s.sol --rpc-url localhost --broadcast

deploy-testnet:
	@echo "Deploying to testnet..."
	@forge script script/Deploy.s.sol --rpc-url $(RPC_URL) --broadcast --verify

update:
	@echo "Updating dependencies..."
	@forge update

docs:
	@echo "Generating documentation..."
	@forge doc

verify:
	@echo "Verifying contract on Etherscan..."
	@forge verify-contract $(CONTRACT) $(ADDRESS) --chain $(CHAIN)

hooks-install: install

hooks-uninstall:
	@echo "Uninstalling git hooks..."
	@git config --unset core.hooksPath

ci: validate coverage
	@echo "✓ CI checks passed!"
