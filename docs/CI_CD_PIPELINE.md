## CI/CD Pipeline

### Current Status
- Implemented: build (release), clippy, fmt, minimal smoke run, audit live paths, docker smoke.
- Next: add unit/integration tests and coverage gates per Phase 1 acceptance.

**Status:** CI/CD being added incrementally.
- Pure AZL checks replace Rust gates where applicable
- Tests (unit + integration) — executed via AZL interpreter; coverage expansion planned
- Gates:
  - No `placeholder|TODO|FIXME` in `.azl`
  - Virtual OS (fs/http/proc) paths validated by smoke tests
  - Placeholder elimination verified on each run

### CI Stages
1. Checkout, toolchain, cache
2. Build (release)
3. Lint (deny warnings) + fmt check
4. Tests (unit + integration)
5. Fuzz smoke; proptests
6. Minimal smoke run via AZL components (listeners first, boot last)
7. Audit live paths (`scripts/audit_live_path.sh`)
8. Docker image build + container smoke

### Release
- Tagged builds produce artifacts and container images
- Strict mode is enforced; experimental flags disabled


