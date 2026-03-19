# AZL Package Format (.azlpack)

Specification for distributable AZL packages. Enables `azl install <package>` and package registry.

## Format

An `.azlpack` is a tarball (`.tar.gz`) or zip containing:

```
<package_name>/
  manifest.json      # Required: package metadata
  azl/               # AZL source files
    *.azl
  README.md          # Optional
```

## manifest.json

```json
{
  "name": "azl-memory-lha3",
  "version": "1.0.0",
  "entry": "::memory.lha3_quantum",
  "components": [
    "azl/memory/lha3_quantum_memory.azl",
    "azl/quantum/memory/lha3_quantum_engine.azl"
  ],
  "dependencies": []
}
```

| Field | Required | Description |
|-------|----------|-------------|
| name | Yes | Package identifier (lowercase, hyphens) |
| version | Yes | Semver |
| entry | No | Default entry component |
| components | Yes | List of .azl files relative to package root |
| dependencies | No | List of package names |

## Registry

Simple HTTP registry: `GET https://registry.azl.dev/<name>/<version>` returns the .azlpack tarball.

**Local registry directory** (no HTTP): `packages/registry/<name>/<version>/pkg.tar.gz`

- Build from source: `bash scripts/build_azlpack.sh` (defaults to `packages/src/azl-hello/` → `packages/registry/azl-hello/1.0.0/pkg.tar.gz`).
- **HTTP server:** `python3 tools/registry_server.py` serves from `AZL_REGISTRY_DIR` (default `.azl/packages` — override to `packages/registry` for dogfood).

## Install Command

```bash
# Local dogfood (first-party pack `azl-hello`)
bash scripts/build_azlpack.sh
AZL_REGISTRY_DIR="$PWD/packages/registry" bash scripts/azl_install.sh azl-hello

# Remote (when registry is live)
bash scripts/azl_install.sh <name>   # uses AZL_REGISTRY_URL
```

Installed layout: `AZL_PACKAGES_DIR/<name>/` (default `.azl/packages/<name>/`) with flattened `manifest.json` and `azl/` tree.

**Verification:** `scripts/verify_azlpack_local.sh` (invoked from `run_all_tests.sh`).
