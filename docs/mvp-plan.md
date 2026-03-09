# From PoC to Production — MVP Roadmap

## 1. What Changes for MVP (vs Current PoC)

### Authentication: API Key → Cognito / JWT

**Current (PoC):** A single shared API key validated via SHA-256 hash comparison in the Proxy Lambda. No user identity, no token expiry, no rotation.

**MVP:** Amazon Cognito User Pool with JWT tokens. API Gateway authoriser validates JWTs before requests reach the Proxy Lambda. This enables per-user identity, token refresh/rotation, and integration with the frontend login flow.

### Multi-tenancy: Single Client → Multiple Restaurant Chains

**Current (PoC):** One restaurant chain with hardcoded location names (`Riverside`, `Uptown`, `Downtown`, `Midtown`, `Lakeside`). All data lives in a single OpenSearch index.

**MVP:** Tenant-scoped OpenSearch indices (e.g. `reviews_<tenant_id>`) or a `tenant_id` field added to the document schema with mandatory term filters on every query. S3 bucket prefixes per tenant for data isolation. Cognito custom claims carry the tenant context through the request chain.

### Monitoring: CloudWatch Basic → Structured Logging + Alerting

**Current (PoC):** Default CloudWatch Logs from Lambda `print()` statements. No alarms, no dashboards, no structured format.

**MVP:**
- Structured JSON logging via `aws-lambda-powertools` (Python)
- CloudWatch Alarms on: Lambda error rate > 5%, Search Lambda p99 latency > 5s, OpenSearch cluster health RED
- CloudWatch Dashboard with panels for: query volume, latency distribution, error rate, OpenSearch storage usage
- X-Ray tracing enabled on API Gateway + Lambda for request waterfall visibility

### CI/CD: Manual Bash Script → GitHub Actions Pipeline

**Current (PoC):** `deployment_pipeline_bash.sh` builds ZIPs locally and uploads to S3. Terraform apply is run manually.

**MVP:** GitHub Actions workflow with stages:
1. **Lint & Test** — `py_compile` + pytest unit tests + Terraform `validate` + `tflint`
2. **Build** — Build Lambda ZIPs in a clean container
3. **Deploy Staging** — `terraform apply` to staging environment with integration tests
4. **Deploy Production** — Manual approval gate → `terraform apply` to production
5. **Post-deploy** — Smoke test via `test_backend.sh api`

### OpenSearch: Single Node → Multi-AZ

**Current (PoC):** Single `t3.small.search` node, no zone awareness, no replicas.

**MVP:** Two `m5.large.search` nodes across two Availability Zones with a replica shard. Enables zero-downtime during node failures and rolling upgrades. Fine-grained access control enabled with SAML/IAM.

### Data Pipeline: Manual Trigger → EventBridge Scheduled + S3 Event Trigger

**Current (PoC):** ETL and Embedding Lambdas are triggered manually via `aws lambda invoke`.

**MVP:**
- **Scheduled ingestion:** EventBridge rule triggers ETL Lambda nightly (or weekly) to process new raw uploads.
- **Event-driven re-index:** S3 PutObject event on the processed bucket triggers the Embedding Lambda to re-index new data.
- **Dead-letter queues:** SQS DLQs on both Lambdas to capture failed events for manual retry.

---

## 2. Architecture Changes (MVP)

```
                          ┌─────────────┐
                          │  Cognito    │
                          │  User Pool  │
                          └──────┬──────┘
                                 │ JWT
                                 ▼
CloudFront ──▶ S3 (Frontend) ──▶ API Gateway (JWT Authoriser)
                                 │
                                 ▼
                          Proxy Lambda ──▶ Bedrock Agent (Haiku/Sonnet)
                                               │
                                               ▼
                                         Search Lambda ──▶ OpenSearch (Multi-AZ)
                                                            m5.large × 2

EventBridge (schedule) ──▶ ETL Lambda ──▶ S3 (processed)
                                               │
                                    S3 Event Notification
                                               │
                                               ▼
                                      Embedding Lambda ──▶ OpenSearch

CloudWatch Alarms + Dashboard + X-Ray
SQS Dead-Letter Queues on ETL + Embedding Lambdas
```

Key changes from PoC:
- Cognito replaces API key auth
- CloudFront + S3 replaces Vercel (consolidates into AWS)
- OpenSearch moves to Multi-AZ with larger instance type
- EventBridge + S3 events automate the data pipeline
- X-Ray + structured logging for observability
- DLQs for resilience

---

## 3. Effort Estimate

| Feature | Effort (days) | Priority | Dependencies |
|---|---|---|---|
| Cognito User Pool + JWT Authoriser | 3 | P0 — Must have | API Gateway config, frontend login |
| GitHub Actions CI/CD pipeline | 3 | P0 — Must have | Branch protection, staging env |
| Structured logging (Powertools) | 2 | P0 — Must have | All Lambdas |
| CloudWatch Alarms + Dashboard | 2 | P0 — Must have | Structured logging |
| OpenSearch Multi-AZ upgrade | 1 | P0 — Must have | Terraform change, re-index |
| EventBridge scheduled ETL | 1 | P1 — Should have | ETL Lambda idempotency |
| S3 event → Embedding trigger | 1 | P1 — Should have | S3 notification config |
| SQS Dead-Letter Queues | 1 | P1 — Should have | Lambda DLQ config |
| Multi-tenancy (index per tenant) | 5 | P1 — Should have | Cognito claims, search filter |
| X-Ray tracing | 1 | P2 — Nice to have | Lambda + API GW config |
| CloudFront + S3 frontend | 2 | P2 — Nice to have | DNS, TLS cert |
| pytest unit test suite | 3 | P1 — Should have | Test fixtures, mocks |
| Load testing (Locust / Artillery) | 2 | P2 — Nice to have | Staging environment |
| **Total** | **~27 days** | | |

---

## 4. Timeline: 3 Sprints to MVP

### Sprint 1 — Foundation (2 weeks)

**Goal:** Secure access, automated deployment, observability basics.

| Task | Owner | Days |
|---|---|---|
| Cognito User Pool + JWT Authoriser | Backend | 3 |
| GitHub Actions CI/CD (lint, build, deploy staging) | DevOps | 3 |
| Structured logging (Powertools) across all Lambdas | Backend | 2 |
| CloudWatch Alarms (error rate, latency) | DevOps | 1 |
| OpenSearch Multi-AZ migration | Infra | 1 |

**Sprint 1 deliverable:** Authenticated API with automated deployment to staging, structured logs, and basic alerting.

### Sprint 2 — Automation & Quality (2 weeks)

**Goal:** Automated data pipeline, testing, multi-tenancy design.

| Task | Owner | Days |
|---|---|---|
| EventBridge scheduled ETL + S3 event embedding trigger | Backend | 2 |
| SQS Dead-Letter Queues | Backend | 1 |
| pytest unit test suite (ETL, search, proxy) | Backend | 3 |
| Multi-tenancy implementation (index per tenant) | Backend | 5 |

**Sprint 2 deliverable:** Fully automated data pipeline with DLQs, unit tests in CI, and multi-tenant data isolation.

### Sprint 3 — Polish & Hardening (2 weeks)

**Goal:** Production-grade frontend, observability, load testing.

| Task | Owner | Days |
|---|---|---|
| CloudFront + S3 static frontend | Frontend | 2 |
| CloudWatch Dashboard | DevOps | 1 |
| X-Ray tracing | Backend | 1 |
| Load testing with Locust / Artillery | QA | 2 |
| Security review + VPC endpoints for OpenSearch | Infra | 2 |
| Documentation update + handover | All | 1 |

**Sprint 3 deliverable:** Production-ready MVP with consolidated AWS hosting, full observability, and validated performance under load.

---

## Risk Register

| Risk | Impact | Mitigation |
|---|---|---|
| OpenSearch Multi-AZ migration causes downtime | Medium | Blue-green: create new domain, re-index, swap alias |
| Cognito adds latency to every request | Low | JWT validation at API GW is <10ms; cache tokens client-side |
| Multi-tenancy index explosion | Medium | Cap tenants per cluster; consider shared index with tenant_id filter |
| Bedrock Haiku quality insufficient for production | Medium | Swap to Sonnet (12× cost) or fine-tune prompts; monitor eval scores |
| GitHub Actions secrets leak | High | Use OIDC for AWS auth; no long-lived credentials |
