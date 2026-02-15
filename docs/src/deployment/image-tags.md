# Image Tags

Liteskill Docker images are built and published via GitHub Actions to GitHub Container Registry (GHCR). The CI/CD pipeline runs tests, then builds multi-architecture images (linux/amd64 and linux/arm64).

## CI/CD Pipeline

The Docker workflow (`.github/workflows/docker.yml`) triggers on:

- **Push to `main`** branch
- **Tags** matching `v*.*.*` (semantic version releases)
- **Pull requests** targeting `main`

### Pipeline Steps

1. **Test job**: Runs the full test suite against PostgreSQL (pgvector:pg16)
   - Compiles with `--warnings-as-errors`
   - Checks formatting with `mix format --check-formatted`
   - Runs all tests with `mix test`

2. **Docker job** (depends on test passing):
   - Sets up QEMU for multi-architecture builds
   - Sets up Docker Buildx
   - Logs into GitHub Container Registry (skipped for PRs)
   - Extracts metadata for tagging
   - Builds and pushes the image (push skipped for PRs)

## Tagging Strategy

| Event | Tags Generated | Pushed to Registry? |
|-------|---------------|---------------------|
| Push to `main` | `main`, `sha-<commit-hash>` | Yes |
| Tag `v1.2.3` | `1.2.3`, `1.2`, `sha-<commit-hash>` | Yes |
| Pull request | `pr-<number>` | No (build only) |

### Tag Details

- **`main`**: Always points to the latest commit on the main branch. Rolling tag -- overwritten on each push.
- **`sha-<hash>`**: Immutable tag tied to a specific commit. Useful for pinning deployments to exact versions.
- **`X.Y.Z`** (e.g., `1.2.3`): Full semantic version tag, created from git tags.
- **`X.Y`** (e.g., `1.2`): Minor version tag, points to the latest patch release in that minor series.
- **`pr-<number>`**: Pull request builds. Images are built to verify the Dockerfile works but are not pushed to the registry.

## Image Registry

Images are published to GitHub Container Registry:

```
ghcr.io/<owner>/liteskill
```

Replace `<owner>` with the GitHub organization or user that owns the repository.

## Using a Published Image

To use a pre-built image instead of building from source, update your `docker-compose.yml`:

```yaml
app:
  # Replace this:
  # build: .

  # With this:
  image: ghcr.io/<owner>/liteskill:latest

  # Or pin to a specific version:
  # image: ghcr.io/<owner>/liteskill:1.2.3

  # Or pin to a specific commit:
  # image: ghcr.io/<owner>/liteskill:sha-abc1234

  restart: unless-stopped
  depends_on:
    db:
      condition: service_healthy
  ports:
    - "4000:4000"
  environment:
    # ... same environment variables ...
```

Do the same for the `migrate` service if you use it.

## Multi-Architecture Support

Images are built for both `linux/amd64` and `linux/arm64` platforms, supporting deployment on:

- Standard x86-64 servers and cloud instances
- ARM-based servers (e.g., AWS Graviton, Apple Silicon for local development)

Docker automatically selects the correct architecture when pulling.

## Build Caching

The CI pipeline uses GitHub Actions cache (`type=gha`) for Docker layer caching, significantly speeding up subsequent builds when only application code changes (dependency layers are cached).
