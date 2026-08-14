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
  buildScript: '.tools/build_release_dev.ps1'
};

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

function ensureCleanReleaseSource() {
  const trackedStatus = git(['status', '--porcelain', '--untracked-files=no']);
  const untrackedAddonFiles = git([
    'ls-files', '--others', '--exclude-standard', '--', 'ItemRack', 'ItemRackOptions'
  ]);
  if (trackedStatus || untrackedAddonFiles) {
    fail('Commit or stash tracked changes and untracked addon files before preparing a release.');
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
    if (betaSections.length > 0 || development.body) {
      fail(`Stable section ${version} exists alongside unconsolidated beta or Development notes.`);
    }
    return { text, body: existing.body };
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
    if (betaSections.length > 0 || development.body) {
      fail(`In-addon stable section ${version} exists alongside unconsolidated notes.`);
    }
    return text;
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

function readTocVersion(filePath) {
  const match = /^## Version:[ \t]*(\S+)[ \t]*$/m.exec(read(filePath));
  if (!match) fail(`${filePath} has no Version metadata.`);
  return match[1];
}

function setTocVersion(filePath, version) {
  const source = read(filePath);
  const updated = source.replace(/^## Version:[ \t]*\S+[ \t]*$/m, `## Version: ${version}`);
  if (updated === source && readTocVersion(filePath) !== version) {
    fail(`Could not update ${filePath}.`);
  }
  write(filePath, updated);
}

function validateMetadata(version) {
  for (const tocPath of [paths.mainToc, paths.optionsToc]) {
    if (readTocVersion(tocPath) !== version) {
      fail(`${tocPath} does not identify version ${version}.`);
    }
  }
  if (!parseMarkdownSections(read(paths.markdownChangelog)).some((entry) => entry.version === version)) {
    fail(`CHANGELOG.md does not contain release ${version}.`);
  }
  if (!parseAddonSections(read(paths.addonChangelog)).some((entry) => entry.version === version)) {
    fail(`ItemRack/Changelog.txt does not contain release ${version}.`);
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
  return value;
}

function generatePostData(mode, version, body) {
  const isBeta = mode === 'beta';
  const releaseDir = path.join('.versions', 'Release', `v${version}`);
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

function buildRelease(mode, version, body) {
  const powerShell = process.platform === 'win32' ? 'powershell.exe' : 'pwsh';
  run(process.execPath, [
    '.tools/check_lua.js',
    'ItemRack/ItemRack.lua',
    'ItemRack/ItemRackButtons.lua',
    'ItemRack/ItemRackEquip.lua',
    'ItemRack/ItemRackEvents.lua',
    'ItemRack/ItemRackQueue.lua',
    'ItemRackOptions/ItemRackOptions.lua'
  ]);
  run(process.execPath, ['.tools/check_regressions.js']);
  run(powerShell, [
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', paths.buildScript, '-Version', version
  ]);
  generatePostData(mode, version, body);

  const zipPath = path.join('.versions', 'Compressed', `ItemRack-anniversary-${version}.zip`);
  const hashPath = `${zipPath}.sha256`;
  for (const artifact of [zipPath, hashPath]) {
    if (!fs.existsSync(artifact)) fail(`Expected release artifact was not created: ${artifact}`);
  }
  console.log(`[RELEASE] Prepared ${mode} release v${version}.`);
  console.log(`[RELEASE] Archive: ${zipPath}`);
  console.log(`[RELEASE] GitHub notes: .versions/Release/v${version}/GITHUB_RELEASE.md`);
  console.log(`[RELEASE] CurseForge post: .versions/Release/v${version}/CURSEFORGE_RELEASE.md`);
}

function prepare(mode, version, args) {
  if (!versionPattern.test(version || '')) fail('Specify a valid release version.');
  if (mode === 'beta' && !betaVersionPattern.test(version)) {
    fail('Beta versions must end in -betaN (for example, 4.44-beta1).');
  }
  if (mode === 'stable' && !stableVersionPattern.test(version)) {
    fail('Stable versions cannot contain a beta suffix.');
  }

  ensureCleanReleaseSource();
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

  write(paths.markdownChangelog, markdownResult.text);
  write(paths.addonChangelog, updatedAddon);
  setTocVersion(paths.mainToc, version);
  setTocVersion(paths.optionsToc, version);
  validateMetadata(version);
  buildRelease(mode, version, markdownResult.body);
}

function resetDevelopmentMetadata() {
  ensureCleanReleaseSource();
  const branch = git(['branch', '--show-current']);
  if (branch !== 'dev') {
    fail(`Development metadata can only be reset on dev; current branch is ${branch || '(detached)'}.`);
  }
  setTocVersion(paths.mainToc, 'Dev');
  setTocVersion(paths.optionsToc, 'Dev');
  if (readTocVersion(paths.mainToc) !== 'Dev' || readTocVersion(paths.optionsToc) !== 'Dev') {
    fail('Failed to restore Dev TOC metadata.');
  }
  console.log('[RELEASE] Restored both TOC files to Dev. Changelog history was preserved.');
}

module.exports = {
  parseMarkdownSections,
  parseAddonSections,
  promoteBetaMarkdown,
  promoteBetaAddon,
  consolidateStableMarkdown,
  consolidateStableAddon
};

if (require.main === module) {
  const args = process.argv.slice(2);
  const command = args[0];
  if (command === 'beta' || command === 'stable') {
    prepare(command, args[1], args.slice(2));
  } else if (command === 'reset') {
    resetDevelopmentMetadata();
  } else {
    console.error('Usage:');
    console.error('  node .tools/create_release.js beta <version-betaN> [--date YYYY-MM-DD]');
    console.error('  node .tools/create_release.js stable <version> [--date YYYY-MM-DD]');
    console.error('  node .tools/create_release.js reset');
    process.exit(1);
  }
}
