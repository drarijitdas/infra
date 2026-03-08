# Architecture

**Analysis Date:** 2026-03-08

## Pattern Overview

**Overall:** Distributed microservices with multi-tier orchestration

**Key Characteristics:**
- Go workspace monorepo with independent service packages communicating via gRPC
- API layer handles REST requests, delegates VM lifecycle to orchestrator nodes via gRPC
- Client-proxy routes sandbox traffic to the correct orchestrator using Redis-backed catalog
- Firecracker microVMs provide sandboxed execution; envd daemon runs inside each VM
- Infrastructure managed by Terraform + Nomad on GCP (AWS support in progress)

## Layers

**Edge / Routing Layer:**
- Purpose: Route client HTTP/WS traffic to the correct orchestrator hosting a sandbox
- Location: `packages/client-proxy/`
- Contains: Reverse proxy, sandbox catalog lookup, paused sandbox auto-resume
- Depends on: Redis (sandbox catalog), API (gRPC for pause/resume), feature flags
- Used by: External SDK clients connecting to running sandboxes

**API Layer:**
- Purpose: REST API for sandbox CRUD, template management, team auth, billing analytics
- Location: `packages/api/`
- Contains: OpenAPI-generated handlers, auth middleware, orchestrator client, placement logic
- Depends on: PostgreSQL (sqlc), Redis, ClickHouse, orchestrator nodes (gRPC), Supabase (auth)
- Used by: E2B SDK clients, dashboard frontend, client-proxy (gRPC)

**Dashboard API Layer:**
- Purpose: Internal dashboard REST API for team/usage analytics
- Location: `packages/dashboard-api/`
- Contains: OpenAPI-generated handlers using Gin, separate auth flow
- Depends on: PostgreSQL, ClickHouse, auth DB
- Used by: E2B dashboard frontend

**Orchestrator Layer:**
- Purpose: Manage Firecracker VM lifecycle, networking, storage, template caching
- Location: `packages/orchestrator/`
- Contains: gRPC server, sandbox factory, network/NBD pools, template cache, proxy, NFS proxy, hyperloop server, TCP firewall
- Depends on: Firecracker, Redis, ClickHouse, GCS/S3 (template storage), feature flags
- Used by: API layer (gRPC client), client-proxy (HTTP proxy passthrough)

**In-VM Daemon Layer (envd):**
- Purpose: Process and filesystem management inside each Firecracker VM
- Location: `packages/envd/`
- Contains: Connect RPC services for process/filesystem operations, cgroup management, port forwarding
- Depends on: Host MMDS (metadata), cgroups v2
- Used by: SDK clients (via proxy chain), orchestrator (health checks)

**Shared Libraries:**
- Purpose: Cross-cutting concerns reused across services
- Location: `packages/shared/pkg/`
- Contains: gRPC definitions, telemetry, logging, storage providers, Redis helpers, feature flags, event delivery, sandbox catalog, middleware
- Depends on: Various cloud SDKs, OpenTelemetry, Zap, Redis
- Used by: All service packages

**Database Layer:**
- Purpose: PostgreSQL schema, migrations, and generated query code
- Location: `packages/db/`
- Contains: SQL migrations (goose), sqlc queries, auth DB client, connection pooling
- Depends on: PostgreSQL
- Used by: API, dashboard-api

**Auth Package:**
- Purpose: Shared authentication logic (API keys, access tokens, Supabase JWT)
- Location: `packages/auth/`
- Contains: Authenticator interface implementations, team/user types
- Depends on: Database layer
- Used by: API, dashboard-api

**Analytics Layer:**
- Purpose: Event ingestion and time-series analytics
- Location: `packages/clickhouse/`
- Contains: ClickHouse driver, event batchers, host stats collectors, migrations
- Depends on: ClickHouse
- Used by: API, orchestrator

## Data Flow

**Sandbox Creation:**

1. SDK client sends POST `/sandboxes` to API
2. API authenticates via API key/JWT, validates team quotas
3. API resolves template build from DB (PostgreSQL via sqlc)
4. Placement algorithm (`packages/api/internal/orchestrator/placement/`) selects an orchestrator node based on available resources and CPU platform
5. API sends gRPC `CreateSandbox` to chosen orchestrator (`packages/api/internal/orchestrator/create_instance.go`)
6. Orchestrator acquires network slot from pool, NBD device from pool, loads template from cache
7. Orchestrator starts Firecracker VM via FC client (`packages/orchestrator/internal/sandbox/fc/`)
8. Envd boots inside VM, exposes Connect RPC on port 49983
9. Orchestrator registers sandbox in Redis catalog for client-proxy routing
10. Orchestrator publishes sandbox event to ClickHouse + Redis streams

**Client Proxy Request Routing:**

1. Client connects to `sandbox-id.e2b.dev` (or custom domain)
2. Client-proxy extracts sandbox ID from hostname
3. Looks up orchestrator IP/ID from Redis sandbox catalog (`packages/shared/pkg/sandbox-catalog/`)
4. If sandbox is paused and auto-resume is enabled, calls API gRPC to resume
5. Proxies HTTP/WS request to orchestrator's sandbox proxy port
6. Orchestrator's sandbox proxy (`packages/orchestrator/internal/proxy/`) routes to the correct VM

**Template Build:**

1. API receives build request, creates DB record
2. API calls orchestrator's template manager via gRPC (`packages/shared/pkg/grpc/template-manager/`)
3. Template manager (`packages/orchestrator/internal/template/server/`) starts a Firecracker VM with the base image
4. Build commands run inside VM via envd
5. Diff/snapshot of filesystem is created (`packages/orchestrator/internal/sandbox/diffcreator.go`)
6. Build artifacts uploaded to GCS/S3 (`packages/shared/pkg/storage/`)
7. Build status updated in DB

**State Management:**
- PostgreSQL: Persistent state (teams, templates, builds, snapshots, volumes)
- Redis: Ephemeral state (sandbox catalog, event streams, template peer registry, feature flag cache)
- ClickHouse: Analytics events (sandbox lifecycle, host stats, billing)
- In-memory: Sandbox map on each orchestrator (`packages/orchestrator/internal/sandbox/map.go`), template cache, network/NBD pools

## Key Abstractions

**APIStore (API handler aggregate):**
- Purpose: Central struct implementing the OpenAPI ServerInterface; holds all dependencies
- Examples: `packages/api/internal/handlers/store.go`
- Pattern: All HTTP handlers are methods on `APIStore`, which satisfies the generated `api.ServerInterface`

**SandboxFactory (orchestrator):**
- Purpose: Creates sandbox instances with all required resources (network, storage, cgroup)
- Examples: `packages/orchestrator/internal/sandbox/sandbox.go`, `packages/orchestrator/internal/sandbox/build/`
- Pattern: Factory pattern combining network pool, NBD device pool, cgroup manager, feature flags

**Template Cache:**
- Purpose: In-memory cache of template disk images with peer-to-peer sharing between orchestrator nodes
- Examples: `packages/orchestrator/internal/sandbox/template/`
- Pattern: TTL-based cache with Redis peer registry for cross-node template fetching

**SandboxesCatalog:**
- Purpose: Registry mapping sandbox IDs to orchestrator locations for request routing
- Examples: `packages/shared/pkg/sandbox-catalog/catalog.go`
- Pattern: Interface with Redis implementation (`catalog_redis.go`) and in-memory fallback (`catalog_memory.go`)

**Event Delivery:**
- Purpose: Fan-out sandbox lifecycle events to multiple backends
- Examples: `packages/shared/pkg/events/delivery.go`
- Pattern: Generic `Delivery[Payload]` interface with Redis streams and ClickHouse implementations

**Placement Algorithm:**
- Purpose: Choose optimal orchestrator node for new sandbox placement
- Examples: `packages/api/internal/orchestrator/placement/placement.go`
- Pattern: Strategy interface `Algorithm` with retry logic and node exclusion

**Storage Provider:**
- Purpose: Abstract cloud storage for template artifacts (GCS, S3, local)
- Examples: `packages/shared/pkg/storage/storage.go`
- Pattern: Provider interface with environment-based selection (GCP default, AWS, local)

**Clusters Pool:**
- Purpose: Manage multiple orchestrator clusters with node discovery and resource tracking
- Examples: `packages/api/internal/clusters/`
- Pattern: Periodic sync of cluster state from DB, gRPC connections to orchestrator nodes

## Entry Points

**API Service:**
- Location: `packages/api/main.go`
- Triggers: HTTP requests on port 80, gRPC on configurable port
- Responsibilities: REST API, OpenAPI validation, auth, sandbox/template CRUD, gRPC proxy service for client-proxy

**Orchestrator Service:**
- Location: `packages/orchestrator/main.go`
- Triggers: gRPC calls from API, HTTP health checks
- Responsibilities: VM lifecycle, template caching, sandbox proxy, NFS proxy, hyperloop server, TCP firewall
- Note: Runs multiple sub-services selected via `cfg.GetServices()` (orchestrator, template-manager)

**Envd (in-VM daemon):**
- Location: `packages/envd/main.go`
- Triggers: Connect RPC calls on port 49983 from SDK clients (via proxy chain)
- Responsibilities: Process management, filesystem operations, port forwarding, cgroup resource control

**Client Proxy:**
- Location: `packages/client-proxy/main.go`
- Triggers: HTTP/WS connections from SDK clients
- Responsibilities: Route traffic to correct orchestrator, handle paused sandbox resume

**Dashboard API:**
- Location: `packages/dashboard-api/main.go`
- Triggers: HTTP requests from dashboard frontend
- Responsibilities: Team analytics, usage data, admin operations

**Docker Reverse Proxy:**
- Location: `packages/docker-reverse-proxy/main.go`
- Triggers: Docker registry API requests
- Responsibilities: Proxy Docker image pulls with auth and caching

**CLI Utilities:**
- Location: `packages/orchestrator/cmd/`
- Contains: `clean-nfs-cache/`, `copy-build/`, `create-build/`, `inspect-build/`, `mount-build-rootfs/`, `resume-build/`, `show-build-diff/`, `simulate-gcs-traffic/`, `simulate-nfs-traffic/`, `smoketest/`
- Responsibilities: Operational debugging and build management tools

## Error Handling

**Strategy:** Structured error wrapping with domain-specific error types

**Patterns:**
- API errors use `packages/shared/pkg/apierrors/` with HTTP status code mapping
- gRPC errors use standard `google.golang.org/grpc/status` and `codes`
- Handlers return errors via `utils.ErrorHandler()` which maps to JSON responses
- Fatal initialization errors use `logger.L().Fatal()` which calls `os.Exit(1)`
- Graceful shutdown uses `sync.Once` cleanup pattern (API) or reverse-order closer list (orchestrator)
- Context cancellation propagated through all layers for timeout and shutdown

## Cross-Cutting Concerns

**Logging:**
- Zap logger with OpenTelemetry core integration (`packages/shared/pkg/logger/`)
- Separate internal and external sandbox loggers (`packages/shared/pkg/logger/sandbox/`)
- Global logger set via `logger.ReplaceGlobals()` at service startup
- Structured fields: team ID, service instance ID, sandbox ID

**Telemetry:**
- OpenTelemetry traces, metrics, and logs (`packages/shared/pkg/telemetry/`)
- Each service initializes `telemetry.New()` with node ID, service name, commit SHA
- pprof server on separate port for profiling
- Runtime instrumentation for Go metrics (goroutines, heap, GC)

**Authentication:**
- Multiple authenticator chain: API key, access token, Supabase JWT, admin token
- Auth middleware runs via OpenAPI validation (`openapi3filter.AuthenticationFunc`)
- Authenticator interface: `packages/auth/pkg/auth/`
- Team info extracted and attached to request context

**Validation:**
- OpenAPI spec validation via `oapi-codegen/gin-middleware`
- Request size limiting via `gin-contrib/size`
- Database-level validation in sqlc queries

**Feature Flags:**
- LaunchDarkly client (`packages/shared/pkg/feature-flags/`)
- Used in orchestrator (template caching, event delivery), client-proxy, API
- Initialized at service startup, passed as dependency

**Graceful Shutdown:**
- All services handle SIGTERM/SIGINT
- Health endpoint returns 503 during drain phase
- 15-second propagation delay before actual shutdown
- Orchestrator uses file lock to prevent restart races
- Resources closed in reverse initialization order

---

*Architecture analysis: 2026-03-08*
