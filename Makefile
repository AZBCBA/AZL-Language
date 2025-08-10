.PHONY: test ci predeploy check-placeholders install-git-hooks

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


