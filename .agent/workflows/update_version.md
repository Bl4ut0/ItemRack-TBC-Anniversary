---
description: Update plugin version and changelog
---

1. Ask the user for the New Version Number (e.g. 4.27.4), the Date (e.g. 2026-02-03), and a summary of changes.
2. Edit `ItemRack/ItemRack.toc` and update the `## Version` line.
3. Edit `ItemRackOptions/ItemRackOptions.toc` and update the `## Version` line.
4. Edit `CHANGELOG.md` and insert the new version header and changes at the top.
5. Run the following git commands to commit and tag the release:
// turbo-all
   ```bash
   git add .
   git commit -m "Release version {Version}"
   git tag -a v{Version} -m "Release v{Version}"
   git push origin main
   git push origin v{Version}
   ```
6. If the user has `gh` (GitHub CLI) installed, offer to run:
   ```bash
   gh release create v{Version} --title "v{Version}" --notes-file CHANGELOG.md
   ```
   *Note: You may need to extract just the latest section of the changelog for the notes.*
7. Confirm completion to the user.
