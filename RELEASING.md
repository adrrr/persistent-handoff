# Releasing

`main` is the release channel. The marketplace clones the default branch, so what is merged is what the next person installs. No staging branch, no pre-release step.

1. Bump `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` to the same version, add the matching `## [X.Y.Z]` section to `CHANGELOG.md`, add its compare link at the bottom of that file, and repoint `[Unreleased]` there at the new tag. Case 9 of `tests/manifests.sh` ties the two manifests to each other, case 11 ties them to the changelog's top entry.
2. `bash tests/hook.sh` and `bash tests/manifests.sh`, both green.
3. `claude plugin validate .`
4. Open a PR. CI has to be green on Ubuntu, macOS and Windows.
5. Check `actions/checkout` in `.github/workflows/tests.yml` is still pinned to a SHA, and refresh the pin if it is behind. There is no dependabot on this repo on purpose, one action and a bump nobody reads.
6. Merge. The release goes out to installers at that moment, before the tag exists.
7. Tag on `main`: `git tag vX.Y.Z && git push origin vX.Y.Z`.
8. Create the GitHub release from that tag. The body is the changelog section you wrote in step 1, copied as is.
