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
| `MEDIA_ROOT` | Configure the scanning target path. |
| (Default value) | Defaults to `/media` (standard path in the Docker container). |

---

## Manual Execution (PowerShell 7+)

Run the script manually using `pwsh`:

```powershell
pwsh -File Sync-AbsToBookOrbit.ps1 -MediaRoot "C:\path\to\your\audiobooks"
```

### Script Parameters

- `-MediaRoot` *(string)*: Specify the directory path to scan. Overrides environment variables.
- `-Force` *(switch)*: Force regeneration of all `metadata.opf` files regardless of timestamps or file existence.

---

## Docker Usage

The Docker container runs the sync process inside a lightweight PowerShell container on startup.

### Pushing to GitHub & Pulling Down

This repository contains a GitHub Actions workflow that automatically builds and publishes the container to **GitHub Container Registry (GHCR)** on every push to the `main` or `master` branch.

To run the container:

```bash
docker run -d \
  --name sync-abs-to-book-orbit \
  -v /path/to/your/audiobooks:/media \
  ghcr.io/<your-github-username>/sync-abs-to-book-orbit:latest
```

### Custom Mount Paths

If you mount your media library somewhere other than `/media` in the container, pass the path via `MEDIA_ROOT`:

```bash
docker run -d \
  --name sync-abs-to-book-orbit \
  -v /path/to/your/audiobooks:/my-books \
  -e MEDIA_ROOT=/my-books \
  ghcr.io/<your-github-username>/sync-abs-to-book-orbit:latest
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
