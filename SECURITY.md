# Security Guide

## HTTP Surface Hardening
- Authentication: Bearer token via `AZL_API_TOKEN` required; reject missing/invalid tokens.
- Methods: Enforce allowed methods per route (405 otherwise).
- Input validation: For JSON payloads (e.g., /build), validate structure before use.

## Recommended Runtime Flags
- `AZL_STRICT=1` (default): halts on fatal errors like division_by_zero.
- Restrict `AZL_BUILD_API_ENABLED` in untrusted environments.

## Supply Chain
- No external runtime dependencies; sysproxy is compiled locally from `tools/sysproxy.c`.

## Next Steps
- Rate limiting and request size caps in `::net.http.server`.
- Structured JSON parser to replace naive parsing helpers.
