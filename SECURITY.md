# Security Policy

## Supported Versions

We release updates for the AZL Language runtime and tooling as needed. Security fixes are applied to the current main branch.

## Reporting a Vulnerability

If you believe you have found a security vulnerability in the AZL Language project:

1. **Do not** open a public GitHub issue.
2. Email the maintainers (see repository owner/links) or report via GitHub Security Advisories: **Repository → Security → Advisories → New draft**.
3. Include a clear description, steps to reproduce, and impact if possible.
4. Allow reasonable time for a fix before any public disclosure.

We will acknowledge your report and work with you to understand and address the issue.

## Scope

- AZL runtime and interpreter (`scripts/start_azl_native_mode.sh`, `azl/`), parser, compiler, and standard library.
- System interface, sysproxy bridge, and any host-facing APIs.
- Out of scope: third-party dependencies; please report to their maintainers.
