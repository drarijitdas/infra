# External Integrations

**Analysis Date:** 2026-03-08

## APIs & External Services

**Analytics:**
- PostHog - Product analytics and event tracking
  - SDK/Client: `github.com/posthog/posthog-go`
  - Used in: `packages/api/internal/analytics_collector/analytics.go`, `packages/api/internal/handlers/store.go`
  - Auth: env var `POSTHOG_API_KEY` (inferred from usage pattern)

**Feature Flags:**
- LaunchDarkly - Feature flag management and gradual rollouts
  - SDK/Client: `github.com/launchdarkly/go-server-sdk/v7`
  - Implementation: `packages/shared/pkg/feature-flags/client.go`
  - Flag definitions: `packages/shared/pkg/feature-flags/flags.go`
  - Auth: env var `LAUNCH_DARKLY_API_KEY`
  - Fallback: Runs in offline mode with `ldtestdata.DataSource()` when API key is not set
  - Used by: API, Orchestrator, Client Proxy (via shared package)

**Secrets Management:**
- Infisical - Secrets vault for production environment variables
  - CLI tool: `infisical`
  - Script: `scripts/download-prod-env.sh`
  - Usage: `make download-prod-env` to sync secrets to local `.env` files

**Container Registries:**
- GCP Artifact Registry - Container image storage
  - SDK: `cloud.google.com/go/artifactregistry`
  - Client: `packages/shared/pkg/artifacts-registry/`
- AWS ECR - Container image storage (AWS provider)
  - SDK: `github.com/aws/aws-sdk-go-v2/service/ecr`
  - Used in: `packages/orchestrator/` and `packages/shared/`
- Docker Hub - Public image pulls
  - Client: `packages/shared/pkg/dockerhub/`

## Data Storage

**Databases:**
- PostgreSQL 17.4 - Primary data store (teams, templates, sandboxes, auth)
  - Connection: env var `POSTGRES_CONNECTION_STRING`
  - Auth DB: env var `AUTH_DB_CONNECTION_STRING` (separate connection for auth, with read replica via `AUTH_DB_READ_REPLICA_CONNECTION_STRING`)
  - Driver: `jackc/pgx` v5.7.5
  - Query generation: `sqlc` (queries in `packages/db/queries/*.sql`, generated code in `packages/db/client/`)
  - Migrations: `goose` (migration files in `packages/db/migrations/*.sql`)
  - OTel instrumentation: `otelpgx`
  - Connection pooling: Custom pool wrapper in `packages/db/pkg/pool/`

- ClickHouse 25.4.5.24 - Analytics and event data
  - Driver: `ClickHouse/clickhouse-go` v2.40.1
  - Client: `packages/clickhouse/pkg/`
  - Migrations: goose-based (`packages/clickhouse/`)
  - Used for: Sandbox metrics, usage analytics, log aggregation

**Caching & State:**
- Redis 7.4.2 - Caching, distributed locking, state management
  - Client: `github.com/redis/go-redis/v9`
  - Distributed locks: `github.com/bsm/redislock`
  - Connection: configured via env vars
  - OTel instrumentation: `redisotel`
  - Used for: Template caching, auth token caching, sandbox state, distributed coordination
  - Managed option: env var `REDIS_MANAGED=true` for cloud-managed Redis

**Object Storage:**
- GCS (Google Cloud Storage) - Template storage, build artifacts
  - SDK: `cloud.google.com/go/storage`
  - Client: `packages/shared/pkg/storage/storage_google.go`
  - Bucket: env var `TEMPLATE_BUCKET_NAME`
  - Public builds: `gs://e2b-prod-public-builds/` (kernels, Firecracker binaries)

- AWS S3 - Template storage (AWS provider)
  - SDK: `github.com/aws/aws-sdk-go-v2/service/s3`
  - Client: `packages/shared/pkg/storage/storage_aws.go`
  - S3 manager for multipart uploads

- Local filesystem - Development/testing storage
  - Client: `packages/shared/pkg/storage/storage_fs.go`

**File Storage:**
- GCP Filestore - NFS-based shared cache for builds across cluster
  - Enabled via: env var `FILESTORE_CACHE_ENABLED`
  - Tiers: `BASIC_HDD` (staging/dev), `ZONAL` (production)

## Authentication & Identity

**Auth Provider:**
- Supabase (JWT-based) - User authentication
  - Implementation: `packages/auth/pkg/auth/service.go`
  - JWT validation via `golang-jwt/jwt/v5`
  - Secrets: env var `SUPABASE_JWT_SECRETS` (comma-separated, supports multiple)
  - Auth flow: JWT token validation -> team lookup via API key or access token
  - Caching: In-memory auth cache (`AuthCache`) to reduce DB lookups
  - API key format: Prefixed keys validated via `packages/shared/pkg/keys/`

**Access Tokens:**
- Custom sandbox access token generation
  - Generator: `packages/api/internal/sandbox/` (`AccessTokenGenerator`)
  - Hash seed: env var `SANDBOX_ACCESS_TOKEN_HASH_SEED`

**Volume Tokens:**
- JWT-based volume access tokens
  - Issuer: env var `VOLUME_TOKEN_ISSUER`
  - Signing: env vars `VOLUME_TOKEN_SIGNING_METHOD`, `VOLUME_TOKEN_SIGNING_KEY`, `VOLUME_TOKEN_SIGNING_KEY_NAME`

## Service Discovery & Orchestration

**Consul:**
- Service discovery for orchestrator nodes
  - SDK: `github.com/hashicorp/consul/api`
  - Used in: `packages/orchestrator/internal/sandbox/network/storage_kv.go`
  - Purpose: KV store for network state, service registration

**Nomad:**
- Job scheduling and cluster management
  - SDK: `github.com/hashicorp/nomad/api`
  - Used in: `packages/api/internal/clusters/`, `packages/shared/pkg/clusters/discovery/nomad.go`
  - Purpose: Orchestrator node pool management, autoscaling, job deployment
  - Nomad jobs: `iac/provider-gcp/nomad/jobs/`

## Monitoring & Observability

**Tracing:**
- OpenTelemetry (OTLP gRPC) -> Grafana Tempo
  - Setup: `packages/shared/pkg/telemetry/traces.go`
  - Exporters: `otlptracegrpc`
  - Instrumentation: Gin, gRPC, HTTP, PostgreSQL, Redis

**Metrics:**
- OpenTelemetry (OTLP gRPC) -> Grafana Mimir
  - Setup: `packages/shared/pkg/telemetry/metrics.go`
  - Exporters: `otlpmetricgrpc`
  - Runtime metrics: `go.opentelemetry.io/contrib/instrumentation/runtime`
  - GCP-specific: `GoogleCloudPlatform/opentelemetry-operations-go` for GCP metric export

**Logs:**
- Zap (structured logging) -> OpenTelemetry -> Grafana Loki
  - Logger: `packages/shared/pkg/logger/` (Zap with OTEL bridge via `otelzap`)
  - Log export: `otlploggrpc`
  - Loki query client: `packages/shared/pkg/logs/loki/` for log retrieval
  - Loki URL: env var `LOKI_URL`

**Log Shipping:**
- Vector 0.34.x - Log collection and forwarding to Loki
  - Config: `packages/local-dev/vector.toml`

**OpenTelemetry Collector:**
- Deployed as sidecar/standalone
  - Config: `packages/local-dev/otel-collector.yaml` (local), `packages/otel-collector/` (tests)
  - Receives: OTLP gRPC (port 4317), OTLP HTTP (port 4318)

**Profiling:**
- pprof endpoints exposed by API service
  - Implementation: `packages/shared/pkg/telemetry/pprof.go`
  - Access: `/debug/pprof/` (separate mux to avoid default mux security issues)

**Dashboards:**
- Grafana 12.0.0 - Visualization
  - Local port: 53000
  - Datasources: Loki, Tempo, Mimir (configured via `packages/local-dev/grafana-datasources.yaml`)

## CI/CD & Deployment

**Hosting:**
- GCP (primary) - Compute Engine, GCS, Artifact Registry, Secrets Manager
- AWS (in progress) - EC2, S3, ECR

**Infrastructure as Code:**
- Terraform 1.5.7
  - GCP config: `iac/provider-gcp/`
  - AWS config: `iac/provider-aws/`
  - Shared modules: `iac/modules/`
  - Machine images: `iac/nomad-cluster-disk-image/`

**CI Pipeline:**
- GitHub Actions
  - `pr-tests.yml` - Unit tests on PRs
  - `integration_tests.yml` - Integration test suite
  - `lint.yml` - Linting checks
  - `build-and-upload-job.yml` - Container builds
  - `deploy-infra.yml` - Infrastructure deployment
  - `deploy-job.yml` - Individual job deployment
  - `validate-openapi.yml` - OpenAPI spec validation
  - `out-of-order-migrations.yml` - Migration order checks
  - `claude-code-review.yml` - AI code review
  - `heath-check.yml` - Health check monitoring
  - `periodic-test.yml` - Periodic smoke tests

**Container Builds:**
- Docker - Service containerization
  - Built via `make build-and-upload/<service>`
  - Pushed to GCP Artifact Registry or AWS ECR

## Environment Configuration

**Required env vars:**
- `POSTGRES_CONNECTION_STRING` - Primary database connection
- `GCP_PROJECT_ID` - GCP project identifier
- `GCP_REGION` / `GCP_ZONE` - Deployment region
- `DOMAIN_NAME` - Service domain
- `SUPABASE_JWT_SECRETS` - Auth JWT validation
- `LOKI_URL` - Log aggregation
- `VOLUME_TOKEN_ISSUER` - Volume access token config
- `VOLUME_TOKEN_SIGNING_METHOD` - JWT signing method (e.g., HS256)
- `VOLUME_TOKEN_SIGNING_KEY` - JWT signing key (format: `HMAC:<base64>`)

**Optional env vars:**
- `LAUNCH_DARKLY_API_KEY` - Feature flags (offline mode if unset)
- `POSTHOG_API_KEY` - Analytics
- `TEMPLATE_BUCKET_NAME` - Custom template storage bucket
- `REDIS_MANAGED` - Use managed Redis service
- `FILESTORE_CACHE_ENABLED` - Enable NFS cache
- `AUTH_DB_CONNECTION_STRING` - Separate auth database
- `AUTH_DB_READ_REPLICA_CONNECTION_STRING` - Auth DB read replica
- `DASHBOARD_API_COUNT` - Dashboard API instance count

**Secrets location:**
- Production: GCP Secrets Manager
- Production (E2B.dev): Infisical Vault (`make download-prod-env`)
- Development: Local `.env.{prod,staging,dev}` files (not committed, listed in `.gitignore`)

## Webhooks & Callbacks

**Incoming:**
- None detected as explicit webhook endpoints

**Outgoing:**
- PostHog event tracking (analytics events sent to PostHog API)
- LaunchDarkly flag evaluation (SDK polls for flag updates)

## OpenAPI Specifications

**API specs:**
- `spec/openapi.yml` - Main API spec
- `spec/openapi-dashboard.yml` - Dashboard API spec
- `spec/openapi-edge.yml` - Edge API spec
- `spec/openapi-hyperloop.yml` - Hyperloop API spec

**Proto specs:**
- `spec/process/` - Process management (Envd)
- `spec/filesystem/` - Filesystem operations (Envd)
- Internal orchestrator protos in `packages/shared/pkg/grpc/orchestrator/`

---

*Integration audit: 2026-03-08*
