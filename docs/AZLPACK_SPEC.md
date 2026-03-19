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

**Local registry:** `python3 tools/registry_server.py` serves from `AZL_REGISTRY_DIR` (default `.azl/packages`). Package layout: `<dir>/<name>/<version>/pkg.tar.gz`.

## Install Command (Future)

```bash
azl install azl-memory-lha3
# Resolves to .azl/packages/azl-memory-lha3/
# Adds to AZL_COMPONENT_PATH or equivalent
```
