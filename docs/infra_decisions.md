# Infrastructure Decisions for TasteTrend ETL Platform

This document summarizes the **infrastructure choices** we made when setting up the AWS-based environment for the TasteTrend analytics/ETL platform.  
It avoids low-level debugging details and instead focuses on **what we chose** and **why** — serving both as personal reference and as a guide for technical interviewers to understand the design logic.

---

## 1. Deployment Model: ZIP over Container Images

- **Decision**: Use **ZIP-based Lambda deployment** instead of container images.  
- **Reasoning**:
  - Simpler Terraform integration (`aws_lambda_function` with `s3_bucket`/`s3_key`).
  - Avoids overhead of managing ECR (Elastic Container Registry).
  - Fast to iterate for small Python ETL functions.
  - Sufficient for current use case (ETL pipeline, not heavy ML inference).

---

## 2. Lambda Build & Upload Automation

- **Decision**: Automate zipping and uploading Lambda code using Terraform.  
- **Implementation**:
  - Lambda source lives in `src/`.
  - On `terraform apply`, Terraform runs a `null_resource` with `local-exec` to package the code (`Compress-Archive` in Windows PowerShell).
  - Resulting zip file stored under `build/etl-{version}.zip`.
  - File automatically uploaded to the **artifacts S3 bucket** before Lambda deployment.
- **Reasoning**:
  - One command (`terraform apply`) handles packaging, uploading, and deployment.
  - Avoids manual `aws s3 cp` uploads.
  - Keeps deployment **declarative** and reproducible.

---

## 3. Versioning Strategy

- **Decision**: Control Lambda deployment through a **`lambda_version` variable**.  
- **Reasoning**:
  - Each new deployment just bumps `lambda_version` (e.g., `0.1 → 0.2`).
  - Keeps zip file names unique (`etl-0.1.zip`, `etl-0.2.zip`) and avoids state confusion.
  - Avoids overcomplicating with AWS Lambda aliases or CodeDeploy for now.
- **Future Consideration**:
  - Add alias-based deployment if moving toward production with blue/green or rollback requirements.
  - For now, **simplicity > enterprise-grade rollout**.

---

## 4. S3 Buckets & Separation of Concerns

- **Decision**: Three dedicated buckets per environment:
  - `*-raw-*` → raw incoming data.
  - `*-processed-*` → processed ETL outputs.
  - `*-artifacts-*` → Lambda deployment packages and other infra artifacts.
- **Reasoning**:
  - Clean separation of responsibilities.
  - Easier IAM scoping: Lambda gets read/write only to `raw` and `processed`, but only read from `artifacts`.
  - Aligns with typical data lake / pipeline staging patterns.

---

## 5. IAM Design

- **Decision**: Minimal IAM role for Lambda, with:
  - Basic CloudWatch logging policy.
  - Custom S3 access policy restricted to `raw` and `processed` buckets.
- **Reasoning**:
  - Principle of least privilege.
  - Avoid attaching broad AWS-managed policies (`AmazonS3FullAccess`).
  - Keeps audit/compliance clean.

---

## 6. Local Development Environment

- **Decision**: Use **Docker Linux container locally** for packaging Lambda dependencies.  
- **Reasoning**:
  - Lambda runs on Amazon Linux; building wheels on Windows can cause binary incompatibility (e.g., `pandas`, `numpy`).
  - Docker ensures dependencies are compiled against the right environment.
  - Keeps deployments consistent and prevents runtime errors.

---

## 7. Infrastructure as Code (IaC) with Terraform

- **Decision**: All infra defined in **Terraform modules**:
  - `s3/` for bucket definitions.
  - `iam/` for Lambda roles and policies.
  - `lambda/` for Lambda deployment logic.
- **Reasoning**:
  - Reusable modules keep environment setup consistent (`dev`, `staging`, `prod`).
  - Clear separation of responsibilities (buckets, IAM, Lambda).
  - Avoids ad-hoc CLI setups.

---

## 8. Efficiency vs. Complexity Trade-Off

- **Chosen Path**: Prioritize **simplicity and fast iteration** over enterprise-grade complexity.
- **Examples**:
  - No Lambda alias/traffic shifting (yet).
  - No automated rollback system.
  - No CI/CD pipeline integrated — Terraform runs locally for now.
- **Reasoning**:
  - We don’t expect frequent redeployments.
  - Infra is supporting ETL + early RAG experiments, not a high-traffic SaaS.
  - IaC is a tool, not the product; we optimize for **developer efficiency**, not maximum AWS feature usage.

---

## 9. Future Extensions (Optional, for later phases)

- Add **Lambda aliases** for safe deployments in production.
- Introduce **Terraform workspaces** or separate state files for `dev/staging/prod`.
- Add **CI/CD pipeline** (GitHub Actions or CodeBuild) for automated deploys.
- Evaluate **serverless framework** or **SAM** if project grows beyond Terraform comfort zone.

---

## Summary

The current infra setup is designed to be:
- **Lightweight** (ZIP-based Lambda, minimal IAM).
- **Automated** (Terraform handles packaging + upload).
- **Safe** (bucket separation + least-privilege IAM).
- **Pragmatic** (avoids overengineering until production needs arise).

This balances **developer speed** and **AWS best practices**, making it a solid foundation for the TasteTrend ETL pipeline and future data products.
