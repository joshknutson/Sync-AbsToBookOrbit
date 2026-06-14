# Sync-AbsToBookOrbit

A parallelized PowerShell script to scan your audiobook media files, locate Audiobookshelf `metadata.json` files, and automatically generate/update matching Calibre-compatible `metadata.opf` XML files. This enables metadata reading on platforms like BookOrbit, Calibre, or generic OPF readers.

## Features

- **Delta Engine:** Checks if the target `metadata.opf` already exists or if the source `metadata.json` has been updated since the OPF was last generated, avoiding redundant processing.
- **Multithreading:** Runs in parallel using PowerShell 7's `-Parallel` feature.
- **Smart Parsing:** Auto-extracts subtitles, maps long language names to ISO 639-1 two-letter codes, extracts series indices, handles single/multiple authors and narrators, and structures standard OPF metadata with proper XML namespace declarations.

---

## Configuration & Environment Variables

| Environment Variable | Description |
| :--- | :--- |
| `MEDIA_ROOT` | Configure the scanning target paths. Supports a single path or a comma-separated list of paths (e.g. `/media/books,/media/audiobooks`). |
| `CRON` | Optional. A 5-field cron expression (e.g. `*/30 * * * *` for every 30 mins) to enable scheduled background execution inside the container. If omitted, the container runs in one-shot mode and exits. |
| (Default value) | Defaults to `/media` (standard path in the Docker container). |

---

## Manual Execution (PowerShell 7+)

Run the script manually using `pwsh`. You can pass single or multiple directories to scan:

```powershell
# Single directory
pwsh -File Sync-AbsToBookOrbit.ps1 -MediaRoot "C:\path\to\your\audiobooks"

# Multiple directories (separated by commas or passed as an array)
pwsh -File Sync-AbsToBookOrbit.ps1 -MediaRoot "C:\path\to\books", "D:\path\to\audiobooks"
```

### Script Parameters

- `-MediaRoot` *(string[])*: Specify one or more directory paths to scan. Overrides environment variables. Supports comma-separated strings.
- `-Force` *(switch)*: Force regeneration of all `metadata.opf` files regardless of timestamps or file existence.

---

## Docker Usage

The Docker container runs the sync process inside a lightweight PowerShell container on startup.

### Pushing to GitHub & Pulling Down

This repository contains a GitHub Actions workflow that automatically builds and publishes the container to **GitHub Container Registry (GHCR)** on every push to the `main` or `master` branch.

To run the container:

```bash
docker run -d \
  --name sync-abstobookorbit \
  -v /path/to/your/audiobooks:/media \
  ghcr.io/joshknutson/sync-abstobookorbit:latest
```

### Custom Mount Paths & Multiple Volumes

If you mount multiple libraries or use custom mount paths, map each volume and list them in `MEDIA_ROOT` separated by a comma:

```bash
docker run -d \
  --name sync-abstobookorbit \
  -v /path/to/books:/books \
  -v /path/to/audiobooks:/audiobooks \
  -e MEDIA_ROOT=/books,/audiobooks \
  ghcr.io/joshknutson/sync-abstobookorbit:latest
```

### Cron Scheduling

To keep the container running and scan automatically on a schedule, pass a `CRON` expression:

```bash
docker run -d \
  --name sync-abstobookorbit \
  -v /path/to/audiobooks:/media \
  -e CRON="0 0 * * *" \
  ghcr.io/joshknutson/sync-abstobookorbit:latest
```

### Docker Compose

Alternatively, you can integrate this into a `docker-compose.yml` stack. Here is a configuration using multiple volumes and scheduled execution every 30 minutes:

```yaml
version: '3.8'

services:
  sync-abstobookorbit:
    image: ghcr.io/joshknutson/sync-abstobookorbit:latest
    container_name: sync-abstobookorbit
    volumes:
      - /path/to/books:/media/books
      - /path/to/audiobooks:/media/audiobooks
    environment:
      - MEDIA_ROOT=/media/books,/media/audiobooks
      - CRON=*/30 * * * *
    restart: unless-stopped
```

---

## Running Tests

An integration test script is included to verify the XML parsing, language mapping, series formatting, and delta detection logic.

To run the integration tests locally, execute:

```powershell
pwsh -File test-sync.ps1
```

---

## GitHub Actions Continuous Deployment

The workflow file [.github/workflows/docker-publish.yml](.github/workflows/docker-publish.yml) automates:
1. Docker build using the [Dockerfile](Dockerfile).
2. Authenticating with `ghcr.io` using the automatic repository `GITHUB_TOKEN`.
3. Tagging with:
   - `latest` (for the default branch)
   - Git branch name
   - Semantic versions (e.g., `v1.0.0`, `v1.0`, `v1` if a git tag is pushed)
   - Commit SHA

