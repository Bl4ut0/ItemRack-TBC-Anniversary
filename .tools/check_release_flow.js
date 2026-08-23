const assert = require('assert');
const fs = require('fs');
const releaseTools = require('./create_release');

const read = (filePath) => fs.readFileSync(filePath, 'utf8');
const createRelease = read('.tools/create_release.js');
const buildScript = read('.tools/build_release_dev.ps1');
const installScript = read('.tools/install_local.ps1');
const workflow = read('.agent/workflows/release.md');
const packageJson = JSON.parse(read('package.json'));

let checks = 0;
function check(condition, message) {
  assert.ok(condition, message);
  checks += 1;
}

function between(source, start, end) {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex + start.length);
  assert.notStrictEqual(startIndex, -1, `Missing start marker: ${start}`);
  assert.notStrictEqual(endIndex, -1, `Missing end marker: ${end}`);
  return source.slice(startIndex, endIndex);
}

check(
  createRelease.includes("command === 'prepare'") && createRelease.includes("command === 'build'"),
  'Release tooling must separate metadata preparation from exact-ref building.'
);
const prepareFunction = between(createRelease, 'function prepare(', 'function resetDevelopmentMetadata');
const preparationValidationIndex = prepareFunction.indexOf(
  'runValidationSuite({ allowVersionMismatch: true });'
);
const metadataWriteIndex = prepareFunction.indexOf('writeMetadataTransaction(files);');
check(
  preparationValidationIndex >= 0 &&
    metadataWriteIndex >= 0 &&
    preparationValidationIndex < metadataWriteIndex,
  'Preparation validation must finish before release metadata is replaced.'
);
check(
  createRelease.includes("'-Version', version, '-Ref', commit"),
  'The Node release driver must pass a resolved commit to the packager.'
);

check(
  buildScript.includes("'-c', 'core.autocrlf=false'") &&
    buildScript.includes("'archive', '--format=zip'") &&
    buildScript.includes("'ls-tree', '-r'") &&
    buildScript.includes("'hash-object', '--no-filters'") &&
    buildScript.includes('SOURCE_COMMIT.txt') &&
    buildScript.includes('SOURCE_TREE.txt') &&
    buildScript.includes('SOURCE_FILES.sha256'),
  'The packager must archive and verify an immutable commit tree with provenance manifests.'
);
check(
  !buildScript.includes('Copy-Item -LiteralPath $itemRackSource'),
  'The packager must not copy addon files from the mutable checkout.'
);

check(
  installScript.includes('if ($destinations.Count -eq 0)') &&
    installScript.includes('No supported local WoW AddOns folders were found.'),
  'Local installation must fail when no supported client folder exists.'
);
check(
  installScript.includes('$completedDestinations += $addOnsPath') &&
    installScript.includes('foreach ($destinationPath in $reportedDestinations)') &&
    installScript.includes('Assert-ReleaseSourceManifest -Root $sourceRootFull') &&
    installScript.includes('Assert-DirectoryMirror -Source $entry.Source -Target $target'),
  'Local installation must verify and report every deterministic destination it handled.'
);

const betaTrack = between(workflow, '## Track A: Beta', '## Track B: Primary');
check(
  !betaTrack.includes('git switch {ReleaseBranch}') && !betaTrack.includes('git push origin {ReleaseBranch}'),
  'The beta track must never touch the production branch.'
);
check(
  betaTrack.includes('build beta {Version} --ref "v{Version}"') && betaTrack.includes('--prerelease'),
  'The beta track must build its exact tag and publish a GitHub prerelease.'
);

const candidatePhase = between(workflow, '### Phase 1: Create and test a candidate', '### Candidate correction loop');
check(
  candidatePhase.includes('git push origin {ReleaseBranch}') &&
    candidatePhase.includes('build stable {Version} --ref {CandidateCommit}') &&
    candidatePhase.includes('install_local.ps1'),
  'A primary candidate must be pushed, built from its recorded commit, and installed locally.'
);
check(
  !candidatePhase.includes('git tag -a') && !candidatePhase.includes('gh release create'),
  'A primary candidate must not create a tag or public GitHub release.'
);

const correctionPhase = between(
  workflow,
  '### Candidate correction loop',
  '### Phase 2: Finalize an accepted candidate'
);
check(
  correctionPhase.includes('$currentCandidate -ne "{CandidateCommit}"') &&
    correctionPhase.includes('git merge --no-ff {CandidateCommit}') &&
    correctionPhase.indexOf('git merge --no-ff {CandidateCommit}') <
      correctionPhase.indexOf('node .tools/create_release.js reset') &&
    correctionPhase.indexOf('node .tools/create_release.js reset') <
      correctionPhase.indexOf('add only a fresh Development'),
  'A rejected candidate must synchronize its exact stable metadata into dev and reset only the TOCs before new correction notes are added.'
);

const finalizePhase = between(workflow, '### Phase 2: Finalize an accepted candidate', '## Failure handling');
check(
  finalizePhase.indexOf('git tag -a') < finalizePhase.indexOf('gh release create') &&
    finalizePhase.indexOf('gh release create') < finalizePhase.indexOf('git switch dev'),
  'Primary finalization must tag and publish before merging back and resetting dev.'
);
check(
  finalizePhase.includes('$testedHash = "{TestedSHA256}".ToLowerInvariant()') &&
    finalizePhase.includes('$finalHash -ne $testedHash'),
  'Finalization must compare the tagged archive with the locally accepted candidate hash.'
);
check(
  !workflow.includes('powershell.exe -NoProfile -ExecutionPolicy Bypass -File .tools/install_local.ps1') &&
    workflow.includes('& .\\.tools\\install_local.ps1'),
  'Workflow examples must preserve the Confirm switch value on Windows PowerShell 5.1.'
);

const originalDevMarkdown = `# Changelog

## [Development]

- Original development note

## [4.43-beta2] - 2026-08-20
### Bug Fixes & Improvements
- Beta two

## [4.43-beta1] - 2026-08-19
### Bug Fixes & Improvements
- Beta one

## [4.42] - 2026-07-25
- Previous stable
`;
const firstCandidateMarkdown = releaseTools.consolidateStableMarkdown(
  originalDevMarkdown,
  '4.43',
  '2026-08-21'
).text;
const synchronizedDevMarkdown = firstCandidateMarkdown.replace(
  '## [Development]\n',
  '## [Development]\n\n- Candidate correction\n'
);
const correctedMarkdown = releaseTools.consolidateStableMarkdown(
  synchronizedDevMarkdown,
  '4.43',
  '2026-08-22'
).text;
check(
    (correctedMarkdown.match(/## \[4\.43\]/g) || []).length === 1 &&
    !correctedMarkdown.includes('4.43-beta') &&
    correctedMarkdown.includes('## [4.43] - 2026-08-22') &&
    correctedMarkdown.indexOf('- Candidate correction') < correctedMarkdown.indexOf('- Original development note') &&
    (correctedMarkdown.match(/- Original development note/g) || []).length === 1 &&
    (correctedMarkdown.match(/- Beta two/g) || []).length === 1 &&
    (correctedMarkdown.match(/- Beta one/g) || []).length === 1 &&
    (correctedMarkdown.match(/- Candidate correction/g) || []).length === 1 &&
    releaseTools.parseMarkdownSections(correctedMarkdown).find((section) => section.version === 'Development').body === '',
  'A corrected primary candidate must fold only fresh Development notes into the synchronized stable section without restoring or duplicating consumed notes.'
);

const originalDevAddon = `__ Development __

- Original development note

__ New in 4.43-beta2 - By Bl4ut0 __
- Beta two

__ New in 4.43-beta1 - By Bl4ut0 __
- Beta one

__ New in 4.42 - By Bl4ut0 __
- Previous stable
`;
const firstCandidateAddon = releaseTools.consolidateStableAddon(originalDevAddon, '4.43');
const synchronizedDevAddon = firstCandidateAddon.replace(
  '__ Development __\n',
  '__ Development __\n\n- Candidate correction\n'
);
const correctedAddon = releaseTools.consolidateStableAddon(synchronizedDevAddon, '4.43');
check(
  (correctedAddon.match(/__ New in 4\.43 /g) || []).length === 1 &&
    !correctedAddon.includes('4.43-beta') &&
    (correctedAddon.match(/- Original development note/g) || []).length === 1 &&
    (correctedAddon.match(/- Beta two/g) || []).length === 1 &&
    (correctedAddon.match(/- Beta one/g) || []).length === 1 &&
    (correctedAddon.match(/- Candidate correction/g) || []).length === 1,
  'The synchronized in-addon changelog must support a corrected candidate without duplicated notes or stable headers.'
);

check(
  packageJson.scripts['validate:structure'] && packageJson.scripts['test:release'],
  'The default test stack must expose structure and release-flow checks.'
);

console.log(`[RELEASE FLOW] ${checks} candidate, packaging, installation, and finalization guards passed.`);
