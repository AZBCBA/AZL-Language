.PHONY: test ci predeploy check-placeholders install-git-hooks examples branch-protection-apply branch-protection-verify branch-protection-contract

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
