# Local Build and Installation Workflow

Use this workflow to validate and install the current `dev` source without creating a release.

1. Confirm the checkout is on `dev` and inspect `git status --short`.
2. Run the complete validation suite:

   ```powershell
   npm.cmd test
   ```

3. Ask before replacing any installed addon folders. After approval, install the source tree:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .tools/install_local.ps1 -SourceRoot . -Confirm:$false
   ```

4. Verify both installed addon folders contain their TOC and Lua files. Do not commit local game files or generated `.versions` artifacts.

For release testing, use `.agent/workflows/release.md`; it installs the immutable staged release rather than the mutable source checkout.
