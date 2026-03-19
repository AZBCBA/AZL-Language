# azl-hello

Minimal distributable AZL package for registry / `azl install` dogfood.

Build tarball:

```bash
bash scripts/build_azlpack.sh
```

Install from local registry layout (`packages/registry/azl-hello/1.0.0/pkg.tar.gz`):

```bash
AZL_REGISTRY_DIR="$PWD/packages/registry" bash scripts/azl_install.sh azl-hello
```
