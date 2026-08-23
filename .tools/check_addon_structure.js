const fs = require('fs');
const path = require('path');

const cliArgs = process.argv.slice(2);
const allowVersionMismatch = cliArgs.includes('--allow-version-mismatch');
const rootArgument = cliArgs.find((argument) => !argument.startsWith('--'));
const sourceRoot = path.resolve(rootArgument || path.join(__dirname, '..'));
const addonNames = ['ItemRack', 'ItemRackOptions'];
let checks = 0;

function fail(message) {
  throw new Error(`[STRUCTURE] ${message}`);
}

function normalizeAddonPath(value) {
  return value.replace(/[\\/]+/g, path.sep);
}

function assertChildPath(candidate, parent, label) {
  const relative = path.relative(parent, candidate);
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
    fail(`${label} resolves outside its addon directory: ${candidate}`);
  }
}

function walk(directory, extension, results = []) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      walk(fullPath, extension, results);
    } else if (entry.isFile() && entry.name.toLowerCase().endsWith(extension)) {
      results.push(fullPath);
    }
  }
  return results;
}

function scanXmlTags(text, filePath) {
  const stack = [];
  let rootCount = 0;
  let cursor = 0;

  while (cursor < text.length) {
    const open = text.indexOf('<', cursor);
    if (open === -1) break;

    if (text.startsWith('<!--', open)) {
      const close = text.indexOf('-->', open + 4);
      if (close === -1) fail(`${filePath} contains an unterminated XML comment.`);
      cursor = close + 3;
      continue;
    }
    if (text.startsWith('<![CDATA[', open)) {
      const close = text.indexOf(']]>', open + 9);
      if (close === -1) fail(`${filePath} contains an unterminated CDATA section.`);
      cursor = close + 3;
      continue;
    }

    let quote = null;
    let close = open + 1;
    for (; close < text.length; close += 1) {
      const character = text[close];
      if (quote) {
        if (character === quote) quote = null;
      } else if (character === '"' || character === "'") {
        quote = character;
      } else if (character === '>') {
        break;
      }
    }
    if (close >= text.length) fail(`${filePath} contains an unterminated XML tag.`);

    const raw = text.slice(open + 1, close).trim();
    cursor = close + 1;
    if (!raw || raw.startsWith('?') || raw.startsWith('!')) continue;

    const closing = raw.startsWith('/');
    const selfClosing = /\/$/.test(raw);
    const nameMatch = /^\/?\s*([A-Za-z_][\w:.-]*)/.exec(raw);
    if (!nameMatch) fail(`${filePath} contains an invalid XML tag near offset ${open}.`);
    const name = nameMatch[1];

    if (closing) {
      const expected = stack.pop();
      if (expected !== name) {
        fail(`${filePath} closes <${name}> while <${expected || '(none)'}> is open.`);
      }
    } else {
      if (stack.length === 0) rootCount += 1;
      if (!selfClosing) stack.push(name);
    }
  }

  if (stack.length > 0) fail(`${filePath} does not close <${stack[stack.length - 1]}>.`);
  if (rootCount !== 1) fail(`${filePath} must contain exactly one XML root element; found ${rootCount}.`);
  checks += 1;
}

function validateXmlReferences(text, filePath, addonRoot) {
  const referencePattern = /<(Script|Include)\b[^>]*\bfile\s*=\s*(["'])(.*?)\2[^>]*>/gi;
  for (const match of text.matchAll(referencePattern)) {
    const target = path.resolve(path.dirname(filePath), normalizeAddonPath(match[3]));
    assertChildPath(target, addonRoot, `${path.relative(sourceRoot, filePath)} ${match[1]} reference`);
    if (!fs.existsSync(target) || !fs.statSync(target).isFile()) {
      fail(`${path.relative(sourceRoot, filePath)} references missing file ${match[3]}.`);
    }
    checks += 1;
  }
}

function validateToc(addonName) {
  const addonRoot = path.join(sourceRoot, addonName);
  const tocPath = path.join(addonRoot, `${addonName}.toc`);
  if (!fs.existsSync(tocPath)) fail(`Missing ${path.relative(sourceRoot, tocPath)}.`);

  const text = fs.readFileSync(tocPath, 'utf8').replace(/^\uFEFF/, '');
  const versionMatches = Array.from(text.matchAll(/^## Version:\s*(\S+)\s*$/gm));
  if (versionMatches.length !== 1) {
    fail(`${path.relative(sourceRoot, tocPath)} must contain exactly one Version field.`);
  }

  let sourceEntries = 0;
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const target = path.resolve(addonRoot, normalizeAddonPath(line));
    assertChildPath(target, addonRoot, `${addonName}.toc entry`);
    if (!fs.existsSync(target) || !fs.statSync(target).isFile()) {
      fail(`${addonName}.toc references missing file ${line}.`);
    }
    sourceEntries += 1;
    checks += 1;
  }
  if (sourceEntries === 0) fail(`${addonName}.toc contains no loadable source entries.`);

  for (const xmlPath of walk(addonRoot, '.xml')) {
    const xml = fs.readFileSync(xmlPath, 'utf8').replace(/^\uFEFF/, '');
    scanXmlTags(xml, path.relative(sourceRoot, xmlPath));
    validateXmlReferences(xml, xmlPath, addonRoot);
  }

  return versionMatches[0][1];
}

try {
  const versions = addonNames.map(validateToc);
  if (!allowVersionMismatch && versions[0] !== versions[1]) {
    fail(`Addon TOC versions differ: ItemRack=${versions[0]}, ItemRackOptions=${versions[1]}.`);
  }
  checks += 1;
  const versionLabel = versions[0] === versions[1]
    ? `version ${versions[0]}`
    : `transitional versions ${versions.join(' / ')}`;
  console.log(`[STRUCTURE] ${checks} TOC, XML, and file-reference checks passed for ${versionLabel}.`);
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
