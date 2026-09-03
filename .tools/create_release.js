const fs = require('fs');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const repoRoot = path.resolve(__dirname, '..');
process.chdir(repoRoot);

const paths = {
  mainToc: 'ItemRack/ItemRack.toc',
  optionsToc: 'ItemRackOptions/ItemRackOptions.toc',
  markdownChangelog: 'CHANGELOG.md',
  addonChangelog: 'ItemRack/Changelog.txt',
  buildScript: '.tools/build_release_dev.ps1',
  structureScript: '.tools/check_addon_structure.js'
};

const releaseMetadataPaths = new Set([
  paths.mainToc,
  paths.optionsToc,
  paths.markdownChangelog,
  paths.addonChangelog
]);

const versionPattern = /^\d+\.\d+(?:\.\d+)?(?:-beta\d+)?$/;
const stableVersionPattern = /^\d+\.\d+(?:\.\d+)?$/;
const betaVersionPattern = /^\d+\.\d+(?:\.\d+)?-beta\d+$/;

function fail(message) {
  console.error(`[RELEASE] ${message}`);
  process.exit(1);
}

function run(command, args) {
  console.log(`> ${command} ${args.join(' ')}`);
  const result = spawnSync(command, args, { cwd: repoRoot, stdio: 'inherit' });
  if (result.error) {
    fail(result.error.message);
  }
  if (result.status !== 0) {
    fail(`${command} exited with status ${result.status}.`);
  }
}

function git(args) {
  return execFileSync('git', args, { cwd: repoRoot, encoding: 'utf8' }).trim();
}

function trackedChanges() {
  const status = git(['status', '--porcelain', '--untracked-files=no']);
  if (!status) return [];
  return status.split(/\r?\n/).map((line) => {
    const statusPath = line.slice(3);
    const renameIndex = statusPath.lastIndexOf(' -> ');
    return (renameIndex >= 0 ? statusPath.slice(renameIndex + 4) : statusPath).replace(/\\/g, '/');
  });
}

function ensureNoUntrackedAddonFiles() {
  const untrackedAddonFiles = git([
    'ls-files', '--others', '--exclude-standard', '--', 'ItemRack', 'ItemRackOptions'
  ]);
  if (untrackedAddonFiles) {
    fail('Remove or commit untracked addon files before continuing a release.');
  }
}

function ensureCleanReleaseSource() {
  ensureNoUntrackedAddonFiles();
  if (trackedChanges().length > 0) {
    fail('Commit or stash tracked changes before continuing a release.');
  }
}

function ensureRetryablePreparationSource() {
  ensureNoUntrackedAddonFiles();
  const disallowed = trackedChanges().filter((filePath) => !releaseMetadataPaths.has(filePath));
  if (disallowed.length > 0) {
    fail(`Preparation only permits existing release-metadata changes; also dirty: ${disallowed.join(', ')}`);
  }
}

function ensureTagDoesNotExist(version) {
  if (git(['tag', '--list', `v${version}`])) {
    fail(`Tag v${version} already exists locally. Refusing to rebuild an existing release.`);
  }
}

function read(filePath) {
  return fs.readFileSync(filePath, 'utf8');
}

function write(filePath, content) {
  fs.writeFileSync(filePath, content, 'utf8');
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function parseMarkdownSections(text) {
  const regex = /^## \[([^\]]+)\](?: - ([^\r\n]+))?\r?\n/gm;
  const matches = Array.from(text.matchAll(regex));
  return matches.map((match, index) => ({
    version: match[1],
    date: match[2],
    start: match.index,
    headerEnd: match.index + match[0].length,
    end: index + 1 < matches.length ? matches[index + 1].index : text.length,
    body: text.slice(
      match.index + match[0].length,
      index + 1 < matches.length ? matches[index + 1].index : text.length
    ).trim()
  }));
}

function parseAddonSections(text) {
  const regex = /^__ New in (.+?) - By .*? __\r?\n/gm;
  const matches = Array.from(text.matchAll(regex));
  return matches.map((match, index) => ({
    version: match[1],
    start: match.index,
    headerEnd: match.index + match[0].length,
    end: index + 1 < matches.length ? matches[index + 1].index : text.length,
    body: text.slice(
      match.index + match[0].length,
      index + 1 < matches.length ? matches[index + 1].index : text.length
    ).trim()
  }));
}

function markdownDevelopment(text) {
  const sections = parseMarkdownSections(text);
  const section = sections.find((entry) => entry.version === 'Development');
  if (!section) fail('CHANGELOG.md has no [Development] section.');
  return section;
}

function addonDevelopment(text) {
  const match = /^__ Development __\r?\n/m.exec(text);
  if (!match) fail('ItemRack/Changelog.txt has no Development section.');
  const headerEnd = match.index + match[0].length;
  const remainder = text.slice(headerEnd);
  const nextSection = /^__ New in /m.exec(remainder);
  const end = nextSection ? headerEnd + nextSection.index : text.length;
  return {
    start: match.index,
    headerEnd,
    end,
    body: text.slice(headerEnd, end).trim()
  };
}

function replaceMarkdownDevelopment(text, sectionText) {
  const development = markdownDevelopment(text);
  const prefix = text.slice(0, development.headerEnd);
  const suffix = text.slice(development.end).replace(/^\s*/, '');
  return `${prefix}\n${sectionText ? `\n${sectionText.trim()}\n\n` : '\n'}${suffix}`;
}

function replaceAddonDevelopment(text, sectionText) {
  const development = addonDevelopment(text);
  const prefix = text.slice(0, development.headerEnd);
  const suffix = text.slice(development.end).replace(/^\s*/, '');
  return `${prefix}${sectionText ? `\n${sectionText.trim()}\n\n` : '\n'}${suffix}`;
}

function removeRanges(text, ranges) {
  let result = text;
  for (const range of [...ranges].sort((a, b) => b.start - a.start)) {
    result = result.slice(0, range.start) + result.slice(range.end);
  }
  return result;
}

function normalizeMarkdownBody(body) {
  return body
    .replace(/^### Bug Fixes & Improvements\s*/m, '')
    .trim();
}

function promoteBetaMarkdown(text, version, date) {
  const sections = parseMarkdownSections(text);
  const existing = sections.find((entry) => entry.version === version);
  const development = markdownDevelopment(text);
  if (existing) {
    if (existing.date !== date) {
      fail(`CHANGELOG.md already dates ${version} as ${existing.date || '(undated)'}, not ${date}.`);
    }
    if (development.body) {
      fail(`CHANGELOG.md already contains ${version}, but Development is not empty.`);
    }
    return { text, body: existing.body };
  }
  if (!development.body) {
    fail('No Markdown development changes are available for the beta release.');
  }
  const section = `## [${version}] - ${date}\n${development.body}`;
  const updated = replaceMarkdownDevelopment(text, section);
  return { text: updated, body: parseMarkdownSections(updated).find((entry) => entry.version === version).body };
}

function promoteBetaAddon(text, version) {
  const existing = parseAddonSections(text).find((entry) => entry.version === version);
  const development = addonDevelopment(text);
  if (existing) {
    if (development.body) {
      fail(`ItemRack/Changelog.txt already contains ${version}, but Development is not empty.`);
    }
    return text;
  }
  if (!development.body) {
    fail('No in-addon development changes are available for the beta release.');
  }
  return replaceAddonDevelopment(
    text,
    `__ New in ${version} - By Bl4ut0 __\n${development.body}`
  );
}

function consolidateStableMarkdown(text, version, date) {
  const sections = parseMarkdownSections(text);
  const existing = sections.find((entry) => entry.version === version);
  const betaRegex = new RegExp(`^${escapeRegExp(version)}-beta(\\d+)$`);
  const betaSections = sections
    .filter((entry) => betaRegex.test(entry.version))
    .sort((a, b) => Number(b.version.match(betaRegex)[1]) - Number(a.version.match(betaRegex)[1]));
  const development = markdownDevelopment(text);

  if (existing) {
    if (betaSections.length > 0) {
      fail(`Stable section ${version} exists alongside unconsolidated beta notes.`);
    }
    if (!development.body) {
      if (existing.date !== date) {
        fail(`CHANGELOG.md already dates ${version} as ${existing.date || '(undated)'}, not ${date}.`);
      }
      return { text, body: existing.body };
    }

    const combined = [
      normalizeMarkdownBody(development.body),
      normalizeMarkdownBody(existing.body)
    ].filter(Boolean).join('\n');
    const withoutExisting = removeRanges(text, [existing]);
    const updated = replaceMarkdownDevelopment(
      withoutExisting,
      `## [${version}] - ${date}\n### Bug Fixes & Improvements\n${combined}`
    );
    return { text: updated, body: parseMarkdownSections(updated).find((entry) => entry.version === version).body };
  }
  if (betaSections.length === 0 && !development.body) {
    fail(`No ${version}-beta* or Development notes were found to consolidate.`);
  }

  const bodies = [];
  if (development.body) bodies.push(normalizeMarkdownBody(development.body));
  for (const section of betaSections) {
    bodies.push(normalizeMarkdownBody(section.body));
  }
  const combined = bodies.filter(Boolean).join('\n');
  let updated = removeRanges(text, betaSections);
  updated = replaceMarkdownDevelopment(
    updated,
    `## [${version}] - ${date}\n### Bug Fixes & Improvements\n${combined}`
  );
  return { text: updated, body: parseMarkdownSections(updated).find((entry) => entry.version === version).body };
}

function consolidateStableAddon(text, version) {
  const sections = parseAddonSections(text);
  const existing = sections.find((entry) => entry.version === version);
  const betaRegex = new RegExp(`^${escapeRegExp(version)}-beta(\\d+)$`);
  const betaSections = sections
    .filter((entry) => betaRegex.test(entry.version))
    .sort((a, b) => Number(b.version.match(betaRegex)[1]) - Number(a.version.match(betaRegex)[1]));
  const development = addonDevelopment(text);

  if (existing) {
    if (betaSections.length > 0) {
      fail(`In-addon stable section ${version} exists alongside unconsolidated beta notes.`);
    }
    if (!development.body) {
      return text;
    }

    const withoutExisting = removeRanges(text, [existing]);
    return replaceAddonDevelopment(
      withoutExisting,
      `__ New in ${version} - By Bl4ut0 __\n${[development.body, existing.body].filter(Boolean).join('\n')}`
    );
  }
  if (betaSections.length === 0 && !development.body) {
    fail(`No in-addon ${version}-beta* or Development notes were found.`);
  }

  const bodies = [];
  if (development.body) bodies.push(development.body);
  for (const section of betaSections) bodies.push(section.body);
  let updated = removeRanges(text, betaSections);
  updated = replaceAddonDevelopment(
    updated,
    `__ New in ${version} - By Bl4ut0 __\n${bodies.filter(Boolean).join('\n')}`
  );
  return updated;
}

function readTocVersionFromText(text, label) {
  const matches = Array.from(text.matchAll(/^## Version:[ \t]*(\S+)[ \t]*$/gm));
  if (matches.length !== 1) {
    fail(`${label} must contain exactly one Version metadata field.`);
  }
  return matches[0][1];
}

function tocWithVersion(text, version, label) {
  readTocVersionFromText(text, label);
  return text.replace(/^## Version:[ \t]*\S+[ \t]*$/m, `## Version: ${version}`);
}

function validateMetadataContent(version, markdown, addon, mainToc, optionsToc) {
  for (const [label, text] of [
    [paths.mainToc, mainToc],
    [paths.optionsToc, optionsToc]
  ]) {
    if (readTocVersionFromText(text, label) !== version) {
      fail(`${label} does not identify version ${version}.`);
    }
  }
  if (!parseMarkdownSections(markdown).some((entry) => entry.version === version)) {
    fail(`CHANGELOG.md does not contain release ${version}.`);
  }
  if (!parseAddonSections(addon).some((entry) => entry.version === version)) {
    fail(`ItemRack/Changelog.txt does not contain release ${version}.`);
  }
}

function writeMetadataTransaction(files) {
  const token = `${process.pid}-${Date.now()}`;
  const entries = Object.entries(files).map(([filePath, content]) => ({
    filePath,
    content,
    temporaryPath: `${filePath}.release-${token}.tmp`,
    backupPath: `${filePath}.release-${token}.bak`,
    replaced: false
  }));

  try {
    for (const entry of entries) write(entry.temporaryPath, entry.content);
    for (const entry of entries) {
      fs.renameSync(entry.filePath, entry.backupPath);
      fs.renameSync(entry.temporaryPath, entry.filePath);
      entry.replaced = true;
    }
  } catch (error) {
    for (const entry of entries.slice().reverse()) {
      if (entry.replaced && fs.existsSync(entry.filePath)) fs.unlinkSync(entry.filePath);
      if (fs.existsSync(entry.backupPath)) fs.renameSync(entry.backupPath, entry.filePath);
      if (fs.existsSync(entry.temporaryPath)) fs.unlinkSync(entry.temporaryPath);
    }
    fail(`Release metadata was not changed: ${error.message}`);
  }

  for (const entry of entries) {
    try {
      fs.unlinkSync(entry.backupPath);
    } catch (error) {
      console.warn(`[RELEASE] Metadata is committed, but backup cleanup is needed: ${entry.backupPath}`);
    }
  }
}

function localDate() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function requestedDate(args) {
  const index = args.indexOf('--date');
  const value = index >= 0 ? args[index + 1] : localDate();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value || '')) {
    fail('Release date must use YYYY-MM-DD.');
  }
  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    fail('Release date must be a real calendar date in YYYY-MM-DD form.');
  }
  return value;
}

function generatePostData(mode, version, body, outputRoot = '.versions') {
  const isBeta = mode === 'beta';
  const releaseDir = path.join(outputRoot, 'Release', `v${version}`);
  fs.mkdirSync(releaseDir, { recursive: true });
  const channelText = isBeta
    ? '> Beta test build: please report Lua errors, incorrect swaps, or regressions with `/itemrack dump` output.'
    : 'This stable release consolidates the tested beta changes for this version.';
  const normalizedBody = body.trim();
  const github = `# ItemRack Anniversary v${version}\n\n${channelText}\n\n## Changes\n\n${normalizedBody}\n`;
  const curseForge = `# ItemRack Anniversary v${version}\n\n${isBeta ? '**Beta test release**' : '**Stable release**'}\n\n${normalizedBody}\n\nPlease include the output of \`/itemrack dump\` with any bug report.\n`;
  write(path.join(releaseDir, 'GITHUB_RELEASE.md'), github);
  write(path.join(releaseDir, 'CURSEFORGE_RELEASE.md'), curseForge);
}

function releasePostBody(mode, version, markdown, currentBody) {
  if (mode !== 'beta') return currentBody;
  const versionMatch = /^(.*)-beta(\d+)$/.exec(version);
  if (!versionMatch) return currentBody;
  const baseVersion = versionMatch[1];
  const currentNumber = Number(versionMatch[2]);
  const betaPattern = new RegExp(`^${escapeRegExp(baseVersion)}-beta(\\d+)$`);
  const sections = parseMarkdownSections(markdown)
    .map((entry) => ({ entry, match: betaPattern.exec(entry.version) }))
    .filter(({ match }) => match && Number(match[1]) <= currentNumber)
    .sort((left, right) => Number(right.match[1]) - Number(left.match[1]));
  if (sections.length <= 1) return currentBody;
  return sections.map(({ entry }) =>
    `### ${entry.version}\n\n${normalizeMarkdownBody(entry.body)}`
  ).join('\n\n');
}

function validateModeAndVersion(mode, version) {
  if (!versionPattern.test(version || '')) fail('Specify a valid release version.');
  if (mode === 'beta' && !betaVersionPattern.test(version)) {
    fail('Beta versions must end in -betaN (for example, 4.44-beta1).');
  }
  if (mode === 'stable' && !stableVersionPattern.test(version)) {
    fail('Stable versions cannot contain a beta suffix.');
  }
  if (mode !== 'beta' && mode !== 'stable') {
    fail('Release mode must be beta or stable.');
  }
}

function resolveCommit(ref) {
  if (!ref) fail('A committed source ref is required.');
  try {
    return git(['rev-parse', '--verify', `${ref}^{commit}`]);
  } catch (error) {
    fail(`Could not resolve committed source ref ${ref}.`);
  }
}

function readAtRef(commit, filePath) {
  try {
    return execFileSync('git', ['show', `${commit}:${filePath}`], {
      cwd: repoRoot,
      encoding: 'utf8',
      maxBuffer: 16 * 1024 * 1024
    });
  } catch (error) {
    fail(`Could not read ${filePath} from commit ${commit}.`);
  }
}

function optionValue(args, name) {
  const index = args.indexOf(name);
  if (index < 0 || !args[index + 1] || args[index + 1].startsWith('--')) {
    fail(`${name} requires a value.`);
  }
  return args[index + 1];
}

function optionalOptionValue(args, name, fallback) {
  const index = args.indexOf(name);
  if (index < 0) return fallback;
  if (!args[index + 1] || args[index + 1].startsWith('--')) {
    fail(`${name} requires a value.`);
  }
  return args[index + 1];
}

function runValidationSuite(options = {}) {
  run(process.execPath, [
    '.tools/check_lua.js',
    'ItemRack/ItemRack.lua',
    'ItemRack/ItemRackButtons.lua',
    'ItemRack/ItemRackEquip.lua',
    'ItemRack/ItemRackEvents.lua',
    'ItemRack/ItemRackQueue.lua',
    'ItemRackOptions/ItemRackOptions.lua'
  ]);
  run(process.execPath, [
    paths.structureScript,
    ...(options.allowVersionMismatch ? ['--allow-version-mismatch'] : [])
  ]);
  for (const validator of [
    '.tools/check_regressions.js',
    '.tools/check_events_runtime.js',
    '.tools/check_identity_regressions.js',
    '.tools/check_queue_watchdog_regressions.js',
    '.tools/check_release_flow.js'
  ]) {
    run(process.execPath, [validator]);
  }
}

function buildRelease(mode, version, args) {
  validateModeAndVersion(mode, version);
  const requestedRef = optionValue(args, '--ref');
  const outputRoot = path.resolve(repoRoot, optionalOptionValue(args, '--output-root', '.versions'));
  const commit = resolveCommit(requestedRef);
  const markdown = readAtRef(commit, paths.markdownChangelog);
  const addon = readAtRef(commit, paths.addonChangelog);
  const mainToc = readAtRef(commit, paths.mainToc);
  const optionsToc = readAtRef(commit, paths.optionsToc);
  validateMetadataContent(version, markdown, addon, mainToc, optionsToc);

  const releaseSection = parseMarkdownSections(markdown).find((entry) => entry.version === version);
  const powerShell = process.platform === 'win32' ? 'powershell.exe' : 'pwsh';
  run(powerShell, [
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', paths.buildScript,
    '-Version', version, '-Ref', commit, '-OutputRoot', outputRoot
  ]);

  const releaseDir = path.join(outputRoot, 'Release', `v${version}`);
  run(process.execPath, [
    '.tools/check_lua.js',
    path.join(releaseDir, 'ItemRack/ItemRack.lua'),
    path.join(releaseDir, 'ItemRack/ItemRackButtons.lua'),
    path.join(releaseDir, 'ItemRack/ItemRackEquip.lua'),
    path.join(releaseDir, 'ItemRack/ItemRackEvents.lua'),
    path.join(releaseDir, 'ItemRack/ItemRackQueue.lua'),
    path.join(releaseDir, 'ItemRackOptions/ItemRackOptions.lua')
  ]);
  run(process.execPath, [paths.structureScript, releaseDir]);
  generatePostData(
    mode,
    version,
    releasePostBody(mode, version, markdown, releaseSection.body),
    outputRoot
  );

  const zipPath = path.join(outputRoot, 'Compressed', `ItemRack-anniversary-${version}.zip`);
  const hashPath = `${zipPath}.sha256`;
  for (const artifact of [
    zipPath,
    hashPath,
    path.join(releaseDir, 'SOURCE_COMMIT.txt'),
    path.join(releaseDir, 'SOURCE_TREE.txt'),
    path.join(releaseDir, 'SOURCE_FILES.sha256'),
    path.join(releaseDir, 'GITHUB_RELEASE.md'),
    path.join(releaseDir, 'CURSEFORGE_RELEASE.md')
  ]) {
    if (!fs.existsSync(artifact)) fail(`Expected release artifact was not created: ${artifact}`);
  }
  console.log(`[RELEASE] Built ${mode} release v${version} from ${commit}.`);
  console.log(`[RELEASE] Requested ref: ${requestedRef}`);
  console.log(`[RELEASE] Archive: ${zipPath}`);
  console.log(`[RELEASE] GitHub notes: ${releaseDir}/GITHUB_RELEASE.md`);
  console.log(`[RELEASE] CurseForge post: ${releaseDir}/CURSEFORGE_RELEASE.md`);
}

function prepare(mode, version, args) {
  validateModeAndVersion(mode, version);

  ensureRetryablePreparationSource();
  ensureTagDoesNotExist(version);
  const branch = git(['branch', '--show-current']);
  if (mode === 'beta' && branch !== 'dev') {
    fail(`Beta releases must be prepared on dev; current branch is ${branch || '(detached)'}.`);
  }
  if (mode === 'stable' && branch !== 'main' && branch !== 'master') {
    fail(`Stable releases must be prepared on main or master after merging dev; current branch is ${branch || '(detached)'}.`);
  }

  const date = requestedDate(args);
  const markdown = read(paths.markdownChangelog);
  const addon = read(paths.addonChangelog);
  const markdownResult = mode === 'beta'
    ? promoteBetaMarkdown(markdown, version, date)
    : consolidateStableMarkdown(markdown, version, date);
  const updatedAddon = mode === 'beta'
    ? promoteBetaAddon(addon, version)
    : consolidateStableAddon(addon, version);
  const updatedMainToc = tocWithVersion(read(paths.mainToc), version, paths.mainToc);
  const updatedOptionsToc = tocWithVersion(read(paths.optionsToc), version, paths.optionsToc);

  validateMetadataContent(
    version,
    markdownResult.text,
    updatedAddon,
    updatedMainToc,
    updatedOptionsToc
  );
  runValidationSuite({ allowVersionMismatch: true });

  const files = {
    [paths.markdownChangelog]: markdownResult.text,
    [paths.addonChangelog]: updatedAddon,
    [paths.mainToc]: updatedMainToc,
    [paths.optionsToc]: updatedOptionsToc
  };
  if (Object.entries(files).some(([filePath, content]) => read(filePath) !== content)) {
    writeMetadataTransaction(files);
    console.log(`[RELEASE] Prepared ${mode} metadata for v${version}. Review and commit it before building.`);
  } else {
    console.log(`[RELEASE] ${mode} metadata for v${version} is already prepared and verified.`);
  }
}

function resetDevelopmentMetadata() {
  ensureCleanReleaseSource();
  const branch = git(['branch', '--show-current']);
  if (branch !== 'dev') {
    fail(`Development metadata can only be reset on dev; current branch is ${branch || '(detached)'}.`);
  }
  const mainToc = tocWithVersion(read(paths.mainToc), 'Dev', paths.mainToc);
  const optionsToc = tocWithVersion(read(paths.optionsToc), 'Dev', paths.optionsToc);
  if (readTocVersionFromText(mainToc, paths.mainToc) !== 'Dev' ||
      readTocVersionFromText(optionsToc, paths.optionsToc) !== 'Dev') {
    fail('Could not construct Dev TOC metadata.');
  }
  writeMetadataTransaction({ [paths.mainToc]: mainToc, [paths.optionsToc]: optionsToc });
  console.log('[RELEASE] Restored both TOC files to Dev. Changelog history was preserved.');
}

module.exports = {
  parseMarkdownSections,
  parseAddonSections,
  promoteBetaMarkdown,
  promoteBetaAddon,
  consolidateStableMarkdown,
  consolidateStableAddon,
  releasePostBody,
  runValidationSuite
};

if (require.main === module) {
  const args = process.argv.slice(2);
  const command = args[0];
  if (command === 'prepare') {
    prepare(args[1], args[2], args.slice(3));
  } else if (command === 'build') {
    buildRelease(args[1], args[2], args.slice(3));
  } else if (command === 'beta' || command === 'stable') {
    console.warn(`[RELEASE] '${command}' is a compatibility alias for 'prepare ${command}'; it no longer builds a mutable checkout.`);
    prepare(command, args[1], args.slice(2));
  } else if (command === 'reset') {
    resetDevelopmentMetadata();
  } else {
    console.error('Usage:');
    console.error('  node .tools/create_release.js prepare beta <version-betaN> [--date YYYY-MM-DD]');
    console.error('  node .tools/create_release.js prepare stable <version> [--date YYYY-MM-DD]');
    console.error('  node .tools/create_release.js build <beta|stable> <version> --ref <commit-or-tag> [--output-root <path>]');
    console.error('  node .tools/create_release.js reset');
    process.exit(1);
  }
}
