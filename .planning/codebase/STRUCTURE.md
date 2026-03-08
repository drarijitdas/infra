# STRUCTURE.md — Directory Layout & Organization

## Top-Level Layout

```
infra/
├── packages/              # Go service modules (14 packages)
├── iac/                   # Infrastructure as Code (Terraform)
├── spec/                  # Proto/API specifications
├── tests/                 # Integration tests
├── scripts/               # Utility scripts
├── mocks/                 # Generated mocks (mockery)
├── .github/workflows/     # CI/CD pipelines
├── go.work                # Go workspace definition
├── Makefile               # Root build orchestration
├── CLAUDE.md              # Project documentation
├── .env.template          # Environment variable template
└── .mockery.yaml          # Mock generation config
```

## packages/ — Go Service Modules

### Core Services

```
packages/api/                    # REST API server
├── main.go                      # Entry point, server setup
├── internal/
│   ├── handlers/                # Request handlers
│   │   └── store.go             # APIStore — core handler struct
│   ├── api/                     # Generated OpenAPI code
│   │   ├── api.gen.go           # Generated types + handlers (~12k lines)
│   │   └── spec.gen.go          # Embedded OpenAPI spec
│   ├── auth/                    # JWT/Supabase auth
│   ├── sandbox/                 # Sandbox lifecycle management
│   └── utils/                   # API-specific utilities
├── Makefile                     # API-specific build targets
└── go.mod

packages/orchestrator/           # Firecracker VM orchestration
├── main.go                      # Entry point
├── internal/
│   ├── sandbox/                 # VM lifecycle
│   │   ├── sandbox.go           # Core sandbox logic (~1.3k lines)
│   │   ├── fc/                  # Firecracker integration
│   │   ├── network/             # VM networking (iptables, netlink)
│   │   ├── nbd/                 # Network Block Device storage
│   │   └── template/            # Template caching
│   ├── server/                  # gRPC server implementation
│   └── dns/                     # DNS management
├── cmd/
│   ├── clean-nfs-cache/         # NFS cache cleanup utility
│   ├── build-template/          # Template builder
│   └── resume-build/            # Build resumption (~1.4k lines)
├── generate.Dockerfile          # Proto code generation
├── Makefile
└── go.mod

packages/envd/                   # In-VM daemon
├── main.go                      # Entry point
├── internal/
│   ├── services/                # RPC service implementations
│   │   ├── process/             # Process management
│   │   ├── filesystem/          # Filesystem operations
│   │   └── legacy/              # Backward-compatible interceptors
│   └── host/                    # Host communication
├── Makefile
└── go.mod

packages/client-proxy/           # Edge routing layer
├── main.go
├── internal/
│   ├── proxy/                   # Proxy logic
│   └── consul/                  # Service discovery
└── go.mod
```

### Supporting Packages

```
packages/shared/                 # Shared libraries
├── pkg/
│   ├── grpc/                    # gRPC definitions + helpers
│   │   ├── orchestrator/        # Orchestrator proto types
│   │   └── envd/                # Envd proto types
│   ├── storage/                 # Cloud storage (GCS/S3/Local)
│   ├── telemetry/               # OpenTelemetry setup
│   ├── logger/                  # Zap + OTEL logging
│   ├── db/                      # Database client (ent ORM)
│   ├── models/                  # Shared domain models
│   ├── apierrors/               # Structured error types
│   ├── cache/                   # Caching utilities
│   ├── feature-flags/           # LaunchDarkly integration
│   ├── middleware/              # HTTP/gRPC middleware
│   ├── redis/                   # Redis utilities
│   ├── smap/                    # Synchronized maps
│   ├── id/                      # ID generation
│   ├── env/                     # Environment helpers
│   ├── events/                  # Event publishing
│   ├── factories/               # Client factories (Redis, etc.)
│   ├── health/                  # Health check utilities
│   ├── limit/                   # Rate limiting
│   ├── connlimit/               # Connection limiting
│   ├── sandbox-network/         # Network config
│   ├── sandbox-catalog/         # Sandbox templates
│   ├── filesystem/              # FS utilities
│   ├── ioutils/                 # I/O helpers
│   ├── synchronization/         # Sync primitives
│   └── utils/                   # General utilities
└── go.mod

packages/db/                     # PostgreSQL layer
├── migrations/                  # SQL migrations (goose)
│   └── *.sql                    # Numbered migration files
├── queries/                     # SQL queries (sqlc)
│   └── *.sql                    # Named query files
├── internal/db/                 # Generated sqlc code
├── pkg/testutils/               # Test database helpers
├── sqlc.yaml                    # sqlc configuration
└── go.mod

packages/clickhouse/             # Analytics database
├── migrations/                  # ClickHouse migrations
└── go.mod

packages/auth/                   # Authentication module
packages/dashboard-api/          # Dashboard API
packages/docker-reverse-proxy/   # HTTP reverse proxy
packages/local-dev/              # Local development infra
packages/nomad-nodepool-apm/     # Nomad APM
packages/otel-collector/         # OTEL collector config
packages/fc-versions/            # Firecracker/kernel versions
```

## iac/ — Infrastructure as Code

```
iac/
├── provider-gcp/                # GCP Terraform
│   ├── main.tf                  # Root module
│   ├── variables.tf             # Input variables
│   ├── output.tf                # Outputs
│   ├── nomad/                   # Nomad job definitions
│   │   └── jobs/                # HCL job files
│   ├── nomad-cluster/           # GKE cluster setup
│   ├── network/                 # VPC/firewall config
│   └── init/                    # Bootstrap (buckets, secrets)
├── provider-aws/                # AWS Terraform (30+ files)
│   ├── main.tf
│   ├── variables.tf
│   └── ...                      # Similar structure to GCP
├── modules/                     # Reusable Terraform modules
└── nomad-cluster-disk-image/    # Packer image configs
```

## spec/ — API Specifications

```
spec/
├── openapi.yml                  # REST API spec
├── process/
│   └── process.proto            # Process management proto
└── filesystem/
    └── filesystem.proto         # Filesystem proto
```

## tests/ — Integration Tests

```
tests/integration/
├── internal/
│   ├── setup/                   # Test infrastructure (DB, clients)
│   ├── api/                     # API client helpers
│   └── tests/
│       ├── envd/                # Envd integration tests
│       └── api/                 # API integration tests
├── go.mod                       # Separate module
└── go.sum
```

## Naming Conventions

### Files
- **Go source**: lowercase, underscore-separated (`sandbox_store.go`, `api_store.go`)
- **Test files**: `*_test.go` alongside source
- **Generated**: `*.gen.go` suffix (OpenAPI), `mock*.go` (mocks)
- **Proto**: `*.proto` in `spec/` directories
- **Migrations**: `NNNNNN_description.sql` (goose numbering)

### Directories
- **Package names**: lowercase single word (`sandbox`, `network`, `storage`)
- **Internal code**: `internal/` for package-private code
- **Public APIs**: `pkg/` for importable libraries
- **Commands**: `cmd/` for standalone CLI tools

### Key File Locations
- **Service entry points**: `packages/{service}/main.go`
- **Core handlers**: `packages/api/internal/handlers/store.go`
- **VM management**: `packages/orchestrator/internal/sandbox/sandbox.go`
- **Database queries**: `packages/db/queries/*.sql`
- **Migrations**: `packages/db/migrations/*.sql`
- **Proto definitions**: `spec/` and `packages/shared/pkg/grpc/`
- **Mock config**: `.mockery.yaml`
- **Workspace config**: `go.work`
