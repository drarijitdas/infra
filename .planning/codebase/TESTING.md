# TESTING.md — Test Framework & Patterns

## Frameworks & Tools

| Tool | Purpose | Version/Source |
|------|---------|----------------|
| `testing` | Standard Go test runner | Built-in |
| `testify/assert` | Soft assertions (test continues) | `github.com/stretchr/testify` |
| `testify/require` | Hard assertions (test stops) | `github.com/stretchr/testify` |
| `testify/mock` | Mock objects | `github.com/stretchr/testify` |
| `mockery` | Interface mock generation | v3.5.0 (`.mockery.yaml`) |
| `testcontainers-go` | Docker containers for tests | Real PostgreSQL in tests |
| `-race` flag | Race condition detection | Standard Go toolchain |

## Test Structure

### File Location
- Unit tests: `*_test.go` alongside source code
- Integration tests: `tests/integration/` (separate Go module)
- Test utilities: `packages/db/pkg/testutils/`

### Test Function Pattern
```go
func TestFunctionName(t *testing.T) {
    t.Parallel()  // Enable parallel execution

    // Arrange
    store := NewTestStore(t)

    // Act
    result, err := store.Create(ctx, input)

    // Assert
    require.NoError(t, err)
    assert.Equal(t, expected, result.Name)
}
```

### Subtests
```go
func TestSandbox(t *testing.T) {
    t.Run("creates successfully", func(t *testing.T) {
        t.Parallel()
        // ...
    })

    t.Run("returns error on invalid input", func(t *testing.T) {
        t.Parallel()
        // ...
    })
}
```

## Mock Generation

### Configuration (`.mockery.yaml`)
```yaml
# Root-level mockery config
# Generates mocks for interfaces across packages
```

**Mocked interfaces include:**
- `FilesystemHandler`, `ChunkServiceClient`, `StorageProvider`
- `Blob`, `Seekable`, `SeekableReader`
- `Template`, `File`, `Cache`
- `DiffCreator`, `MemoryBackend`, `Manager`

### Generated Mock Location
- Package-specific `mocks/` directories
- File naming: `mock<InterfaceName>.go`

### Mock Usage
```go
mockStore := mocks.NewMockStorageProvider(t)
mockStore.EXPECT().Get(ctx, key).Return(data, nil)

svc := NewService(mockStore)
result, err := svc.Process(ctx, key)

require.NoError(t, err)
mockStore.AssertExpectations(t)
```

### Regenerating Mocks
```bash
make generate-mocks
```

## Integration Testing

### Location
`tests/integration/` — separate Go module with own `go.mod`

### Test Database Setup
Uses `testcontainers-go` for real PostgreSQL:
```go
// packages/db/pkg/testutils/
func SetupDatabase(t *testing.T) *Database {
    // Spins up PostgreSQL container
    // Runs migrations with goose
    // Returns SqlcClient, AuthDb, TestQueries
}
```

### API Client Setup
```go
db := setup.GetTestDBClient(t)
c := setup.GetAPIClient()
utils.SetupSandboxWithCleanup(t, c)
```

### Async Assertions
Polling with timeout for eventually-consistent operations:
```go
require.Eventually(t, func() bool {
    status, err := client.GetStatus(ctx, id)
    return err == nil && status == "ready"
}, 30*time.Second, 500*time.Millisecond, "sandbox should become ready")
```

### Cleanup
```go
t.Cleanup(func() {
    // Tear down resources
    container.Terminate(ctx)
})
```

## Running Tests

### All unit tests
```bash
make test
# Runs: go test -race ./...
```

### Integration tests
```bash
make test-integration
```

### Single package
```bash
cd packages/<package>
go test -race -v ./internal/handlers
```

### Specific test
```bash
go test -race -v -run TestCreateSandbox ./internal/handlers
```

### Skip expensive tests
```go
if testing.Short() {
    t.Skip("skipping expensive test in short mode")
}
```
```bash
go test -short ./...
```

## Test Patterns

### Assertions
- `require.*` — stops test immediately on failure (use for preconditions)
- `assert.*` — continues test on failure (use for verification)
- Common: `NoError`, `Equal`, `NotNil`, `True`, `Contains`, `Len`

### Parallel Execution
- Tests marked with `t.Parallel()` run concurrently
- Used throughout for faster test execution
- Requires tests to be independent (no shared mutable state)

### Race Detection
- All tests run with `-race` flag by default
- Catches concurrent access violations at test time
- Orchestrator has `make run-debug` for race-detected development runs

### Table-Driven Tests
```go
tests := []struct {
    name     string
    input    Input
    expected Output
    wantErr  bool
}{
    {"valid input", Input{...}, Output{...}, false},
    {"empty name", Input{Name: ""}, Output{}, true},
}

for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
        t.Parallel()
        result, err := Process(tt.input)
        if tt.wantErr {
            require.Error(t, err)
            return
        }
        require.NoError(t, err)
        assert.Equal(t, tt.expected, result)
    })
}
```

## CI/CD Test Pipelines

- `.github/workflows/pr-tests.yml` — runs on PRs
- `.github/workflows/integration_tests.yml` — integration test suite
- Tests must pass before merge
