# CI/CD Infrastructure

Reusable GitHub Actions composite actions for the SerenityFlow platform.

## Actions

### `actions/gradle-build`

Builds a Gradle project and uploads artifacts.

**Example:**
```yaml
- uses: serenity-flow/serenity-flow/infrastructure/cicd/actions/gradle-build@main
  with:
    java-version: '17'
    artifact-name: 'build-artifacts'
    artifact-path: 'build/libs/'
```

**Inputs:**
| Name | Default | Description |
|------|---------|-------------|
| `java-version` | `17` | Java version |
| `java-distribution` | `temurin` | JDK distribution |
| `artifact-name` | `build-artifacts` | Artifact name |
| `artifact-path` | `build/libs/` | Path to upload |

**Outputs:**
| Name | Description |
|------|-------------|
| `build-status` | Build outcome |

---

### `actions/gradle-test`

Runs Gradle tests and uploads results.

**Example:**
```yaml
- uses: serenity-flow/serenity-flow/infrastructure/cicd/actions/gradle-test@main
  with:
    java-version: '17'
    artifact-name: 'test-results'
    test-results-path: 'build/reports/tests/'
```

**Inputs:**
| Name | Default | Description |
|------|---------|-------------|
| `java-version` | `17` | Java version |
| `java-distribution` | `temurin` | JDK distribution |
| `artifact-name` | `test-results` | Artifact name |
| `test-results-path` | `build/reports/tests/` | Path to results |

**Outputs:**
| Name | Description |
|------|-------------|
| `test-status` | Test outcome |

---

### `actions/gradle-publish`

Publishes Gradle artifacts to GitHub Packages.

**Example - SNAPSHOT:**
```yaml
- uses: serenity-flow/serenity-flow/infrastructure/cicd/actions/gradle-publish@main
  with:
    github-actor: ${{ github.actor }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

**Example - Release:**
```yaml
- uses: serenity-flow/serenity-flow/infrastructure/cicd/actions/gradle-publish@main
  with:
    release-version: '1.0.0'
    github-actor: ${{ github.actor }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

**Inputs:**
| Name | Default | Description |
|------|---------|-------------|
| `java-version` | `17` | Java version |
| `java-distribution` | `temurin` | JDK distribution |
| `release-version` | `''` | If set, publishes release; else SNAPSHOT |
| `github-actor` | - | **Required** GitHub actor |
| `github-token` | - | **Required** GitHub token |

---

### `actions/maven-publish`

Publishes Maven artifacts to GitHub Packages.

**Example - SNAPSHOT:**
```yaml
- uses: serenity-flow/serenity-flow/infrastructure/cicd/actions/maven-publish@main
  with:
    github-actor: ${{ github.actor }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

**Example - Release:**
```yaml
- uses: serenity-flow/serenity-flow/infrastructure/cicd/actions/maven-publish@main
  with:
    release-version: '1.0.0'
    github-actor: ${{ github.actor }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

**Inputs:**
| Name | Default | Description |
|------|---------|-------------|
| `java-version` | `17` | Java version |
| `java-distribution` | `temurin` | JDK distribution |
| `release-version` | `''` | If set, publishes release; else SNAPSHOT |
| `github-actor` | - | **Required** GitHub actor |
| `github-token` | - | **Required** GitHub token |

---

## Usage in Platform Libraries

Each platform library should have a workflow like:

```yaml
name: CI/CD

on:
  push:
    branches: [main, develop]
    tags: ['v*']
  pull_request:
    branches: [main, develop]

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: serenity-flow/serenity-flow/infrastructure/cicd/actions/gradle-build@main
      - uses: serenity-flow/serenity-flow/infrastructure/cicd/actions/gradle-test@main

  publish:
    needs: build
    if: github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/v')
    steps:
      - uses: actions/checkout@v4
      - name: Extract version
        if: startsWith(github.ref, 'refs/tags/v')
        run: echo "VERSION=${GITHUB_REF#refs/tags/v}" >> $GITHUB_ENV
      - uses: serenity-flow/serenity-flow/infrastructure/cicd/actions/gradle-publish@main
        with:
          release-version: ${{ env.VERSION }}
          github-actor: ${{ github.actor }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

---

## Multi-Module Projects (Maven + Gradle)

For projects with both Maven and Gradle modules (like `graphql-java-codegen-plugin`), see the example workflow at:
`graphql-java-codegen-plugin/.github/workflows/release.yml`

This workflow demonstrates:
- Building and testing both Maven and Gradle modules
- Publishing Maven artifacts using `mvn deploy`
- Publishing Gradle artifacts using the Gradle publish plugin
- Creating GitHub releases automatically on tag push
