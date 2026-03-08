# CONCERNS.md — Technical Debt & Issues

## Active Engineering Tickets in Code

### ENG-3544: Snapshot query scoping
- **Location**: `packages/api/internal/handlers/`
- **Issue**: Snapshot queries not scoped by `teamID` for ownership validation
- **Risk**: Requires post-fetch ownership checks; potential data leakage if checks missed
- **Priority**: Medium — security-relevant

### ENG-3469: Build status migration
- **Location**: `packages/api/internal/`
- **Issue**: Pending migration from `dbtypes.BuildStatusPending` to `types.BuildStatusReady`
- **Risk**: Multiple services still using old enum values; inconsistent state
- **Priority**: Medium — consistency issue

### ENG-3514: Sandbox state management migration
- **Location**: `packages/api/internal/sandbox/store.go`
- **Issue**: Migration from in-memory to Redis-backed state management
- **Risk**: Dual-path code present; both old and new paths active
- **Priority**: Medium — complexity and potential state inconsistency

## Technical Debt

### Legacy envd RPC compatibility layer
- **Location**: `packages/envd/internal/services/legacy/`
- **Description**: Backward-compatible interceptors and conversion utilities between old/new RPC protocols
- **Impact**: Extra code paths to maintain; increases test surface
- **Recommendation**: Remove once all clients migrate to new protocol

### Large generated files
- **File**: `packages/api/internal/api/api.gen.go` (~12,091 lines)
- **Impact**: Slow IDE performance, hard to review in PRs
- **Mitigation**: Already gitignored from review; regenerated via `make generate/api`

### Complex single files
- **File**: `packages/orchestrator/internal/sandbox/sandbox.go` (~1,288 lines)
- **File**: `packages/orchestrator/cmd/resume-build/main.go` (~1,405 lines)
- **Impact**: High cognitive load; difficult to test individual pieces
- **Recommendation**: Consider decomposing into smaller, focused files

### Lint suppressions
- **Location**: `packages/api/main.go:85,92`
- **Suppression**: `//nolint:contextcheck` on middleware setup
- **Impact**: Context handling in middleware may not follow standard patterns

## Security Considerations

### Authentication layers
- JWT via Supabase for user auth
- API keys for programmatic access
- Admin tokens for internal operations
- **Concern**: Multiple auth paths increase attack surface; ensure all paths validated consistently

### Firecracker VM isolation
- Orchestrator requires **sudo/root** to run (Firecracker requirement)
- VM networking uses `iptables` and Linux `netlink`
- **Concern**: Root-level operations require careful input validation to prevent privilege escalation

### Secret management
- Production secrets in GCP Secrets Manager
- Local development uses `.env.*` files
- **Concern**: `.env.*` files must stay gitignored; template exists as `.env.template`

## Performance Considerations

### Database connection pooling
- PostgreSQL max 40 connections configured
- **Concern**: Under heavy load, connection exhaustion possible; monitor pool utilization

### Storage chunk sizing
- 4MB chunks for cloud storage operations
- **Concern**: Fixed chunk size may not be optimal for all workloads (small files over-allocate, large files under-utilize)

### Template caching
- Redis-backed with peer-to-peer registry
- GCS bucket for persistent storage
- **Concern**: Cache invalidation complexity; stale templates could cause VM issues

### gRPC multiplexing
- CMux reuses single TCP port for HTTP and gRPC
- **Concern**: Single-port approach means one protocol's issues can affect the other

## Fragile Areas

### Graceful shutdown ordering
- **Location**: All service `main.go` files
- **Issue**: Background goroutine management during shutdown is noted as incomplete (api/main.go comments)
- **Risk**: Orphaned goroutines during shutdown could cause data loss or hung connections

### Network Block Device (NBD) management
- **Location**: `packages/orchestrator/internal/sandbox/nbd/`
- **Issue**: Low-level kernel interface; errors hard to diagnose
- **Risk**: NBD connection failures can leave VMs in inconsistent state

### VM networking
- **Location**: `packages/orchestrator/internal/sandbox/network/`
- **Issue**: Direct `iptables` and `netlink` manipulation
- **Risk**: Race conditions in network setup/teardown under concurrent VM operations

## Test Coverage Gaps

### Integration test scope
- Integration tests exist in `tests/integration/` but are a separate module
- **Gap**: Not all service interactions tested end-to-end
- **Gap**: Firecracker-dependent tests require specialized infrastructure (not in CI)

### Orchestrator testing
- Core sandbox management is complex (~1.3k lines)
- **Gap**: Requires root/sudo for real Firecracker testing
- **Gap**: Network and NBD subsystems difficult to unit test in isolation

### Client proxy testing
- Edge routing and service discovery logic
- **Gap**: Consul-dependent behavior hard to test without real Consul

## Monitoring & Observability

### Current state
- OpenTelemetry traces, metrics, and logs configured
- Grafana stack (Loki, Tempo, Mimir) for visualization
- pprof for profiling
- **Strength**: Good observability foundation

### Gaps
- Custom alerting rules not visible in codebase
- No structured error tracking service (e.g., Sentry) visible
- Health check endpoints exist but monitoring of check results not evident in code
