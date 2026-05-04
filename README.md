# Containerizing the Forest Vegetation Simulator
The [**Forest Vegetation Simulator (FVS)**](https://github.com/USDAForestService/ForestVegetationSimulator) is a forest growth and yield model maintained by the USDA Forest Service. To allow FVS to be utilized in a reproducible, automated, or cloud-native context we have created this repository to provide:

- A repeatable, automated build process that tracks upstream releases
- Executable runtime environments that can be invoked programmatically
- Version traceability so simulation outputs can be tied to the exact FVS version used
- Minimal operational overhead as new FVS releases are published ~quarterly

This repository builds FVS from source into a **single runtime image per upstream release**, with all regional variants included. Images are published to **GitHub Container Registry (GHCR)**.

| | |
|--|--|
| **Image** | `ghcr.io/vibrant-planet-open-science/fvs-runtime:<FVS_TAG>` and `:latest` |
| **Workflows** | [`.github/workflows/poll-upstream.yml`](.github/workflows/poll-upstream.yml), [`.github/workflows/build-runtime.yml`](.github/workflows/build-runtime.yml) |
| **Local tests** | Install FVS binaries under `/usr/local/bin` (or extract from the image), Fortran runtimes (`libgfortran5`, `libquadmath0` on Ubuntu), then `pip install pytest` and `pytest tests/ -v` |

---

## Functionality
This repository establishes a few automations as GitHub Actions to:
- Detect new releases of FVS from the upstream repository automatically
- Build all 22 of the US regional variants for each detected release (the Canadian variants currently have broken build recipes)
- Produce a single versioned runtime image per release containing all variants
- Support invocation by variant name and accept a keyfile as the primary input
- Support pass-through of FVS command-line options (`--keywordfile`, `--stoppoint`, `--restart`)
- Mount an external data directory as the FVS working directory so keyfiles, databases, and outputs are accessible to the caller
- Tag images with both a version-pinned tag and a rolling `latest` tag
- All regional variants must pass existing tests in this repo before any image is pushed to the registry
- Images are retained for the last few releases based on a quarterly release cadence by USFS. Older versions are evicted from the registry.

---

## Repository layout

```
.
├── .github/
│   └── workflows/
│       ├── poll-upstream.yml       # Scheduled: detects new FVS releases
│       └── build-runtime.yml       # Dispatched: matrix build + assembly + test + push
├── docker/
│   ├── Dockerfile.variant          # Per-variant build (matrix jobs)
│   ├── Dockerfile.runtime          # Final runtime image
│   └── entrypoint.sh               # Container entrypoint (fvs-run)
├── scripts/
│   └── evict.sh                    # Deletes GHCR package versions for evicted tags
├── tests/
│   ├── test_fvs_build.py           # Pytest per variant + keyfiles/
│   └── keyfiles/
└── releases.json                   # Newest-first list of retained FVS release tags
```

---

## Workflow stages

### Stage 1 — Upstream polling (`poll-upstream.yml`)

Detects when the upstream FVS repo publishes a new release and triggers the build. Runs on a daily cron and can be run manually.

Reads `releases.json` for the most recently built version, queries the GitHub API for the latest upstream tag (releases API first, then tags). If they differ, dispatches `build-runtime.yml` with the new tag. It does not modify `releases.json`; only a successful build updates that file.

```
[cron / manual]
        │
        ▼
 Query GitHub API ──► Compare to releases.json
        │
        ├── No change ──► Exit
        │
        └── New version ──► Dispatch build-runtime.yml { fvs_version }
```

### Stage 2 — Matrix variant build (`build-runtime.yml`)

Each of 24 jobs compiles one variant; binaries are uploaded as **GitHub Actions artifacts** (short retention). Nothing is pushed to a registry in this stage.

### Stage 3 — Runtime assembly (`build-runtime.yml`)

After all matrix jobs succeed, artifacts are downloaded, fanned into `build-context/usr/local/bin/` and `build-context/usr/local/lib/`, and `docker/Dockerfile.runtime` builds the image locally (not pushed yet).

### Stage 4 — Tests (`build-runtime.yml`)

Binaries are copied from the local image onto the runner; Fortran runtimes are installed; **`pytest tests/`** runs. On failure, nothing is pushed and `releases.json` is unchanged.

### Stage 5 — Push and release management (`build-runtime.yml`)

Log in to GHCR, push version tag and `latest`, update `releases.json`, run `scripts/evict.sh` if a version fell off the retention list, commit `releases.json` back to the repo.

---

## Using the image

### Direct invocation

The entrypoint (`fvs-run`) takes the variant name and keyfile; remaining args go to FVS. Mount your workdir at `/data`.

```bash
docker run --rm \
  -v /path/to/workdir:/data \
  ghcr.io/vibrant-planet-open-science/fvs-runtime:latest \
  FVSak myrun.key
```

```bash
# Stop point
docker run --rm \
  -v /path/to/workdir:/data \
  ghcr.io/YOUR_ORG/fvs-runtime:latest \
  FVSak myrun.key --stoppoint=1,2040,myrun.stop
```

```bash
# Restart
docker run --rm \
  -v /path/to/workdir:/data \
  ghcr.io/YOUR_ORG/fvs-runtime:latest \
  FVSak --restart=myrun.stop
```

### As a build stage

```dockerfile
FROM ghcr.io/vibrant-planet-open-science/fvs-runtime:latest AS fvs
FROM ubuntu:22.04
COPY --from=fvs /usr/local/lib/FVSak.so /opt/myapp/lib/
COPY --from=fvs /usr/local/bin/FVSak    /opt/myapp/bin/
```

### Data directory (`/data`)

| File | Role |
|------|------|
| `<run>.key` | FVS keyword file (input) |
| `<db>.db` | SQLite database referenced by the keyfile (input/output) |

Outputs (`*.out`, `*.trl`, `*.sum`, etc.) are written under `/data`. Paths in the keyfile should be relative to `/data` or use `/data/...`.

---

## Version retention

`releases.json` is a JSON array, newest first, for example:

```json
["FS2025.4c", "FS2025.3", "FS2025.2", "FS2024.4"]
```

The limit is **`KEEP_RELEASES`** in `.github/workflows/build-runtime.yml` (default `4`). When a new version is added beyond that count, the oldest tag is removed from the file and its GHCR package version is deleted via `scripts/evict.sh`. Downstream services can treat this list as the supported version window.
