# Centralized CI/CD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a reusable GitHub Actions workflow to centralize CI/CD for Java microservices deploying to Coolify, reducing per-service workflow from ~837 lines to ~30 lines.

**Architecture:** Create a reusable workflow in `infrastructure/.github/workflows/` that services call via `workflow_call`. Secrets follow naming convention `{PREFIX}_{SERVICE}_{ENV}`. Each service passes minimal config (`service-name`, `java-version`).

**Tech Stack:** GitHub Actions, YAML, GitHub Container Registry (GHCR), Coolify API

---

## File Structure

| File | Purpose |
|------|---------|
| `.github/workflows/microservice-deploy.yml` | Main reusable workflow - contains all CI/CD logic |
| `README.md` (update) | Document usage and secret conventions |
| `platform-user-service/.github/workflows/deploy.yml` | Service workflow - minimal caller |
| `platform-file-management-service/.github/workflows/deploy.yml` | Service workflow - minimal caller |

---

## Task 1: Create Reusable Workflow Directory Structure

**Files:**
- Create: `.github/workflows/` directory

**Prerequisites:** None

- [ ] **Step 1: Create workflows directory**

Ensure the `.github/workflows/` directory exists in the infrastructure repository:

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: Verify directory structure**

```bash
ls -la .github/
```

Expected output shows `workflows` directory.

- [ ] **Step 3: Commit directory structure**

```bash
git add .github/workflows/.gitkeep 2>/dev/null || true
git commit -m "chore: prepare workflows directory for centralized CI/CD

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Create Reusable Workflow - Header and Inputs

**Files:**
- Create: `.github/workflows/microservice-deploy.yml` (lines 1-40)

**Prerequisites:** Task 1 complete

- [ ] **Step 1: Write workflow header and inputs**

Create `.github/workflows/microservice-deploy.yml`:

```yaml
name: Microservice Deploy (Reusable)

on:
  workflow_call:
    inputs:
      service-name:
        description: 'Service identifier (kebab-case, e.g., platform-user-service)'
        required: true
        type: string
      java-version:
        description: 'Java version for Gradle build'
        required: false
        type: string
        default: '17'
      java-distribution:
        description: 'JDK distribution'
        required: false
        type: string
        default: 'temurin'
      health-check-path:
        description: 'Health check endpoint path'
        required: false
        type: string
        default: '/actuator/health'
      info-endpoint-path:
        description: 'Version info endpoint path'
        required: false
        type: string
        default: '/actuator/info'
      deploy-timeout-minutes:
        description: 'Deployment wait timeout in minutes'
        required: false
        type: number
        default: 10
      health-check-timeout-minutes:
        description: 'Health check timeout in minutes'
        required: false
        type: number
        default: 5

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}
```

- [ ] **Step 2: Validate YAML syntax**

Run: `yamllint .github/workflows/microservice-deploy.yml` or use online validator.
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/microservice-deploy.yml
git commit -m "feat(cicd): add reusable workflow header and inputs

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Add Validate Job to Reusable Workflow

**Files:**
- Modify: `.github/workflows/microservice-deploy.yml` (after inputs, add jobs section)

**Prerequisites:** Task 2 complete

- [ ] **Step 1: Add validate job**

Append to `.github/workflows/microservice-deploy.yml`:

```yaml
jobs:
  # -----------------------------------------------------------------------------
  # Validate Secrets and Configuration
  # -----------------------------------------------------------------------------
  validate:
    runs-on: ubuntu-latest
    outputs:
      validation-passed: ${{ steps.check.outputs.passed }}
    steps:
      - name: Validate required secrets
        id: check
        run: |
          echo "Validating required configuration..."

          errors=0

          # Check GitHub Token (should always be available)
          if [ -z "${{ secrets.GITHUB_TOKEN }}" ]; then
            echo "ERROR: GITHUB_TOKEN is not available"
            errors=$((errors + 1))
          else
            echo "✓ GITHUB_TOKEN is available"
          fi

          # For non-PR builds, check if we can push to registry
          if [ "${{ github.event_name }}" != "pull_request" ]; then
            if [ -z "${{ secrets.GH_PAT }}" ] && [ -z "${{ secrets.GITHUB_TOKEN }}" ]; then
              echo "⚠ WARNING: Neither GH_PAT nor GITHUB_TOKEN available for package access"
            else
              echo "✓ Package access token is available"
            fi
          fi

          if [ $errors -gt 0 ]; then
            echo ""
            echo "Validation failed with $errors error(s)"
            exit 1
          fi

          echo "✓ All validations passed"
          echo "passed=true" >> $GITHUB_OUTPUT
```

- [ ] **Step 2: Validate YAML syntax**

Run: `yamllint .github/workflows/microservice-deploy.yml`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/microservice-deploy.yml
git commit -m "feat(cicd): add validate job to reusable workflow

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Add Build and Test Job

**Files:**
- Modify: `.github/workflows/microservice-deploy.yml` (after validate job)

**Prerequisites:** Task 3 complete

- [ ] **Step 1: Add build job**

Append to `.github/workflows/microservice-deploy.yml` after the validate job:

```yaml
  # -----------------------------------------------------------------------------
  # Build and Test
  # -----------------------------------------------------------------------------
  build:
    needs: validate
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    outputs:
      version: ${{ steps.version.outputs.version }}
      short-sha: ${{ steps.version.outputs.short-sha }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Set up JDK ${{ inputs.java-version }}
        uses: actions/setup-java@v4
        with:
          java-version: ${{ inputs.java-version }}
          distribution: ${{ inputs.java-distribution }}

      - name: Cache Gradle packages
        uses: actions/cache@v4
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: ${{ runner.os }}-gradle-${{ hashFiles('**/build.gradle') }}
          restore-keys: |
            ${{ runner.os }}-gradle-

      - name: Grant execute permission for gradlew
        run: chmod +x gradlew

      - name: Calculate version
        id: version
        run: |
          SHORT_SHA=$(echo '${{ github.sha }}' | cut -c1-7)
          VERSION="0.0.1-${SHORT_SHA}"
          echo "version=${VERSION}" >> $GITHUB_OUTPUT
          echo "short-sha=${SHORT_SHA}" >> $GITHUB_OUTPUT
          echo "Building with version: ${VERSION}"

      - name: Build with Gradle
        run: ./gradlew build --no-daemon
        env:
          GITHUB_ACTOR: ${{ github.actor }}
          GITHUB_TOKEN: ${{ secrets.GH_PAT || secrets.GITHUB_TOKEN }}

      - name: Run tests
        run: ./gradlew test --no-daemon
        env:
          GITHUB_ACTOR: ${{ github.actor }}
          GITHUB_TOKEN: ${{ secrets.GH_PAT || secrets.GITHUB_TOKEN }}

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results-${{ inputs.service-name }}
          path: build/reports/tests/
          retention-days: 7
```

- [ ] **Step 2: Validate YAML syntax**

Run: `yamllint .github/workflows/microservice-deploy.yml`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/microservice-deploy.yml
git commit -m "feat(cicd): add build and test job to reusable workflow

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 5: Add Docker Build and Push Job

**Files:**
- Modify: `.github/workflows/microservice-deploy.yml` (after build job)

**Prerequisites:** Task 4 complete

- [ ] **Step 1: Add Docker build and push job**

Append to `.github/workflows/microservice-deploy.yml` after the build job:

```yaml
  # -----------------------------------------------------------------------------
  # Build and Push Docker Image
  # -----------------------------------------------------------------------------
  build-image:
    needs: build
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    outputs:
      image-tag: ${{ github.sha }}
      image-full-name: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Build Docker image
        run: |
          VERSION="0.0.1-$(echo '${{ github.sha }}' | cut -c1-7)"
          echo "Building with version: $VERSION"

          docker build \
            --build-arg GITHUB_ACTOR=${{ github.actor }} \
            --build-arg GITHUB_TOKEN=${{ secrets.GH_PAT || secrets.GITHUB_TOKEN }} \
            --build-arg VERSION=$VERSION \
            -t ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} \
            -t ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:build-${{ github.run_number }} .

      - name: Log in to Container Registry
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Push Docker image
        if: github.event_name != 'pull_request'
        run: |
          echo "Pushing Docker images to registry..."

          # Push the SHA-tagged image
          docker push ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          echo "✓ Pushed: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}"

          # Tag and push with branch name
          docker tag ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.ref_name }}
          docker push ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.ref_name }}
          echo "✓ Pushed: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.ref_name }}"

          # Tag with 'latest' if on main/master
          if [[ "${{ github.ref_name }}" == "main" || "${{ github.ref_name }}" == "master" ]]; then
            docker tag ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
            docker push ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
            echo "✓ Pushed: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest"
          fi

          # Tag with version if it's a tag
          if [[ "${{ github.ref }}" == refs/tags/* ]]; then
            VERSION=${GITHUB_REF#refs/tags/}
            docker tag ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${VERSION}
            docker push ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${VERSION}
            echo "✓ Pushed: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${VERSION}"
          fi
```

- [ ] **Step 2: Validate YAML syntax**

Run: `yamllint .github/workflows/microservice-deploy.yml`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/microservice-deploy.yml
git commit -m "feat(cicd): add Docker build and push job

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 6: Add Secret Resolution Helper Script

**Files:**
- Modify: `.github/workflows/microservice-deploy.yml` (before deploy-dev job, add helper step at top of deploy-dev)

**Prerequisites:** Task 5 complete

- [ ] **Step 1: Update deploy-dev job with secret resolution**

The deploy jobs will use a naming convention. For now, add a comment in the workflow explaining the convention. Later we'll add actual secret resolution.

This task is actually about understanding the secret naming. Skip adding code here - the secret names will be referenced directly in deploy jobs using the convention pattern.

- [ ] **Step 2: Document secret naming convention**

Add a comment at the top of the jobs section in `.github/workflows/microservice-deploy.yml`:

```yaml
# Secret Naming Convention:
# Services must define these secrets following the pattern:
# - COOLIFY_URL_DEV / COOLIFY_URL_PROD (infrastructure level, optional)
# - COOLIFY_API_TOKEN_DEV / COOLIFY_API_TOKEN_PROD (infrastructure level, optional)
# - COOLIFY_APP_UUID_{SERVICE}_{ENV} (per-service, required)
#   Example: COOLIFY_APP_UUID_PLATFORM_USER_SERVICE_DEV
# - SERVICE_URL_{SERVICE}_{ENV} (per-service, optional for health checks)
#   Example: SERVICE_URL_PLATFORM_USER_SERVICE_DEV
#
# Service name transformation: platform-user-service -> PLATFORM_USER_SERVICE
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/microservice-deploy.yml
git commit -m "docs(cicd): document secret naming convention

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 7: Add Deploy Development Job

**Files:**
- Modify: `.github/workflows/microservice-deploy.yml` (after build-image job)

**Prerequisites:** Task 6 complete

- [ ] **Step 1: Add deploy-dev job with secrets mapping**

Append to `.github/workflows/microservice-deploy.yml` after the build-image job:

```yaml
  # -----------------------------------------------------------------------------
  # Deploy to Development Environment (Coolify)
  # -----------------------------------------------------------------------------
  deploy-dev:
    name: Deploy to Development
    needs: build-image
    if: |
      github.event_name != 'pull_request' && (
        github.ref == 'refs/heads/main' ||
        github.ref == 'refs/heads/master' ||
        (github.event_name == 'workflow_dispatch' && github.event.inputs.environment == 'development')
      )
    runs-on: ubuntu-latest
    environment:
      name: development
      url: ${{ steps.deploy.outputs.url || steps.secrets.outputs.coolify_url }}

    steps:
      - name: Resolve Secrets
        id: secrets
        run: |
          # Transform service name: platform-user-service -> PLATFORM_USER_SERVICE
          SERVICE_UPPER=$(echo "${{ inputs.service-name }}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
          echo "service_upper=${SERVICE_UPPER}" >> $GITHUB_OUTPUT

          # Try infrastructure-level secrets first, fall back to service-level
          COOLIFY_URL="${{ secrets.COOLIFY_URL_DEV }}"
          COOLIFY_API_TOKEN="${{ secrets.COOLIFY_API_TOKEN_DEV }}"

          # Get service-specific secrets
          COOLIFY_APP_UUID="${{ secrets[format('COOLIFY_APP_UUID_{0}_DEV', SERVICE_UPPER)] }}"
          SERVICE_URL="${{ secrets[format('SERVICE_URL_{0}_DEV', SERVICE_UPPER)] }}"

          echo "coolify_url=${COOLIFY_URL}" >> $GITHUB_OUTPUT
          echo "coolify_api_token=${COOLIFY_API_TOKEN}" >> $GITHUB_OUTPUT
          echo "coolify_app_uuid=${COOLIFY_APP_UUID}" >> $GITHUB_OUTPUT
          echo "service_url=${SERVICE_URL}" >> $GITHUB_OUTPUT

      - name: Validate Development Secrets
        id: validate
        run: |
          echo "Validating Coolify development configuration..."

          errors=0

          if [ -z "${{ steps.secrets.outputs.coolify_url }}" ]; then
            echo "ERROR: COOLIFY_URL_DEV secret is not set!"
            errors=$((errors + 1))
          else
            echo "✓ COOLIFY_URL_DEV is configured"
          fi

          if [ -z "${{ steps.secrets.outputs.coolify_api_token }}" ]; then
            echo "ERROR: COOLIFY_API_TOKEN_DEV is not set!"
            errors=$((errors + 1))
          else
            echo "✓ COOLIFY_API_TOKEN_DEV is configured"
          fi

          if [ -z "${{ steps.secrets.outputs.coolify_app_uuid }}" ]; then
            echo "ERROR: COOLIFY_APP_UUID_${{ steps.secrets.outputs.service_upper }}_DEV is not set!"
            echo ""
            echo "To fix this:"
            echo "1. Go to your Coolify instance → Applications → ${{ inputs.service-name }}"
            echo "2. Copy the Application UUID"
            echo "3. Add it as a repository secret:"
            echo "   Name: COOLIFY_APP_UUID_${{ steps.secrets.outputs.service_upper }}_DEV"
            echo "   Value: <application-uuid>"
            echo ""
            errors=$((errors + 1))
          else
            echo "✓ COOLIFY_APP_UUID_${{ steps.secrets.outputs.service_upper }}_DEV is configured"
          fi

          if [ $errors -gt 0 ]; then
            echo ""
            echo "Validation failed with $errors error(s)"
            exit 1
          fi

          echo "✓ All development environment validations passed"
```

- [ ] **Step 2: Validate YAML syntax**

Run: `yamllint .github/workflows/microservice-deploy.yml`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/microservice-deploy.yml
git commit -m "feat(cicd): add deploy-dev job - secret validation

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 8: Add Deploy Dev - Trigger and Wait Steps

**Files:**
- Modify: `.github/workflows/microservice-deploy.yml` (continue deploy-dev job)

**Prerequisites:** Task 7 complete

- [ ] **Step 1: Add trigger deployment step**

Continue appending to the deploy-dev job in `.github/workflows/microservice-deploy.yml`:

```yaml
      - name: Trigger Coolify Development Deployment
        id: deploy
        run: |
          COOLIFY_URL="${{ steps.secrets.outputs.coolify_url }}"
          COOLIFY_API_TOKEN="${{ steps.secrets.outputs.coolify_api_token }}"
          COOLIFY_APP_UUID="${{ steps.secrets.outputs.coolify_app_uuid }}"

          echo "Triggering Coolify development deployment..."
          echo ""
          echo "Deployment Details:"
          echo "  Environment: Development"
          echo "  Image: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}"
          echo "  Commit: ${{ github.sha }}"
          echo "  Branch: ${{ github.ref_name }}"
          echo "  App UUID: $COOLIFY_APP_UUID"
          echo ""

          # First check if Coolify is reachable
          echo "Checking connectivity to $COOLIFY_URL..."
          if ! curl -sL --max-time 10 -o /dev/null "$COOLIFY_URL"; then
            echo ""
            echo "ERROR: Cannot reach Coolify instance at $COOLIFY_URL"
            exit 1
          fi

          HTTP_CODE=$(curl -sL --max-time 30 -o /dev/null -w "%{http_code}" -X GET \
            "$COOLIFY_URL/api/v1/deploy?uuid=$COOLIFY_APP_UUID&force=true" \
            -H "Authorization: Bearer $COOLIFY_API_TOKEN")

          echo "API Response Code: $HTTP_CODE"

          if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "202" ]; then
            echo "Development deployment triggered successfully (HTTP $HTTP_CODE)"
            echo "url=$COOLIFY_URL" >> $GITHUB_OUTPUT
          else
            echo "ERROR: Coolify API returned HTTP $HTTP_CODE"
            exit 1
          fi
```

- [ ] **Step 2: Add wait for deployment step**

Continue appending to the deploy-dev job:

```yaml
      - name: Wait for Development Deployment
        timeout-minutes: ${{ inputs.deploy-timeout-minutes }}
        run: |
          COOLIFY_URL="${{ steps.secrets.outputs.coolify_url }}"
          COOLIFY_API_TOKEN="${{ steps.secrets.outputs.coolify_api_token }}"
          COOLIFY_APP_UUID="${{ steps.secrets.outputs.coolify_app_uuid }}"

          echo "Waiting for development deployment to complete..."
          echo ""

          MAX_RETRIES=30
          RETRY_COUNT=0

          while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
            RESPONSE=$(curl -s -H "Authorization: Bearer $COOLIFY_API_TOKEN" \
              "$COOLIFY_URL/api/v1/applications/$COOLIFY_APP_UUID" 2>/dev/null || echo '{"status": "unknown"}')

            STATUS=$(echo "$RESPONSE" | jq -r '.status // "unknown"')

            case "$STATUS" in
              "running"|"running:"*)
                echo "Development deployment completed successfully! (status: $STATUS)"
                exit 0
                ;;
              "error"|"failed")
                echo "Development deployment failed!"
                echo "Response: $RESPONSE"
                exit 1
                ;;
              "building"|"deploying")
                echo "Deployment in progress... ($STATUS) - attempt $((RETRY_COUNT+1))/$MAX_RETRIES"
                ;;
              *)
                echo "Waiting for deployment... (status: $STATUS) - attempt $((RETRY_COUNT+1))/$MAX_RETRIES"
                ;;
            esac

            RETRY_COUNT=$((RETRY_COUNT+1))
            sleep 10
          done

          echo "Deployment status check timed out after $((MAX_RETRIES * 10)) seconds"
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/microservice-deploy.yml
git commit -m "feat(cicd): add deploy-dev trigger and wait steps

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 9: Add Deploy Dev - Health Check and Verification

**Files:**
- Modify: `.github/workflows/microservice-deploy.yml` (continue deploy-dev job)

**Prerequisites:** Task 8 complete

- [ ] **Step 1: Add health check step**

Continue appending to the deploy-dev job:

```yaml
      - name: Verify Application Health (Development)
        timeout-minutes: ${{ inputs.health-check-timeout-minutes }}
        run: |
          SERVICE_URL="${{ steps.secrets.outputs.service_url }}"

          if [ -z "$SERVICE_URL" ]; then
            echo "WARNING: SERVICE_URL_${{ steps.secrets.outputs.service_upper }}_DEV is not set. Skipping health verification."
            exit 0
          fi

          echo "Verifying application health at $SERVICE_URL${{ inputs.health-check-path }}..."
          echo ""

          MAX_RETRIES=30
          RETRY_COUNT=0

          while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
            HTTP_CODE=$(curl -s -o /tmp/health_response.json -w "%{http_code}" "$SERVICE_URL${{ inputs.health-check-path }}" 2>/dev/null || echo "000")

            if [ "$HTTP_CODE" = "200" ]; then
              STATUS=$(jq -r '.status // "unknown"' /tmp/health_response.json 2>/dev/null || echo "unknown")
            else
              STATUS="unknown"
            fi

            if [ "$STATUS" = "UP" ]; then
              echo "✓ Application health check passed!"
              cat /tmp/health_response.json
              exit 0
            fi

            echo "Health check attempt $((RETRY_COUNT+1))/$MAX_RETRIES: status=$STATUS"
            RETRY_COUNT=$((RETRY_COUNT+1))
            sleep 2
          done

          echo "ERROR: Application health check failed after $MAX_RETRIES attempts"
          exit 1
```

- [ ] **Step 2: Add version verification step**

Continue appending to the deploy-dev job:

```yaml
      - name: Verify Deployed Version (Development)
        timeout-minutes: ${{ inputs.health-check-timeout-minutes }}
        run: |
          SERVICE_URL="${{ steps.secrets.outputs.service_url }}"

          if [ -z "$SERVICE_URL" ]; then
            echo "WARNING: SERVICE_URL_${{ steps.secrets.outputs.service_upper }}_DEV is not set. Skipping version verification."
            exit 0
          fi

          EXPECTED_SHA_SHORT=$(echo "${{ github.sha }}" | cut -c1-7)
          echo "Waiting for correct version to be deployed..."
          echo "Expected SHA: $EXPECTED_SHA_SHORT"
          echo ""

          MAX_RETRIES=60
          RETRY_COUNT=0

          while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
            HTTP_CODE=$(curl -s -o /tmp/info_response.json -w "%{http_code}" "$SERVICE_URL${{ inputs.info-endpoint-path }}" 2>/dev/null || echo "000")

            if [ "$HTTP_CODE" = "200" ]; then
              DEPLOYED_VERSION=$(jq -r '.build.version // "unknown"' /tmp/info_response.json 2>/dev/null || echo "unknown")
            else
              DEPLOYED_VERSION="unknown"
            fi

            DEPLOYED_SHA_SHORT=$(echo "$DEPLOYED_VERSION" | grep -oE '[a-f0-9]{7}$' || echo "")

            if [ "$DEPLOYED_SHA_SHORT" = "$EXPECTED_SHA_SHORT" ]; then
              echo "✓ Version verification passed!"
              echo "  Deployed SHA matches expected commit: $EXPECTED_SHA_SHORT"
              echo "  Full version: $DEPLOYED_VERSION"
              exit 0
            fi

            if [ "$HTTP_CODE" != "200" ]; then
              echo "Version check attempt $((RETRY_COUNT+1))/$MAX_RETRIES: HTTP $HTTP_CODE"
            else
              echo "Version check attempt $((RETRY_COUNT+1))/$MAX_RETRIES:"
              echo "  Current version: $DEPLOYED_VERSION (SHA: $DEPLOYED_SHA_SHORT)"
              echo "  Waiting for:   0.0.1-$EXPECTED_SHA_SHORT"
            fi

            RETRY_COUNT=$((RETRY_COUNT+1))
            sleep 5
          done

          echo "ERROR: Version verification timed out"
          exit 1
```

- [ ] **Step 3: Add deployment summary step**

Continue appending to the deploy-dev job:

```yaml
      - name: Development Deployment Summary
        if: always()
        run: |
          echo ""
          echo "============================================================"
          echo "           Development Deployment Summary                   "
          echo "============================================================"
          echo ""
          echo "Service: ${{ inputs.service-name }}"
          echo "Image: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}"
          echo "Version: 0.0.1-$(echo '${{ github.sha }}' | cut -c1-7)"
          echo "Branch: ${{ github.ref_name }}"
          echo ""

          if [ "${{ job.status }}" == "success" ]; then
            echo "✓ Development deployment completed successfully!"
          else
            echo "✗ Development deployment failed or was cancelled"
          fi
          echo ""
```

- [ ] **Step 4: Validate YAML syntax**

Run: `yamllint .github/workflows/microservice-deploy.yml`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/microservice-deploy.yml
git commit -m "feat(cicd): add deploy-dev health check and verification

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 10: Add Deploy Production Job

**Files:**
- Modify: `.github/workflows/microservice-deploy.yml` (after deploy-dev job)

**Prerequisites:** Task 9 complete

- [ ] **Step 1: Add deploy-prod job**

Append to `.github/workflows/microservice-deploy.yml` after the deploy-dev job (copy of deploy-dev with `_PROD` instead of `_DEV`):

```yaml
  # -----------------------------------------------------------------------------
  # Deploy to Production Environment (Coolify)
  # -----------------------------------------------------------------------------
  deploy-prod:
    name: Deploy to Production
    needs: build-image
    if: |
      github.event_name != 'pull_request' && (
        startsWith(github.ref, 'refs/tags/v') ||
        (github.event_name == 'workflow_dispatch' && github.event.inputs.environment == 'production')
      )
    runs-on: ubuntu-latest
    environment:
      name: production
      url: ${{ steps.deploy.outputs.url || steps.secrets.outputs.coolify_url }}

    steps:
      - name: Resolve Secrets
        id: secrets
        run: |
          SERVICE_UPPER=$(echo "${{ inputs.service-name }}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
          echo "service_upper=${SERVICE_UPPER}" >> $GITHUB_OUTPUT

          COOLIFY_URL="${{ secrets.COOLIFY_URL_PROD }}"
          COOLIFY_API_TOKEN="${{ secrets.COOLIFY_API_TOKEN_PROD }}"
          COOLIFY_APP_UUID="${{ secrets[format('COOLIFY_APP_UUID_{0}_PROD', SERVICE_UPPER)] }}"
          SERVICE_URL="${{ secrets[format('SERVICE_URL_{0}_PROD', SERVICE_UPPER)] }}"

          echo "coolify_url=${COOLIFY_URL}" >> $GITHUB_OUTPUT
          echo "coolify_api_token=${COOLIFY_API_TOKEN}" >> $GITHUB_OUTPUT
          echo "coolify_app_uuid=${COOLIFY_APP_UUID}" >> $GITHUB_OUTPUT
          echo "service_url=${SERVICE_URL}" >> $GITHUB_OUTPUT

      - name: Validate Production Secrets
        id: validate
        run: |
          echo "Validating Coolify production configuration..."

          errors=0

          if [ -z "${{ steps.secrets.outputs.coolify_url }}" ]; then
            echo "ERROR: COOLIFY_URL_PROD secret is not set!"
            errors=$((errors + 1))
          else
            echo "✓ COOLIFY_URL_PROD is configured"
          fi

          if [ -z "${{ steps.secrets.outputs.coolify_api_token }}" ]; then
            echo "ERROR: COOLIFY_API_TOKEN_PROD is not set!"
            errors=$((errors + 1))
          else
            echo "✓ COOLIFY_API_TOKEN_PROD is configured"
          fi

          if [ -z "${{ steps.secrets.outputs.coolify_app_uuid }}" ]; then
            echo "ERROR: COOLIFY_APP_UUID_${{ steps.secrets.outputs.service_upper }}_PROD is not set!"
            errors=$((errors + 1))
          else
            echo "✓ COOLIFY_APP_UUID_${{ steps.secrets.outputs.service_upper }}_PROD is configured"
          fi

          if [ $errors -gt 0 ]; then
            echo "Validation failed with $errors error(s)"
            exit 1
          fi

          echo "✓ All production environment validations passed"

      - name: Trigger Coolify Production Deployment
        id: deploy
        run: |
          COOLIFY_URL="${{ steps.secrets.outputs.coolify_url }}"
          COOLIFY_API_TOKEN="${{ steps.secrets.outputs.coolify_api_token }}"
          COOLIFY_APP_UUID="${{ steps.secrets.outputs.coolify_app_uuid }}"

          echo "Triggering Coolify production deployment..."
          echo "Environment: Production"
          echo "Image: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}"
          echo "App UUID: $COOLIFY_APP_UUID"

          if ! curl -sL --max-time 10 -o /dev/null "$COOLIFY_URL"; then
            echo "ERROR: Cannot reach Coolify instance at $COOLIFY_URL"
            exit 1
          fi

          HTTP_CODE=$(curl -sL --max-time 30 -o /dev/null -w "%{http_code}" -X GET \
            "$COOLIFY_URL/api/v1/deploy?uuid=$COOLIFY_APP_UUID&force=true" \
            -H "Authorization: Bearer $COOLIFY_API_TOKEN")

          if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "202" ]; then
            echo "Production deployment triggered successfully (HTTP $HTTP_CODE)"
            echo "url=$COOLIFY_URL" >> $GITHUB_OUTPUT
          else
            echo "ERROR: Coolify API returned HTTP $HTTP_CODE"
            exit 1
          fi

      - name: Wait for Production Deployment
        timeout-minutes: ${{ inputs.deploy-timeout-minutes }}
        run: |
          COOLIFY_URL="${{ steps.secrets.outputs.coolify_url }}"
          COOLIFY_API_TOKEN="${{ steps.secrets.outputs.coolify_api_token }}"
          COOLIFY_APP_UUID="${{ steps.secrets.outputs.coolify_app_uuid }}"

          MAX_RETRIES=30
          RETRY_COUNT=0

          while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
            RESPONSE=$(curl -s -H "Authorization: Bearer $COOLIFY_API_TOKEN" \
              "$COOLIFY_URL/api/v1/applications/$COOLIFY_APP_UUID" 2>/dev/null || echo '{"status": "unknown"}')

            STATUS=$(echo "$RESPONSE" | jq -r '.status // "unknown"')

            case "$STATUS" in
              "running"|"running:"*)
                echo "Production deployment completed! (status: $STATUS)"
                exit 0
                ;;
              "error"|"failed")
                echo "Production deployment failed!"
                exit 1
                ;;
            esac

            RETRY_COUNT=$((RETRY_COUNT+1))
            sleep 10
          done

          echo "Deployment status check timed out"

      - name: Verify Application Health (Production)
        timeout-minutes: ${{ inputs.health-check-timeout-minutes }}
        run: |
          SERVICE_URL="${{ steps.secrets.outputs.service_url }}"
          if [ -z "$SERVICE_URL" ]; then
            echo "WARNING: Skipping health verification - SERVICE_URL_${{ steps.secrets.outputs.service_upper }}_PROD not set"
            exit 0
          fi

          MAX_RETRIES=30
          RETRY_COUNT=0

          while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
            HTTP_CODE=$(curl -s -o /tmp/health.json -w "%{http_code}" "$SERVICE_URL${{ inputs.health-check-path }}" 2>/dev/null || echo "000")
            STATUS=$(jq -r '.status // "unknown"' /tmp/health.json 2>/dev/null || echo "unknown")

            if [ "$STATUS" = "UP" ]; then
              echo "✓ Health check passed!"
              exit 0
            fi
            RETRY_COUNT=$((RETRY_COUNT+1))
            sleep 2
          done
          exit 1

      - name: Verify Deployed Version (Production)
        timeout-minutes: ${{ inputs.health-check-timeout-minutes }}
        run: |
          SERVICE_URL="${{ steps.secrets.outputs.service_url }}"
          if [ -z "$SERVICE_URL" ]; then
            echo "WARNING: Skipping version verification"
            exit 0
          fi

          EXPECTED_SHA_SHORT=$(echo "${{ github.sha }}" | cut -c1-7)
          MAX_RETRIES=60
          RETRY_COUNT=0

          while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
            HTTP_CODE=$(curl -s -o /tmp/info.json -w "%{http_code}" "$SERVICE_URL${{ inputs.info-endpoint-path }}" 2>/dev/null || echo "000")
            DEPLOYED_VERSION=$(jq -r '.build.version // "unknown"' /tmp/info.json 2>/dev/null || echo "unknown")
            DEPLOYED_SHA_SHORT=$(echo "$DEPLOYED_VERSION" | grep -oE '[a-f0-9]{7}$' || echo "")

            if [ "$DEPLOYED_SHA_SHORT" = "$EXPECTED_SHA_SHORT" ]; then
              echo "✓ Version verification passed! SHA: $EXPECTED_SHA_SHORT"
              exit 0
            fi
            RETRY_COUNT=$((RETRY_COUNT+1))
            sleep 5
          done
          exit 1

      - name: Production Deployment Summary
        if: always()
        run: |
          echo "============================================================"
          echo "           Production Deployment Summary                    "
          echo "============================================================"
          echo "Service: ${{ inputs.service-name }}"
          echo "Image: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}"
          if [ "${{ job.status }}" == "success" ]; then
            echo "✓ Production deployment completed successfully!"
          else
            echo "✗ Production deployment failed"
          fi
```

- [ ] **Step 2: Validate YAML syntax**

Run: `yamllint .github/workflows/microservice-deploy.yml`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/microservice-deploy.yml
git commit -m "feat(cicd): add deploy-prod job with full pipeline

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 11: Update Infrastructure README

**Files:**
- Modify: `README.md`

**Prerequisites:** Task 10 complete

- [ ] **Step 1: Add reusable workflow documentation**

Add to `README.md` after the CI/CD section:

```markdown
### Reusable Microservice Deploy Workflow

The `microservice-deploy.yml` reusable workflow centralizes CI/CD for Java microservices deploying to Coolify.

**Usage in a service repository:**

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

**Required Secrets (per service):**

| Secret | Description |
|--------|-------------|
| `COOLIFY_APP_UUID_{SERVICE}_DEV` | Application UUID in Coolify (dev) |
| `COOLIFY_APP_UUID_{SERVICE}_PROD` | Application UUID in Coolify (prod) |
| `SERVICE_URL_{SERVICE}_DEV` | Service public URL for health checks (dev) |
| `SERVICE_URL_{SERVICE}_PROD` | Service public URL for health checks (prod) |

**Secret naming:** Transform service name to uppercase with underscores:
- `platform-user-service` → `PLATFORM_USER_SERVICE`
- Example: `COOLIFY_APP_UUID_PLATFORM_USER_SERVICE_DEV`

**Optional Secrets (infrastructure level):**

| Secret | Description |
|--------|-------------|
| `COOLIFY_URL_DEV` / `COOLIFY_URL_PROD` | Coolify instance URL |
| `COOLIFY_API_TOKEN_DEV` / `COOLIFY_API_TOKEN_PROD` | Coolify API token |
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document microservice-deploy reusable workflow

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 12: Create Service Workflow for platform-user-service

**Files:**
- Create: `platform-user-service/.github/workflows/deploy.yml` (minimal version)

**Prerequisites:** Task 11 complete (infrastructure workflow pushed to main)

- [ ] **Step 1: Create minimal service workflow**

In `platform-user-service` repository, create `.github/workflows/deploy.yml`:

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

- [ ] **Step 2: Validate YAML syntax**

Run: `yamllint .github/workflows/deploy.yml`
Expected: No errors.

- [ ] **Step 3: Commit and push**

```bash
git add .github/workflows/deploy.yml
git commit -m "refactor(cicd): use centralized reusable workflow

Replaces 837-line workflow with 25-line caller.
All CI/CD logic now in infrastructure repo.

Required secrets: COOLIFY_APP_UUID_PLATFORM_USER_SERVICE_DEV/PROD

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
git push origin main
```

---

## Task 13: Create Service Workflow for platform-file-management-service

**Files:**
- Create: `platform-file-management-service/.github/workflows/deploy.yml` (minimal version)

**Prerequisites:** Task 12 complete (test with one service first)

- [ ] **Step 1: Create minimal service workflow**

In `platform-file-management-service` repository, create `.github/workflows/deploy.yml`:

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
      service-name: platform-file-management-service
      java-version: '17'
    secrets: inherit
```

- [ ] **Step 2: Validate YAML syntax**

Run: `yamllint .github/workflows/deploy.yml`
Expected: No errors.

- [ ] **Step 3: Commit and push**

```bash
git add .github/workflows/deploy.yml
git commit -m "refactor(cicd): use centralized reusable workflow

Replaces 837-line workflow with 25-line caller.
All CI/CD logic now in infrastructure repo.

Required secrets: COOLIFY_APP_UUID_PLATFORM_FILE_MANAGEMENT_SERVICE_DEV/PROD

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
git push origin main
```

---

## Task 14: Test and Verify

**Files:**
- Test: All service repositories

**Prerequisites:** Task 13 complete

- [ ] **Step 1: Trigger test deployment**

Push a test commit to `platform-user-service` to verify the new workflow works:

```bash
# In platform-user-service repo
echo "# Testing new workflow" >> README.md
git add README.md
git commit -m "test: verify centralized workflow"
git push origin main
```

- [ ] **Step 2: Monitor GitHub Actions**

Go to GitHub Actions tab and verify:
1. Workflow triggers on push
2. Validate job passes
3. Build and test job completes
4. Docker image builds and pushes
5. Deploy to dev succeeds (if secrets configured)

- [ ] **Step 3: Verify secrets are resolved**

Check job logs to confirm secrets are resolved correctly:
- Look for "✓ COOLIFY_APP_UUID_PLATFORM_USER_SERVICE_DEV is configured"

- [ ] **Step 4: Check for errors**

If any step fails, review logs and fix the reusable workflow in infrastructure repo.

---

## Self-Review Checklist

### Spec Coverage

| Spec Requirement | Implementation Task |
|------------------|---------------------|
| Reusable workflow with workflow_call | Task 2 |
| service-name input | Task 2 |
| java-version input | Task 2 |
| Secret naming convention | Task 6, 7, 10 |
| Validate job | Task 3 |
| Build and test job | Task 4 |
| Docker build and push job | Task 5 |
| Deploy dev job | Task 7, 8, 9 |
| Deploy prod job | Task 10 |
| Health check verification | Task 9 |
| Version verification | Task 9 |
| Service workflow template | Task 12, 13 |
| Documentation | Task 11 |

### Placeholder Scan

- [ ] No "TBD" or "TODO" in code
- [ ] All steps have concrete code/commands
- [ ] No "similar to Task X" references
- [ ] Exact file paths specified
- [ ] Complete commands with expected output

### Type Consistency

- [ ] `service-name` is kebab-case input → transformed to `SERVICE_UPPER` consistently
- [ ] Secret names use format expression correctly: `format('COOLIFY_APP_UUID_{0}_DEV', SERVICE_UPPER)`
- [ ] Job dependencies: `needs: validate` → `needs: build` → `needs: build-image` → deploy jobs

---

## Execution Options

**Plan complete and saved to `docs/superpowers/plans/2026-03-29-centralized-cicd-implementation.md`.**

Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
