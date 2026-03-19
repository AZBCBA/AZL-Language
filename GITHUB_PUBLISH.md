# Publishing AZL Language on GitHub

This repo is set up so others can **use** and **contribute** to AZL on GitHub. Your remote is already configured: `origin` → `https://github.com/AZBCBA/AZL-Language.git`.

## What’s in place for users and contributors

- **README.md** — Project intro, AZL identity (not Java/TypeScript), Installation (clone + run), Quick Start, Language Reference, Project Structure, Contributing link.
- **LICENSE** — MIT at repo root.
- **docs/CONTRIBUTING.md** — How to contribute (native-first AZL); points to AZL rules and spec.
- **docs/language/AZL_LANGUAGE_RULES.md** — AZL rules and identity.
- **docs/language/AZL_CURRENT_SPECIFICATION.md** — Current syntax and behavior.
- **docs/language/GRAMMAR.md** — Grammar reference (parser in AZL).
- **SECURITY.md** — How to report vulnerabilities.
- **CODE_OF_CONDUCT.md** — Contributor Covenant.
- **.github/ISSUE_TEMPLATE/** — Bug report and feature request templates.
- **.github/PULL_REQUEST_TEMPLATE.md** — PR checklist (CONTRIBUTING, docs, no placeholders).
- **.gitignore** — AZL runtime artifacts, logs, local training data so the repo stays clean.

## Push to GitHub (main branch)

From a machine with internet access, run:

```bash
./scripts/push_to_github.sh
```

If you see "Could not resolve host: github.com" or similar, run that script from your local machine (or any host that can reach GitHub). If push is rejected because the remote changed, run: `git push origin main --force`.

---

1. **Review what will be committed**
   ```bash
   git status
   ```
   Files under `.azl/` (daemon, pid, tokens, logs) and other ignored paths should no longer show as modified once ignored.

2. **Stage what you want to publish**
   - Add new docs and community files:
   ```bash
   git add LICENSE CHANGELOG.md SECURITY.md CODE_OF_CONDUCT.md GITHUB_PUBLISH.md
   git add README.md .gitignore
   git add docs/README.md docs/CONTRIBUTING.md docs/advanced_features.md
   git add docs/language/AZL_CURRENT_SPECIFICATION.md docs/language/AZL_LANGUAGE_RULES.md docs/language/GRAMMAR.md
   git add azl/docs/README.md
   git add .github/ISSUE_TEMPLATE/ .github/PULL_REQUEST_TEMPLATE.md
   ```
   - Add any code/docs you want public (e.g. `azl/`, native scripts, docs, workflows).

3. **Commit and push**
   ```bash
   git commit -m "Docs and GitHub readiness: LICENSE, CONTRIBUTING, AZL rules, grammar, security, CoC, issue/PR templates, Installation"
   git push -u origin main
   ```

4. **Optional: repo settings on GitHub**
   - **Settings → General**: add description and website/topics so people can find the repo.
   - **Settings → Branches**: add branch protection for `main` (e.g. require PR reviews) if you want.
   - **Insights → Community**: GitHub will suggest SECURITY.md, CODE_OF_CONDUCT.md, CONTRIBUTING, etc.; you’ve already added them.

## After publish

- **Use**: Anyone can clone and run `bash scripts/start_azl_native_mode.sh` (see README Installation).
- **Contribute**: Contributors open issues (bug/feature templates) and PRs (PR template + CONTRIBUTING and AZL rules).

If you want, we can next refine exactly which files to stage (e.g. only core AZL + docs and exclude training/LLM scripts) or add a `requirements.txt` and a one-line “Run tests” in README.
