# Technology Stack

**Analysis Date:** 2026-03-08

## Languages

**Primary:**
- Go 1.25.4 - All services (API, Orchestrator, Envd, Client Proxy, Dashboard API, DB, Auth, ClickHouse)

**Secondary:**
- HCL (Terraform 1.5.7) - Infrastructure as Code in `iac/`
- Protocol Buffers (protoc 29.3) - Service communication definitions in `spec/`
- Shell scripts - Build and deployment automation in `scripts/`

## Runtime

**Environment:**
- Go 1.25.4 (specified in `go.work` and `.tool-versions`)
- Linux (production) - Firecracker requires Linux kernel features

**Package Manager:**
- Go modules with workspaces (`go.work`)
- Lockfiles: `go.sum` present in each package module

## Frameworks

**Core:**
- Gin v1.10.1 - HTTP framework for API (`packages/api/`), Dashboard API (`packages/dashboard-api/`), Orchestrator HTTP endpoints
- Chi v5.2.2 - HTTP framework for Envd (`packages/envd/`)
- Connect RPC v1.18.1 - RPC framework for Envd (`packages/envd/`) and Orchestrator client communication
- gRPC v1.78.0 - Inter-service communication (API to Orchestrator)

**Testing:**
- testify v1.11.1 - Assertions (`assert`, `require`) across all packages
- testcontainers-go v0.40.0 - Database integration testing (`packages/db/`)
- mockery v3.5.0 - Mock generation (config: `.mockery.yaml`)

**Build/Dev:**
- air v1.61.7 - Hot reload for API development (`packages/api/`)
- oapi-codegen v2.5.1 - OpenAPI code generation for API, Orchestrator, Envd
- sqlc v1.29.0 - Type-safe SQL code generation (`packages/db/`)
- goose v3.26.0 - Database migrations (`packages/db/`)
- buf v1.28.1 - Protocol buffer tooling
- golangci-lint v2.8.0 - Linting (config: `.golangci.yml`)
- Packer v1.13.1 - Machine image building (`iac/nomad-cluster-disk-image/`)

## Key Dependencies

**Critical:**
- `firecracker-go-sdk` v1.0.0 - Firecracker microVM management (`packages/orchestrator/`)
- `jackc/pgx` v5.7.5 - PostgreSQL driver (`packages/api/`, `packages/db/`, `packages/dashboard-api/`)
- `ClickHouse/clickhouse-go` v2.40.1 - ClickHouse analytics client (`packages/clickhouse/`)
- `redis/go-redis` v9.17.3 - Redis client for caching and state (`packages/api/`, `packages/orchestrator/`, `packages/shared/`)
- `launchdarkly/go-server-sdk` v7.13.0 - Feature flags (`packages/shared/pkg/feature-flags/`)
- `hashicorp/consul/api` v1.32.1 - Service discovery (`packages/orchestrator/`)
- `hashicorp/nomad/api` - Job scheduling and cluster management (`packages/api/`, `packages/shared/`)

**Infrastructure:**
- `cloud.google.com/go/storage` v1.59.2 - GCS object storage (`packages/shared/`, `packages/orchestrator/`)
- `aws/aws-sdk-go-v2` v1.41.0 - AWS S3 and ECR (`packages/shared/`, `packages/orchestrator/`)
- `google/go-containerregistry` v0.20.6 - Container image management (`packages/shared/`, `packages/orchestrator/`)
- `grafana/loki` v3.6.4 - Log querying (`packages/api/`, `packages/shared/`)
- `posthog/posthog-go` - Product analytics (`packages/api/`)

**Networking (Orchestrator-specific):**
- `vishvananda/netlink` v1.3.1 - Linux network interface management
- `vishvananda/netns` v0.0.5 - Linux network namespace management
- `coreos/go-iptables` v0.8.0 - iptables rule management
- `google/nftables` v0.3.0 - nftables firewall rules
- `ngrok/firewall_toolkit` v0.0.18 - Firewall utilities
- `containernetworking/plugins` v1.9.0 - CNI networking plugins
- `Merovius/nbd` - Network Block Device protocol

**Observability:**
- OpenTelemetry SDK v1.41.0 - Traces, metrics, logs (`packages/shared/pkg/telemetry/`)
- `otelgin` v0.57.0 - Gin middleware instrumentation
- `otelgrpc` v0.65.0 - gRPC instrumentation
- `otelpgx` v0.9.3 - PostgreSQL instrumentation
- `redisotel` v9.17.3 - Redis instrumentation
- Zap v1.27.1 - Structured logging (`packages/shared/pkg/logger/`)

## Configuration

**Environment:**
- Config parsed via `caarlos0/env` v11.3.1 (struct tags) in `packages/api/internal/cfg/`
- Environment files: `.env.gcp.template`, `.env.aws.template` (templates for per-environment `.env.{prod,staging,dev}`)
- Active env tracked in `.last_used_env`, switched via `make switch-env ENV=<name>`
- Secrets stored in GCP Secrets Manager (production) or Infisical Vault (`scripts/download-prod-env.sh`)

**Key required env vars:**
- `POSTGRES_CONNECTION_STRING` - Primary database
- `LOKI_URL` - Log aggregation endpoint
- `SUPABASE_JWT_SECRETS` - JWT validation (comma-separated)
- `LAUNCH_DARKLY_API_KEY` - Feature flags (optional, falls back to offline mode)
- `GCP_PROJECT_ID`, `GCP_REGION`, `GCP_ZONE` - Cloud provider config
- `DOMAIN_NAME` - Service domain

**Build:**
- `Makefile` (root) - Top-level orchestration
- Per-package `Makefile` in each `packages/<service>/`
- Docker builds for production containers
- Go workspace: `go.work` links all modules

## Platform Requirements

**Development:**
- Go 1.25.4
- Docker (for local infrastructure via `make local-infra`)
- `.tool-versions` manages: buf, bun, gcloud, golang, golangci-lint, packer, protoc, protoc-gen-connect-go, protoc-gen-go, protoc-gen-go-grpc, python, terraform
- GCP CLI (`gcloud`) for authentication and deployment

**Production:**
- GCP (primary) or AWS (in progress)
- Linux with KVM support (Firecracker requirement)
- Nomad + Consul cluster for job scheduling and service discovery
- Terraform 1.5.7 for infrastructure provisioning

**Local Development Stack** (`packages/local-dev/docker-compose.yaml`):
- PostgreSQL 17.4 (port 5432)
- Redis 7.4.2 (port 6379)
- ClickHouse 25.4.5.24 (ports 8123, 9000)
- Grafana 12.0.0 (port 53000)
- Loki 3.4.1 (port 3100)
- Tempo 2.8.2 (tracing)
- Mimir 2.17.1 (metrics)
- OpenTelemetry Collector 0.146.0 (ports 4317, 4318)
- Vector 0.34.x (log shipping, port 30006)
- Memcached 1.6.38 (port 11211)

---

*Stack analysis: 2026-03-08*
