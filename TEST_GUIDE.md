## Running Tests

### **Run All Tests**
```bash
forge test -vvv
```

### **Run Specific Test File**
```bash
forge test --match-path test/unit/RoleManager.t.sol -vvv
forge test --match-path test/unit/FeeDistributor.t.sol -vvv
forge test --match-path test/unit/NFTMarketplace.t.sol -vvv
forge test --match-path test/EscrowManager.t.sol -vvv
```

### **Run Specific Test Function**
```bash
forge test --match-test test_createListing_Success -vvv
```

### **Run With Gas Report**
```bash
forge test --gas-report
```

### **Run With Coverage**
```bash
forge coverage
forge coverage --report lcov
```

### **Generate Coverage Report (HTML)**
```bash
forge coverage --report lcov
genhtml lcov.info -o coverage
open coverage/index.html
```


## Test Checklist (Per Contract)

### **For Each Contract, Test:**

#### **Constructor**
- [ ] Valid parameters
- [ ] Invalid parameters (revert cases)
- [ ] Initial state correct

#### **Main Functions**
- [ ] Happy path (success case)
- [ ] Revert conditions (all error cases)
- [ ] Access control (unauthorized callers)
- [ ] Edge cases (zero values, max values)
- [ ] State changes correct
- [ ] Events emitted correctly

#### **View Functions**
- [ ] Return correct values
- [ ] Work with empty state
- [ ] Work with populated state

#### **Admin Functions**
- [ ] Only authorized can call
- [ ] Parameters validated
- [ ] State updated correctly

#### **Integration**
- [ ] Works with other contracts
- [ ] Handles failed external calls
- [ ] Reentrancy protection

---

## Useful Test Commands

### **Debugging Failed Tests**
```bash
# Run with maximum verbosity
forge test --match-test testName -vvvvv

# Show stack traces
forge test --match-test testName --show-stack-traces

# Run specific test with debug
forge test --match-test testName --debug
```

### **Gas Optimization**
```bash
# Generate gas snapshot
forge snapshot

# Compare gas usage
forge snapshot --diff

# Show gas usage per function
forge test --gas-report --match-contract YourContract
```

### **Watch Mode**
```bash
# Re-run tests on file changes
forge test --watch
```



### **Short-Term (Improve Coverage)**
5. Add VerificationRegistry tests
6. Add ReputationManager tests
7. Add NFT contract tests
8. Add integration tests

### **Long-Term (Advanced Testing)**
9. Add invariant tests
10. Add property-based tests
11. Gas optimization testing
12. Upgrade testing (if using proxies)
