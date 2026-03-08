# CONVENTIONS.md — Code Style & Patterns

## Language & Style

- **Go 1.25.4** with workspaces (`go.work`)
- Standard `gofmt`/`goimports` formatting
- Lint via `golangci-lint` (see `make lint`)

## Import Organization

Imports follow three groups, separated by blank lines:
1. Standard library
2. External packages
3. Internal packages (`github.com/e2b-dev/infra/packages/...`)

Alias imports used for clarity:
```go
sqlcdb "github.com/e2b-dev/infra/packages/db/client"
```

## Naming Conventions

### Packages
- Lowercase, single word: `sandbox`, `network`, `storage`, `telemetry`
- Internal code in `internal/`, public APIs in `pkg/`

### Types
- **Structs**: PascalCase, descriptive (`APIStore`, `SandboxManager`, `CgroupManager`)
- **Interfaces**: Small and focused, often end with `-er`/`-or` or are nouns (`StorageProvider`, `Blob`, `Seekable`, `Template`)
- **Constants**: `CamelCase` for exported, `camelCase` for unexported; some use `SCREAMING_SNAKE_CASE`

### Functions & Methods
- **Constructors**: `New*` pattern returning initialized structs (`NewAPIStore()`, `NewCgroup2Manager()`)
- **Method receivers**: Single character pointer receivers (`s *Server`, `m *Manager`)
- **Getters**: `Get*` prefix for safe concurrent access

### Variables
- `camelCase`, descriptive names
- `ctx` for context, `err` for errors (standard Go conventions)

## Function Signatures

### Context-first, error-last
```go
func (s *Server) Create(ctx context.Context, req *Request) (*Response, error)
```

### Early returns on error
```go
if err != nil {
    return nil, fmt.Errorf("creating sandbox: %w", err)
}
```

### Pointer receivers consistently
```go
func (s *Server) HandleRequest(ctx context.Context) error { ... }
```

## Error Handling

### Wrapping with context
```go
return fmt.Errorf("failed to create sandbox %s: %w", id, err)
```

### Custom error types
`packages/shared/pkg/apierrors/apierrors.go` — `APIError` struct wraps errors with HTTP status codes and client-facing messages.

### Error checking
```go
if errors.Is(err, ErrNotFound) { ... }
```

### Fatal errors
```go
logger.L().Fatal(ctx, "critical failure", zap.Error(err))
```

### No panics
Error flow uses explicit returns throughout; `panic` is avoided in production code.

## Struct Patterns

### Config structs for initialization
```go
type Config struct {
    Port    int
    Timeout time.Duration
    Logger  *zap.Logger
}
```

### Composition over inheritance
Embedded structs for shared behavior:
```go
type SandboxManager struct {
    *Config
    cache  *Cache
    mu     sync.RWMutex
}
```

### Mutex protection for concurrent access
```go
type Metadata struct {
    mu   sync.RWMutex
    data map[string]string
}
```

## Interface Patterns

### Small and focused (1-3 methods)
```go
type Blob interface {
    Read(ctx context.Context) ([]byte, error)
}

type SeekableReader interface {
    ReadAt(ctx context.Context, offset int64, length int64) ([]byte, error)
}
```

### Composed interfaces
```go
type Seekable interface {
    SeekableReader
    SeekableWriter
    StreamingReader
}
```

### Mock-friendly design
Interfaces generated into mocks via mockery (`.mockery.yaml`).

## Concurrency Patterns

### errgroup for coordinated goroutines
```go
g, ctx := errgroup.WithContext(ctx)
g.Go(func() error { ... })
if err := g.Wait(); err != nil { ... }
```

### sync.WaitGroup for simple fan-out
### Atomic values for flags
```go
var draining atomic.Bool
```

### Channel-based coordination for cross-service communication

## Graceful Shutdown Pattern

Used consistently across all services:
1. Signal handling with `context.WithCancel`
2. Draining phase — return 503 from health checks
3. Delay for load balancer propagation (15s in non-local)
4. Ordered resource cleanup via `closer` structs
5. WaitGroup coordination for goroutines

## Logging

### Structured logging with Zap + OTEL
```go
logger.L().Info(ctx, "sandbox created",
    zap.String("sandbox_id", id),
    zap.Duration("elapsed", elapsed),
)
```

- Always pass `ctx` to logger methods for trace correlation
- Use `zap.Error(err)` for error fields
- Logger injected, not global

## Telemetry

- OpenTelemetry for traces, metrics, and logs
- Central `telemetry.Client` injected into services
- Custom meters for performance tracking
- pprof server on dedicated port

## Configuration

- Struct-based config, not globals
- Environment variables loaded from `.env.{prod,staging,dev}`
- Secrets via GCP Secrets Manager (production)
- Feature flags via LaunchDarkly

## Code Generation

- **Proto/gRPC**: `make generate/orchestrator`, `make generate/shared`
- **OpenAPI**: `oapi-codegen` → `*.gen.go` files
- **SQL**: `sqlc` → type-safe DB code from `queries/*.sql`
- **Mocks**: `mockery` → `mocks/` directories from `.mockery.yaml`

## Lint Suppressions

Occasionally used with justification:
```go
//nolint:contextcheck  // middleware handles context differently
```
