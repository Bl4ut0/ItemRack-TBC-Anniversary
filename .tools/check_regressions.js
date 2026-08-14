const assert = require('assert');
const fs = require('fs');
const releaseTools = require('./create_release');

const read = (filePath) => fs.readFileSync(filePath, 'utf8');
const core = read('ItemRack/ItemRack.lua');
const equip = read('ItemRack/ItemRackEquip.lua');
const events = read('ItemRack/ItemRackEvents.lua');
const buildScript = read('.tools/build_release_dev.ps1');
const installScript = read('.tools/install_local.ps1');
const releaseWorkflow = read('.agent/workflows/release.md');
const technicalChanges = read('TECHNICAL_CHANGES.md');

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

const tooltipHook = between(
  core,
  'function ItemRack.ListSetsHavingItem',
  'function ItemRack.InitCore'
);
check(!tooltipHook.includes('tooltip:Show()'), 'Tooltip post-hooks must not call Show().');
check(tooltipHook.includes('MatchesStoredItemID'), 'Tooltip set membership must be rune-aware.');

const setEquipped = between(
  equip,
  'function ItemRack.IsSetEquipped',
  'function ItemRack.UnequipSet'
);
check(!setEquipped.includes('ItemRack.SameID'), 'IsSetEquipped must not use base-only matching.');
check(setEquipped.includes('matchesStored(set[i],id)'), 'Set slots must use stored-item matching.');
check(setEquipped.includes('matchesStored(slotQueue[q].id, id)'), 'Queue membership must use stored-item matching.');
check(
  setEquipped.includes('local _, active = ItemRack.AutoQueueItemToEquip'),
  'IsSetEquipped must compare the exact queued entry, not AutoQueueItemToEquip\'s base-ID return.'
);
check(
  equip.includes('ItemRack.MatchesStoredItemID(swap[k+1],ItemRack.GetID(i))'),
  'Inner-slot shuffles must distinguish rune-bearing copies.'
);
check(
  events.includes('ItemRack.MatchesStoredItemID(intendedOffhand, currentOffhand)') &&
    events.includes('ItemRack.MatchesStoredItemID(intendedMainhand, currentMainhand)'),
  'Dual-wield retries must compare the saved rune identity.'
);
check(equip.includes('secureMacroMismatch'), 'Secure in-combat macro mismatches must be retained.');

check(
  events.includes('function ItemRack.ProcessSpecializationEvent(force)') &&
    events.includes('if not force and ItemRack.LastLastSpec == currentSpec then return end'),
  'Specialization events must support a forced same-spec evaluation.'
);
check(
  events.includes('ItemRack.RunAllEvents("Global events enabled", true)'),
  'Globally re-enabled events must force specialization evaluation.'
);
check(
  events.includes('local wasActive = eventData and eventData.Active') &&
    events.includes('elseif wasActive and eventData and eventData.Unequip then'),
  'Spin-down fallback must be limited to previously active events.'
);

check(
  /table\.remove\(ItemRack\.SetsWaiting,1\)[\s\S]{0,260}ItemRack\.SetsWaitingStartedAt = GetTime\(\)/.test(equip),
  'Every dequeued waiting request must reset the watchdog budget.'
);
check(
  equip.includes('retryRequest[7] = true') &&
    equip.includes('ItemRack.IsWatchdogRetry = true') &&
    equip.includes('ItemRack.IsWatchdogRetry and true or nil'),
  'The watchdog must preserve the newest manual request for one bounded retry.'
);
check(
  core.includes('ItemRack.BuildID = ItemRack.Version == "Dev"'),
  'BuildID must derive from packaged TOC metadata.'
);
check(
  !buildScript.includes('$version = "') &&
    buildScript.includes('[Parameter(Mandatory = $true)]') &&
    buildScript.includes('does not identify release version $Version'),
  'The packager must require an explicit version instead of retaining a stale hard-coded release.'
);
check(
  installScript.includes('[string]$SourceRoot') && installScript.includes('SupportsShouldProcess'),
  'Local installation must accept exact staged source and support a dry run.'
);
check(
  releaseWorkflow.includes('Track A: Beta release') && releaseWorkflow.includes('Track B: Primary (stable) release'),
  'The canonical workflow must retain both release tracks.'
);
check(
  !fs.existsSync('.agent/workflows/beta_release.md') && !fs.existsSync('.agent/workflows/update_version.md'),
  'Retired contradictory release workflows must not remain present.'
);
check(
  !technicalChanges.includes('Calling `Show()` on `GameTooltip` is safe and taint-free'),
  'Technical guidance must not claim insecure tooltip Show calls are safe.'
);

const betaMarkdown = `# Changelog\n\n## [Development]\n\n### Bug Fixes & Improvements\n- Beta change\n\n## [4.0] - 2025-01-01\n- Old\n`;
const promotedMarkdown = releaseTools.promoteBetaMarkdown(betaMarkdown, '4.1-beta1', '2026-08-14').text;
check(promotedMarkdown.includes('## [4.1-beta1] - 2026-08-14'), 'Beta Markdown promotion failed.');
check(releaseTools.parseMarkdownSections(promotedMarkdown).find((section) => section.version === 'Development').body === '', 'Beta promotion must clear Development.');

const betaAddon = `__ Development __\n\n- Beta change\n\n__ New in 4.0 - By Bl4ut0 __\n- Old\n`;
const promotedAddon = releaseTools.promoteBetaAddon(betaAddon, '4.1-beta1');
check(promotedAddon.includes('__ New in 4.1-beta1 - By Bl4ut0 __'), 'Beta in-addon promotion failed.');

const stableMarkdown = `# Changelog\n\n## [Development]\n\n- Final adjustment\n\n## [4.2-beta2] - 2026-08-12\n### Bug Fixes & Improvements\n- Beta two\n\n## [4.2-beta1] - 2026-08-01\n### Bug Fixes & Improvements\n- Beta one\n\n## [4.1] - 2026-07-01\n- Old\n`;
const consolidatedMarkdown = releaseTools.consolidateStableMarkdown(stableMarkdown, '4.2', '2026-08-14').text;
check(consolidatedMarkdown.includes('## [4.2] - 2026-08-14'), 'Stable Markdown section was not created.');
check(!consolidatedMarkdown.includes('4.2-beta'), 'Stable Markdown must remove consolidated beta headers.');
check(
  consolidatedMarkdown.indexOf('- Final adjustment') < consolidatedMarkdown.indexOf('- Beta two') &&
    consolidatedMarkdown.indexOf('- Beta two') < consolidatedMarkdown.indexOf('- Beta one'),
  'Stable Markdown must preserve final, newest-beta, oldest-beta order.'
);

const stableAddon = `__ Development __\n\n- Final adjustment\n\n__ New in 4.2-beta2 - By Bl4ut0 __\n- Beta two\n\n__ New in 4.2-beta1 - By Bl4ut0 __\n- Beta one\n\n__ New in 4.1 - By Bl4ut0 __\n- Old\n`;
const consolidatedAddon = releaseTools.consolidateStableAddon(stableAddon, '4.2');
check(consolidatedAddon.includes('__ New in 4.2 - By Bl4ut0 __'), 'Stable in-addon section was not created.');
check(!consolidatedAddon.includes('4.2-beta'), 'Stable in-addon changelog must remove beta headers.');

console.log(`[REGRESSION] ${checks} release and behavior guards passed.`);
