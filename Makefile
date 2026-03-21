.PHONY: test ci verify verify-doc-pieces benchmark-real-world benchmark-azl-full-report measure-azl-quality measure-azl-quality-comprehensive predeploy check-placeholders install-git-hooks examples branch-protection-apply branch-protection-verify branch-protection-contract native-release-profile-complete

# One-command integration check: canonical stack, native gates, minimal + full test suite (no optional LLM benches).
# See docs/INTEGRATION_VERIFY.md
verify:
	RUN_OPTIONAL_BENCHES=0 bash scripts/run_full_repo_verification.sh

# Run every documentation-linked piece in release/doc_verification_pieces.json (not only promoted).
verify-doc-pieces:
	bash scripts/verify_documentation_pieces.sh

# Computer Language Benchmarks Game spectral-norm (C vs Python) via hyperfine — see docs/BENCHMARKS_REAL_WORLD.md
benchmark-real-world:
	bash scripts/benchmark_language_real_world.sh

# Timed report: full AZL verify + perf smoke + optional C/Python reference — see docs/BENCHMARKS_AZL_VS_REAL_WORLD.md
benchmark-azl-full-report:
	bash scripts/benchmark_azl_full_coverage_report.sh

# JSON + plain-language report — see docs/AZL_QUALITY_MEASUREMENTS_VS_PYTHON.md
measure-azl-quality:
	bash scripts/measure_azl_quality_parallel.sh

# Wider snapshot: doc promoted + reference C/Python bench + perf smoke (when runnable)
measure-azl-quality-comprehensive:
	AZL_MEASURE_COMPREHENSIVE=1 bash scripts/measure_azl_quality_parallel.sh

test:
	./scripts/run_all_tests.sh

ci:
	./scripts/check_no_placeholders.sh
	./scripts/run_all_tests.sh

predeploy:
	./scripts/pre_deploy_check.sh

check-placeholders:
	./scripts/check_no_placeholders.sh

install-git-hooks:
	./scripts/git-hooks/install.sh

examples:
	./scripts/run_examples.sh

# Maintainer: requires gh auth + repo admin (see docs/GITHUB_BRANCH_PROTECTION.md)
branch-protection-apply:
	bash scripts/gh_apply_main_branch_protection.sh

branch-protection-verify:
	bash scripts/gh_apply_main_branch_protection.sh --verify

branch-protection-contract:
	bash scripts/verify_required_github_status_checks_contract.sh

# Tier A — see docs/PROJECT_COMPLETION_STATEMENT.md (long run; optional benches off)
native-release-profile-complete:
	bash scripts/verify_native_release_profile_complete.sh
