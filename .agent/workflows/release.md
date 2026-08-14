# Unified Release Workflow

This is the canonical release workflow. It contains two tracks: **Beta** and **Primary (stable)**. Both start from tested `dev` source, produce an exact release staging folder and zip, publish an existing annotated tag to GitHub, install that exact staged build locally for testing, and finally restore the `dev` TOCs to `Dev`.

Do not use the retired `beta_release.md` or `update_version.md` procedures. Do not use `git add .` in a release. Generated archives and post files live under `.versions/` and are intentionally not committed.

## Questions to ask first

Ask the user for:

1. Release track: `beta` or `primary`.
2. Version:
   - Beta: `X.Y[-Z]-betaN`, for example `4.44-beta1`.
   - Primary: `X.Y[-Z]` with no beta suffix, for example `4.44`.
3. Release date in `YYYY-MM-DD` (default to the current local date only after confirming it).
4. Confirmation that GitHub publication, tag pushes, and replacement of detected local WoW addon folders are authorized.

CurseForge publication is not automatic. Both tracks generate a complete `CURSEFORGE_RELEASE.md` for review and posting.

## Shared preflight

Run these checks before changing version metadata:

```powershell
git switch dev
git pull --ff-only origin dev
git fetch origin --tags
git status --short
npm.cmd ci
npm.cmd test
```

Stop if tracked files are dirty, addon source contains untracked files, tests fail, or `v{Version}` already exists locally or remotely. Temporary `.release-audit/` and generated `.versions/` content are not release source.

The repository's production branch is resolved without renaming branches:

```powershell
git show-ref --verify --quiet refs/remotes/origin/main
$releaseBranch = if ($LASTEXITCODE -eq 0) { 'main' } else { 'master' }
```

Record that result as `{ReleaseBranch}` and substitute the literal branch name in later commands; do not assume a PowerShell variable will persist across separate terminal calls.

## Track A: Beta release

1. Stay on a clean, up-to-date `dev` branch.
2. Prepare the beta. This promotes a non-empty Development section into the requested beta section. If the requested beta section and TOCs are already prepared, the command verifies and packages them idempotently.

   ```powershell
   node .tools/create_release.js beta {Version} --date {Date}
   ```

3. Review the exact source and generated output:

   ```powershell
   git diff -- CHANGELOG.md ItemRack/Changelog.txt ItemRack/ItemRack.toc ItemRackOptions/ItemRackOptions.toc
   npm.cmd test
   Get-FileHash -Algorithm SHA256 -LiteralPath ".versions\Compressed\ItemRack-anniversary-{Version}.zip"
   Get-Content -LiteralPath ".versions\Compressed\ItemRack-anniversary-{Version}.zip.sha256"
   ```

4. If preparation changed tracked metadata, stage only the four reviewed files and commit. If it was already prepared, leave the clean existing `HEAD` unchanged.

   ```powershell
   git add CHANGELOG.md ItemRack/Changelog.txt ItemRack/ItemRack.toc ItemRackOptions/ItemRackOptions.toc
   git diff --cached --check
   git commit -m "Beta release {Version}"
   ```

5. Create and push an annotated tag, then push `dev`:

   ```powershell
   git tag -a "v{Version}" -m "Beta release v{Version}"
   git push origin dev
   git push origin "refs/tags/v{Version}"
   ```

6. Publish the GitHub prerelease from the verified remote tag:

   ```powershell
   gh release create "v{Version}" ".versions\Compressed\ItemRack-anniversary-{Version}.zip" ".versions\Compressed\ItemRack-anniversary-{Version}.zip.sha256" --title "v{Version} (Beta)" --notes-file ".versions\Release\v{Version}\GITHUB_RELEASE.md" --prerelease --latest=false --verify-tag
   ```

7. Install the exact staged beta locally, not the mutable checkout:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .tools/install_local.ps1 -SourceRoot ".versions\Release\v{Version}" -Confirm:$false
   ```

8. Restore `dev` metadata while retaining the beta changelog entry, commit, and push:

   ```powershell
   node .tools/create_release.js reset
   git add ItemRack/ItemRack.toc ItemRackOptions/ItemRackOptions.toc
   git diff --cached --check
   git commit -m "Reset development version back to Dev"
   git push origin dev
   ```

9. Report the GitHub release URL, archive SHA-256, local client folders updated, and the generated CurseForge post path.

## Track B: Primary (stable) release

1. Complete the shared preflight on `dev` and confirm all intended beta commits are pushed.
2. Resolve `$releaseBranch`, switch to it, fast-forward it, and merge `dev`:

   ```powershell
   git switch {ReleaseBranch}
   git pull --ff-only origin {ReleaseBranch}
   git merge --no-ff dev -m "Merge dev for {Version} release"
   ```

3. Prepare the primary release on the production branch:

   ```powershell
   node .tools/create_release.js stable {Version} --date {Date}
   ```

   This command gathers every `{Version}-betaN` section plus any final Development notes, orders them newest-first, creates one `[{Version}]` section in both changelogs, removes the consolidated beta headers, updates both TOCs, validates all Lua modules and regression guards, packages the exact tree, writes a SHA-256 file, and generates GitHub and CurseForge post data.

4. Review the consolidated changelogs and artifacts. Confirm that no `{Version}-betaN` header remains and no unrelated version was absorbed:

   ```powershell
   git diff -- CHANGELOG.md ItemRack/Changelog.txt ItemRack/ItemRack.toc ItemRackOptions/ItemRackOptions.toc
   npm.cmd test
   Get-FileHash -Algorithm SHA256 -LiteralPath ".versions\Compressed\ItemRack-anniversary-{Version}.zip"
   Get-Content -LiteralPath ".versions\Compressed\ItemRack-anniversary-{Version}.zip.sha256"
   ```

5. Commit only the reviewed release metadata, create an annotated tag, and push the production branch and tag:

   ```powershell
   git add CHANGELOG.md ItemRack/Changelog.txt ItemRack/ItemRack.toc ItemRackOptions/ItemRackOptions.toc
   git diff --cached --check
   git commit -m "Release version {Version}"
   git tag -a "v{Version}" -m "Release v{Version}"
   git push origin {ReleaseBranch}
   git push origin "refs/tags/v{Version}"
   ```

6. Publish the stable GitHub release from the verified remote tag:

   ```powershell
   gh release create "v{Version}" ".versions\Compressed\ItemRack-anniversary-{Version}.zip" ".versions\Compressed\ItemRack-anniversary-{Version}.zip.sha256" --title "v{Version}" --notes-file ".versions\Release\v{Version}\GITHUB_RELEASE.md" --latest --verify-tag
   ```

7. Install the exact staged stable release locally:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .tools/install_local.ps1 -SourceRoot ".versions\Release\v{Version}" -Confirm:$false
   ```

8. Sync the release history back to `dev`, restore both TOCs to `Dev`, commit, and push:

   ```powershell
   git switch dev
   git merge --no-ff {ReleaseBranch} -m "Merge {Version} release back into dev"
   node .tools/create_release.js reset
   git add ItemRack/ItemRack.toc ItemRackOptions/ItemRackOptions.toc
   git diff --cached --check
   git commit -m "Reset development version back to Dev"
   git push origin dev
   ```

9. Report the production branch, merge and tag commits, GitHub release URL, archive SHA-256, local installations updated, and `.versions\Release\v{Version}\CURSEFORGE_RELEASE.md` for posting.

## Failure handling

- Stop immediately on failed tests, merge conflicts, missing changelog content, version mismatches, tag collisions, hash mismatches, or publication errors.
- Never delete or move an existing tag to make a rerun pass.
- Do not reset `dev` metadata until the release commit and remote tag are confirmed. If GitHub publication fails after the tag push, repair or rerun only the publication step against that same verified tag.
- Never publish a package built from files that differ from the tagged commit.
