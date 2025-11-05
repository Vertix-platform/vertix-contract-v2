#!/bin/bash

# Standalone validation script
# Can be run manually or via CI/CD

set -e

BOLD="\033[1m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
RESET="\033[0m"

# Parse arguments
VERBOSE=false
SKIP_TESTS=false
SKIP_COVERAGE=false
COVERAGE_ONLY=false
GAS_REPORT=false

for arg in "$@"; do
    case $arg in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --skip-coverage)
            SKIP_COVERAGE=true
            shift
            ;;
        --coverage-only)
            COVERAGE_ONLY=true
            shift
            ;;
        --gas-report)
            GAS_REPORT=true
            shift
            ;;
        -h|--help)
            echo "Usage: ./scripts/validate.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose        Show verbose output"
            echo "  --skip-tests         Skip running tests"
            echo "  --skip-coverage      Skip coverage check"
            echo "  --coverage-only      Only run coverage check"
            echo "  --gas-report         Generate gas report"
            echo "  -h, --help           Show this help message"
            echo ""
            exit 0
            ;;
    esac
done

echo ""
echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║         🔍 Forge Validation Suite                      ║${RESET}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${RESET}"
echo ""

START_TIME=$(date +%s)
FAILED=0

# Function to print section header
print_section() {
    echo ""
    echo -e "${BOLD}${BLUE}┌────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}${BLUE}│ $1${RESET}"
    echo -e "${BOLD}${BLUE}└────────────────────────────────────────────────────────┘${RESET}"
    echo ""
}

# Function to print success
print_success() {
    echo -e "${GREEN}  ✓ $1${RESET}"
}

# Function to print error
print_error() {
    echo -e "${RED}  ✗ $1${RESET}"
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}  ⚠ $1${RESET}"
}

# Function to print info
print_info() {
    echo -e "${CYAN}  ℹ $1${RESET}"
}

if [ "$COVERAGE_ONLY" = false ]; then
    # 1. Clean build artifacts
    print_section "Cleaning build artifacts"
    forge clean
    print_success "Build artifacts cleaned"

    # 2. Format check
    print_section "Checking code formatting"
    if [ "$VERBOSE" = true ]; then
        forge fmt --check
        FMT_RESULT=$?
    else
        forge fmt --check > /dev/null 2>&1
        FMT_RESULT=$?
    fi

    if [ $FMT_RESULT -eq 0 ]; then
        print_success "Code formatting is correct"
    else
        print_error "Code formatting check failed"
        echo ""
        echo -e "${YELLOW}    Run 'forge fmt' to fix formatting${RESET}"
        FAILED=1
    fi

    # 3. Compilation
    print_section "Compiling contracts"
    if [ "$VERBOSE" = true ]; then
        forge build --sizes
        BUILD_RESULT=$?
    else
        forge build --sizes > /tmp/forge-build.log 2>&1
        BUILD_RESULT=$?
    fi

    if [ $BUILD_RESULT -eq 0 ]; then
        print_success "Compilation successful"

        # Show contract sizes
        if [ "$VERBOSE" = true ]; then
            echo ""
            print_info "Contract sizes:"
            forge build --sizes 2>/dev/null | grep -A 100 "Contract" || true
        fi
    else
        print_error "Compilation failed"
        if [ "$VERBOSE" = false ]; then
            echo ""
            cat /tmp/forge-build.log
        fi
        FAILED=1
    fi

    # 4. Run tests
    if [ "$SKIP_TESTS" = false ] && [ $FAILED -eq 0 ]; then
        print_section "Running tests"

        if [ "$VERBOSE" = true ]; then
            forge test -vvv
            TEST_RESULT=$?
        else
            forge test > /tmp/forge-test.log 2>&1
            TEST_RESULT=$?
        fi

        if [ $TEST_RESULT -eq 0 ]; then
            print_success "All tests passed"

            # Show test summary
            if [ "$VERBOSE" = false ]; then
                echo ""
                grep -E "Suite result:|Ran [0-9]+ test" /tmp/forge-test.log | tail -20 || true
            fi
        else
            print_error "Tests failed"
            if [ "$VERBOSE" = false ]; then
                echo ""
                cat /tmp/forge-test.log
            fi
            FAILED=1
        fi
    elif [ "$SKIP_TESTS" = true ]; then
        print_warning "Skipping tests"
    fi

    # 5. Gas report
    if [ "$GAS_REPORT" = true ] && [ $FAILED -eq 0 ]; then
        print_section "Generating gas report"
        forge test --gas-report > gas-report.txt
        print_success "Gas report saved to gas-report.txt"
    fi
fi

# 6. Coverage
if [ "$SKIP_COVERAGE" = false ] && [ $FAILED -eq 0 ]; then
    print_section "Checking test coverage"

    if [ "$VERBOSE" = true ]; then
        forge coverage
        COV_RESULT=$?
    else
        forge coverage > /tmp/forge-coverage.log 2>&1
        COV_RESULT=$?
    fi

    if [ $COV_RESULT -eq 0 ]; then
        # Extract coverage summary
        TOTAL_LINE=$(grep "Total" /tmp/forge-coverage.log 2>/dev/null || echo "")

        if [ -n "$TOTAL_LINE" ]; then
            print_success "Coverage report generated"
            echo ""
            echo -e "${CYAN}  Coverage Summary:${RESET}"
            echo "$TOTAL_LINE" | awk '{printf "    Lines: %s  Statements: %s  Branches: %s  Functions: %s\n", $2, $3, $4, $5}'

            # Extract percentage (if available)
            COVERAGE_PCT=$(echo "$TOTAL_LINE" | awk '{print $2}' | tr -d '%' || echo "0")
            if [ "${COVERAGE_PCT%.*}" -ge 80 ]; then
                print_success "Coverage meets minimum threshold (80%)"
            else
                print_warning "Coverage below recommended threshold: ${COVERAGE_PCT}%"
            fi
        else
            print_success "Coverage report generated"
        fi

        # Generate lcov report for detailed analysis
        print_info "Generating detailed coverage report..."
        forge coverage --report lcov > /dev/null 2>&1 || true

        if [ -f "lcov.info" ]; then
            print_success "Detailed coverage report saved to lcov.info"
        fi
    else
        print_error "Coverage generation failed"
        if [ "$VERBOSE" = false ]; then
            cat /tmp/forge-coverage.log
        fi
        FAILED=1
    fi
elif [ "$SKIP_COVERAGE" = true ]; then
    print_warning "Skipping coverage check"
fi

# 7. Gas snapshot
if [ "$COVERAGE_ONLY" = false ] && [ $FAILED -eq 0 ]; then
    print_section "Checking gas snapshot"

    if [ -f ".gas-snapshot" ]; then
        forge snapshot --check > /tmp/gas-diff.log 2>&1 || true

        if [ -s /tmp/gas-diff.log ]; then
            print_warning "Gas usage has changed"
            echo ""
            head -20 /tmp/gas-diff.log
        else
            print_success "Gas usage unchanged"
        fi
    else
        print_info "Creating initial gas snapshot..."
        forge snapshot
        print_success "Gas snapshot created"
    fi
fi

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Final summary
echo ""
echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${RESET}"

if [ $FAILED -eq 0 ]; then
    echo -e "${BOLD}${GREEN}║  ✓ All validation checks passed!                       ║${RESET}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "${CYAN}  Duration: ${DURATION}s${RESET}"
    echo ""
    exit 0
else
    echo -e "${BOLD}${RED}║  ✗ Validation failed!                                   ║${RESET}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "${CYAN}  Duration: ${DURATION}s${RESET}"
    echo ""
    exit 1
fi
