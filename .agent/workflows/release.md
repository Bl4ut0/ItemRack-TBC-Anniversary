# Unified Release Workflow

This is the only release workflow. It has two tracks:

- **Beta:** stays on `dev`, publishes a GitHub prerelease, installs that exact build locally, then restores the `dev` TOCs.
- **Primary:** first creates and pushes a locally testable candidate on the production branch. It creates no tag or public release until the user explicitly accepts that exact candidate. Finalization then tags and publishes it, merges it back to `dev`, and restores the `dev` TOCs.

All archives are exported from a committed Git ref. Never publish files copied from the mutable checkout. Generated archives, manifests, hashes, and post files live under `.versions/` and are intentionally not committed.

CurseForge publication remains manual. The final build generates `CURSEFORGE_RELEASE.md`, but testing a primary candidate does not publish anything to CurseForge.

## Questions to ask first

Ask the user for:

1. Track: `beta` or `primary`.
2. Version:
   - Beta: `X.Y[-Z]-betaN`, such as `4.43-beta5`.
   - Primary: `X.Y[-Z]`, such as `4.43`.
3. Release date in `YYYY-MM-DD`.
4. Authorization appropriate to the phase:
   - Beta: push `dev` and an annotated tag, publish a GitHub prerelease, and replace detected local addon folders.
   - Primary candidate: merge/push `dev` to the detected production branch and replace detected local addon folders. This does **not** authorize a tag or public release.
   - Primary finalize: tag and publish the accepted candidate, merge it back to `dev`, and reset/push the `dev` TOCs.

## Shared preflight

Run from a clean `dev` checkout:

```powershell
git switch dev
git pull --ff-only origin dev
git fetch origin --prune --tags
git status --short
npm.cmd ci
npm.cmd test
```

Stop if tracked files are dirty, addon source contains untracked files, validation fails, or the requested tag already exists locally or remotely. `.versions/` and `.release-audit/` are generated data, not release source.

Resolve the production branch without renaming it:

```powershell
git show-ref --verify --quiet refs/remotes/origin/main
$releaseBranch = if ($LASTEXITCODE -eq 0) { 'main' } else { 'master' }
$releaseBranch
```

Record the printed branch as `{ReleaseBranch}`. Likewise, replace `{CandidateCommit}` and `{TestedSHA256}` below with literal recorded values when commands may run in separate terminal calls.

## Track A: Beta

The beta track never switches to or pushes the production branch.

1. Prepare release metadata on `dev`. Validation runs before the four metadata files are replaced. The command is retryable if only those generated metadata changes are present.

   ```powershell
   node .tools/create_release.js prepare beta {Version} --date {Date}
   git diff -- CHANGELOG.md ItemRack/Changelog.txt ItemRack/ItemRack.toc ItemRackOptions/ItemRackOptions.toc
   npm.cmd test
   ```

2. Commit only the reviewed metadata, push `dev`, and record the exact commit:

   ```powershell
   git add CHANGELOG.md ItemRack/Changelog.txt ItemRack/ItemRack.toc ItemRackOptions/ItemRackOptions.toc
   git diff --cached --check
   git commit -m "Beta release {Version}"
   git push origin dev
   git rev-parse HEAD
   ```

3. Create the annotated beta tag at that recorded commit and push it. Never move an existing tag.

   ```powershell
   git tag -a "v{Version}" {BetaCommit} -m "Beta release v{Version}"
   git push origin "refs/tags/v{Version}"
   ```

4. Build from the exact tag. The builder uses `git archive`, verifies every extracted file against the commit's blob tree, and records `SOURCE_COMMIT.txt` and `SOURCE_TREE.txt`.

   ```powershell
   node .tools/create_release.js build beta {Version} --ref "v{Version}"
   Get-Content -LiteralPath ".versions\Release\v{Version}\SOURCE_COMMIT.txt"
   Get-FileHash -Algorithm SHA256 -LiteralPath ".versions\Compressed\ItemRack-anniversary-{Version}.zip"
   Get-Content -LiteralPath ".versions\Compressed\ItemRack-anniversary-{Version}.zip.sha256"
   ```

5. Publish the GitHub prerelease from the already-pushed tag:

   ```powershell
   gh release create "v{Version}" ".versions\Compressed\ItemRack-anniversary-{Version}.zip" ".versions\Compressed\ItemRack-anniversary-{Version}.zip.sha256" --title "v{Version} (Beta)" --notes-file ".versions\Release\v{Version}\GITHUB_RELEASE.md" --prerelease --latest=false --verify-tag
   ```

6. Install the exact staged tag locally. Run the script in the current PowerShell process so `-Confirm:$false` remains a switch value on Windows PowerShell 5.1.

   ```powershell
   & .\.tools\install_local.ps1 -SourceRoot ".versions\Release\v{Version}" -Confirm:$false
   ```

   The installer must list at least one destination or fail. Verify the reported client folders before continuing.

7. Restore only the two `dev` TOCs, retain the beta changelog entry, commit, and push:

   ```powershell
   node .tools/create_release.js reset
   git add ItemRack/ItemRack.toc ItemRackOptions/ItemRackOptions.toc
   git diff --cached --check
   git commit -m "Reset development version back to Dev"
   git push origin dev
   ```

8. Report the beta tag and commit, GitHub URL, archive SHA-256, installed destinations, and generated CurseForge post path. Do not post the beta to CurseForge unless separately requested.

## Track B: Primary

### Phase 1: Create and test a candidate

1. Complete the shared preflight on `dev`. Confirm every intended fix and beta note is committed and pushed.

2. Merge tested `dev` into the detected production branch:

   ```powershell
   git switch {ReleaseBranch}
   git pull --ff-only origin {ReleaseBranch}
   git merge --no-ff dev -m "Merge dev for {Version} release candidate"
   ```

3. Prepare stable metadata on the production branch:

   ```powershell
   node .tools/create_release.js prepare stable {Version} --date {Date}
   git diff -- CHANGELOG.md ItemRack/Changelog.txt ItemRack/ItemRack.toc ItemRackOptions/ItemRackOptions.toc
   npm.cmd test
   ```

   The first candidate consolidates all `{Version}-betaN` sections plus Development into one `{Version}` section. A later correction candidate may add new Development notes to that existing stable section without recreating old beta headers.

4. Commit only reviewed release metadata. If it was already prepared, do not create an empty commit.

   ```powershell
   git add CHANGELOG.md ItemRack/Changelog.txt ItemRack/ItemRack.toc ItemRackOptions/ItemRackOptions.toc
   git diff --cached --check
   git commit -m "Prepare {Version} release candidate"
   ```

5. Push the production candidate, record its immutable commit ID, and confirm the remote branch points to it:

   ```powershell
   git push origin {ReleaseBranch}
   git rev-parse HEAD
   git rev-parse "origin/{ReleaseBranch}"
   ```

   Record the identical value as `{CandidateCommit}`. Do not create a tag or GitHub release.

6. Build from that literal commit and record the candidate hash:

   ```powershell
   node .tools/create_release.js build stable {Version} --ref {CandidateCommit}
   Get-Content -LiteralPath ".versions\Release\v{Version}\SOURCE_COMMIT.txt"
   Get-FileHash -Algorithm SHA256 -LiteralPath ".versions\Compressed\ItemRack-anniversary-{Version}.zip"
   Get-Content -LiteralPath ".versions\Compressed\ItemRack-anniversary-{Version}.zip.sha256"
   ```

   Record the SHA-256 as `{TestedSHA256}`.

7. Install the exact staged candidate locally:

   ```powershell
   & .\.tools\install_local.ps1 -SourceRoot ".versions\Release\v{Version}" -Confirm:$false
   ```

8. Stop and report the candidate commit, SHA-256, production branch, installed destinations, and test checklist. Explicitly state that no tag, GitHub release, CurseForge post, merge-back, or `dev` reset has occurred. Wait for the user's test result.

### Candidate correction loop

If testing rejects a candidate, synchronize that exact candidate back into `dev`
before making the correction. This replaces `dev`'s already-consumed beta and
Development notes with the candidate's single stable section, preventing the
next merge from reintroducing or duplicating them.

1. Confirm the production branch still points to the rejected candidate, then
   merge that literal commit into `dev`:

   ```powershell
   git switch {ReleaseBranch}
   git pull --ff-only origin {ReleaseBranch}
   $currentCandidate = git rev-parse HEAD
   if ($currentCandidate -ne "{CandidateCommit}") { throw "Production moved; create a new candidate plan before correcting it." }
   git switch dev
   git pull --ff-only origin dev
   git merge --no-ff {CandidateCommit} -m "Synchronize rejected {Version} candidate into dev"
   ```

2. Restore only the two development TOCs, test the synchronized tree, commit,
   and push it. The stable changelog section remains intact and Development is
   empty at this point.

   ```powershell
   node .tools/create_release.js reset
   npm.cmd test
   git add ItemRack/ItemRack.toc ItemRackOptions/ItemRackOptions.toc
   git diff --cached --check
   git commit -m "Restore development metadata after {Version} candidate"
   git push origin dev
   ```

3. Implement and test the correction on `dev`, add only a fresh Development
   note for that correction to both changelogs, commit/push `dev`, and repeat
   Primary Phase 1. The next prepare command folds only those fresh notes into
   the existing stable section. Record a new candidate commit and hash; the
   rejected candidate must never be tagged.

### Phase 2: Finalize an accepted candidate

Finalization requires explicit user acceptance of `{CandidateCommit}`.

1. Verify that the clean production branch and its remote still point to the accepted commit:

   ```powershell
   git switch {ReleaseBranch}
   git pull --ff-only origin {ReleaseBranch}
   git status --short
   git rev-parse HEAD
   git rev-parse "origin/{ReleaseBranch}"
   npm.cmd test
   ```

   All commit IDs must equal `{CandidateCommit}`. If they do not, stop and create/test a new candidate.

2. Create and push an annotated tag at the accepted commit:

   ```powershell
   git tag -a "v{Version}" {CandidateCommit} -m "Release v{Version}"
   git push origin "refs/tags/v{Version}"
   ```

   On a retry, if the tag already exists, verify that it peels to `{CandidateCommit}` and reuse it. Never delete or move it.

3. Rebuild from the exact tag and verify its SHA-256 equals the locally tested candidate hash:

   ```powershell
   node .tools/create_release.js build stable {Version} --ref "v{Version}"
   Get-Content -LiteralPath ".versions\Release\v{Version}\SOURCE_COMMIT.txt"
   $finalHash = (Get-FileHash -Algorithm SHA256 -LiteralPath ".versions\Compressed\ItemRack-anniversary-{Version}.zip").Hash.ToLowerInvariant()
   $testedHash = "{TestedSHA256}".ToLowerInvariant()
   if ($finalHash -ne $testedHash) { throw "Tagged archive differs from the accepted candidate." }
   ```

4. Publish the stable GitHub release:

   ```powershell
   gh release create "v{Version}" ".versions\Compressed\ItemRack-anniversary-{Version}.zip" ".versions\Compressed\ItemRack-anniversary-{Version}.zip.sha256" --title "v{Version}" --notes-file ".versions\Release\v{Version}\GITHUB_RELEASE.md" --latest --verify-tag
   ```

5. Reinstall the verified tagged staging folder locally:

   ```powershell
   & .\.tools\install_local.ps1 -SourceRoot ".versions\Release\v{Version}" -Confirm:$false
   ```

6. Merge the published history back to `dev`, restore the two TOCs to `Dev`, commit, and push:

   ```powershell
   git switch dev
   git pull --ff-only origin dev
   git merge --no-ff {ReleaseBranch} -m "Merge {Version} release back into dev"
   node .tools/create_release.js reset
   git add ItemRack/ItemRack.toc ItemRackOptions/ItemRackOptions.toc
   git diff --cached --check
   git commit -m "Reset development version back to Dev"
   git push origin dev
   ```

7. Report the production branch, accepted/tagged commit, GitHub release URL, archive SHA-256, local destinations, and `.versions\Release\v{Version}\CURSEFORGE_RELEASE.md`. CurseForge publication happens only after separate review/authorization.

## Failure handling

- Stop on validation failures, merge conflicts, missing notes, TOC mismatches, tag collisions, source-manifest mismatches, hash changes, failed installation, or publication errors.
- Metadata preparation validates before replacing files and permits a retry when only its four expected files are dirty.
- Building is safe with an otherwise dirty checkout because only the named committed ref is archived; untracked and ignored files cannot enter the zip.
- Never tag a primary candidate before the user accepts its recorded commit and hash.
- Never reset `dev` after an accepted candidate until the beta prerelease or
  primary stable release has been successfully published. The only pre-release
  exception is the documented rejected-candidate correction loop, after the
  exact rejected candidate has first been synchronized into `dev`.
- If GitHub publication fails after a tag push, rerun only exact-ref build/verification and publication against that same tag.
