# Centralized CI/CD for Microservices - Design Document

**Date:** 2026-03-29
**Status:** Approved
**Scope:** Create reusable GitHub Actions workflows to centralize CI/CD configuration for Java microservices deploying to Coolify.

---

## Problem Statement

Both `platform-user-service` and `platform-file-management-service` have nearly **identical 837-line workflows** with only minor differences (service name in one error message). This creates:

- **Maintenance burden** - Changes require updating N service repositories
- **Risk of drift/inconsistency** - Already seeing slight differences between files
- **Barrier to adding new services** - Copy-paste massive files is error-prone
- **Code review fatigue** - Boilerplate obscures actual service-specific changes

---

## Solution: Reusable Workflows (Option B)

Create a **reusable workflow** in `infrastructure/.github/workflows/microservice-deploy.yml` that each microservice calls via `workflow_call`. Services pass minimal configuration, and secrets are resolved via convention.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  platform-user-service/.github/workflows/deploy.yml         │
│  ─────────────────────────────────────────────────────────  │
│  uses: serenity-flow/infrastructure/.github/workflows/      │
│         microservice-deploy.yml@main                          │
│  with:                                                       │
│    service-name: platform-user-service                     │
│  secrets: inherit                                            │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  infrastructure/.github/workflows/microservice-deploy.yml   │
│  ─────────────────────────────────────────────────────────  │
│  Reusable workflow with jobs:                               │
│    - validate                                              │
│    - build-and-test                                        │
│    - build-and-push-image                                  │
│    - deploy-dev                                            │
│    - deploy-prod                                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Reusable Workflow Specification

### Location

`infrastructure/.github/workflows/microservice-deploy.yml`

### Inputs

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `service-name` | string | Yes | - | Service identifier (kebab-case, e.g., `platform-user-service`) |
| `java-version` | string | No | `17` | Java version for Gradle build |
| `java-distribution` | string | No | `temurin` | JDK distribution |
| `health-check-path` | string | No | `/actuator/health` | Health check endpoint path |
| `info-endpoint-path` | string | No | `/actuator/info` | Version info endpoint path |
| `deploy-timeout-minutes` | number | No | `10` | Deployment wait timeout |
| `health-check-timeout-minutes` | number | No | `5` | Health check timeout |

### Secrets Convention

Secrets follow naming pattern: `{PREFIX}_{SERVICE}_{ENV}` or `{PREFIX}_{ENV}`

| Pattern | Example for `platform-user-service` | Description |
|---------|---------------------------------------|-------------|
| `COOLIFY_URL_{ENV}` | `COOLIFY_URL_DEV`, `COOLIFY_URL_PROD` | Coolify instance URL (shared) |
| `COOLIFY_API_TOKEN_{ENV}` | `COOLIFY_API_TOKEN_DEV`, `COOLIFY_API_TOKEN_PROD` | API token for Coolify (shared) |
| `COOLIFY_APP_UUID_{SERVICE}_{ENV}` | `COOLIFY_APP_UUID_PLATFORM_USER_SERVICE_DEV` | Application UUID in Coolify (unique per service) |
| `SERVICE_URL_{SERVICE}_{ENV}` | `SERVICE_URL_PLATFORM_USER_SERVICE_DEV` | Service public URL (unique per service) |

**Secret Name Transformation:**
- Service `platform-user-service` becomes `PLATFORM_USER_SERVICE` (uppercase, hyphens to underscores)

---

## Jobs Specification

### Job 1: Validate

**Purpose:** Validate required secrets and configuration before building.

**Steps:**
1. Check `GITHUB_TOKEN` is available
2. For non-PR builds, verify package access token
3. Fail fast with helpful error messages

**Outputs:** `validation-passed` (boolean)

### Job 2: Build and Test

**Purpose:** Build the Gradle project and run tests.

**Steps:**
1. Checkout repository with `fetch-depth: 0`
2. Set up JDK with Gradle caching
3. Grant execute permission for `gradlew`
4. Run `./gradlew build --no-daemon`
5. Run `./gradlew test --no-daemon`
6. Upload test results as artifact

**Outputs:**
- `build-status`
- `test-status`
- `version` (derived from commit SHA: `0.0.1-{short-sha}`)

### Job 3: Build and Push Image

**Purpose:** Build Docker image and push to GitHub Container Registry.

**Conditions:** Only runs if `github.event_name != 'pull_request'`

**Steps:**
1. Build Docker image with build args:
   - `GITHUB_ACTOR`
   - `GITHUB_TOKEN`
   - `VERSION` (from job 2)
2. Tags to create:
   - `ghcr.io/{repo}:{sha}`
   - `ghcr.io/{repo}:build-{run-number}`
   - `ghcr.io/{repo}:{branch-name}`
   - `ghcr.io/{repo}:latest` (if main/master branch)
   - `ghcr.io/{repo}:{tag}` (if tag push)
3. Log in to GHCR
4. Push all tags

**Outputs:**
- `image-tag`
- `image-full-name`

### Job 4: Deploy to Development

**Purpose:** Deploy to Coolify development environment.

**Conditions:**
```yaml
if: |
  github.event_name != 'pull_request' && (
    github.ref == 'refs/heads/main' ||
    github.ref == 'refs/heads/master' ||
    (github.event_name == 'workflow_dispatch' && inputs.environment == 'development')
  )
```

**Environment:** `development` (enables GitHub environment protection rules)

**Steps:**
1. **Validate Secrets:** Check `COOLIFY_URL_DEV`, `COOLIFY_API_TOKEN_DEV`, `COOLIFY_APP_UUID_{SERVICE}_DEV`
2. **Trigger Deployment:** Call Coolify API `GET /api/v1/deploy?uuid={app-uuid}&force=true`
3. **Wait for Deployment:** Poll `/api/v1/applications/{app-uuid}` until status is `running` or `failed`
4. **Health Check:** Poll `{SERVICE_URL}/actuator/health` until status is `UP`
5. **Version Verification:** Poll `{SERVICE_URL}/actuator/info` and verify deployed SHA matches expected

### Job 5: Deploy to Production

**Purpose:** Deploy to Coolify production environment.

**Conditions:**
```yaml
if: |
  github.event_name != 'pull_request' && (
    startsWith(github.ref, 'refs/tags/v') ||
    (github.event_name == 'workflow_dispatch' && inputs.environment == 'production')
  )
```

**Environment:** `production` (enables GitHub environment protection rules)

**Steps:** Same as development deployment but with `_PROD` secrets.

---

## Service Workflow Template

Each microservice replaces their 837-line workflow with this minimal version:

```yaml
name: Deploy

on:
  push:
    branches: [main, master]
    tags: ['v*']
  pull_request:
    branches: [main, master]
  workflow_dispatch:
    inputs:
      environment:
        description: 'Deployment environment'
        required: true
        default: 'development'
        type: choice
        options:
          - development
          - production

jobs:
  deploy:
    uses: serenity-flow/infrastructure/.github/workflows/microservice-deploy.yml@main
    with:
      service-name: platform-user-service
      java-version: '17'
    secrets: inherit
```

---

## Migration Plan

### Phase 1: Create Reusable Workflow

1. Create `infrastructure/.github/workflows/microservice-deploy.yml`
2. Port logic from existing service workflows
3. Test with one service (platform-user-service) using feature branch reference
4. Fix any issues, merge to main

### Phase 2: Migrate Services

For each service:
1. Create new minimal workflow in `.github/workflows/deploy.yml`
2. Set up required secrets following naming convention
3. Test deployment to dev
4. Merge and verify

### Phase 3: Cleanup

1. Remove old workflows from all service repos
2. Document the new convention in infrastructure README

---

## Secrets Mapping (Migration Reference)

| Old Secret Name | New Secret Name | Location |
|-----------------|-----------------|----------|
| `COOLIFY_URL_DEV` | `COOLIFY_URL_DEV` | Infrastructure repo (shared) |
| `COOLIFY_API_TOKEN_DEV` | `COOLIFY_API_TOKEN_DEV` | Infrastructure repo (shared) |
| `COOLIFY_APP_UUID_DEV` | `COOLIFY_APP_UUID_{SERVICE}_DEV` | Each service repo |
| `SERVICE_URL_DEV` | `SERVICE_URL_{SERVICE}_DEV` | Each service repo |

---

## Error Handling

All jobs include:
- Clear error messages with troubleshooting steps
- Validation of secrets before attempting operations
- Timeouts on polling operations (configurable)
- Summary output at end of deployment jobs

---

## Future Considerations

1. **Matrix builds** - Add support for multiple Java versions if needed
2. **Notification** - Add Slack/Discord notifications on failure/success
3. **Rollback** - Add automated rollback on health check failure
4. **Canary deployments** - Support for staged rollouts

---

## Acceptance Criteria

- [ ] `infrastructure` repo has `microservice-deploy.yml` reusable workflow
- [ ] Service workflows reduced from ~837 lines to ~30 lines
- [ ] Each service can still deploy independently
- [ ] Secrets are resolved via convention
- [ ] Same functionality as before: build, test, Docker push, Coolify deploy, verify
- [ ] No breaking changes to existing deployments
