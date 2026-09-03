const fs = require('fs');

const buttonsXml = fs.readFileSync('ItemRack/ItemRackButtons.xml', 'utf8');
const optionsXml = fs.readFileSync('ItemRackOptions/ItemRackOptions.xml', 'utf8');
const buttonsLua = fs.readFileSync('ItemRack/ItemRackButtons.lua', 'utf8');
const coreLua = fs.readFileSync('ItemRack/ItemRack.lua', 'utf8');
let checks = 0;

function check(value, message) {
  if (!value) throw new Error(`[SECURE TEMPLATES] ${message}`);
  checks += 1;
}

function contains(text, fragment, message) {
  check(text.includes(fragment), message);
}

function excludes(text, pattern, message) {
  check(!pattern.test(text), message);
}

function templateBody(text, name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = new RegExp(`<CheckButton\\s+name=["']${escaped}["'][^>]*>([\\s\\S]*?)<\\/CheckButton>`).exec(text);
  check(match, `missing expanded template ${name}`);
  return match[1];
}

function hasNamedRegion(body, suffix) {
  return new RegExp(`name=["']\\$parent${suffix}["']`).test(body);
}

try {
  excludes(buttonsXml, /inherits=["'][^"']*\b(?:ActionBarButtonTemplate|ActionButtonTemplate)\b/,
    'quick-access XML must not inherit Blizzard action-bar presentation templates');
  excludes(optionsXml, /inherits=["'][^"']*\b(?:ActionBarButtonTemplate|ActionButtonTemplate|SecureActionButtonTemplate)\b/,
    'options selectors must remain visual-only and unprotected');
  excludes(coreLua, /["'](?:ActionBarButtonTemplate|ActionButtonTemplate)["']/,
    'runtime-created popup buttons must not use Blizzard action templates');

  contains(buttonsXml,
    '<CheckButton name="ItemRackButtonsTemplate" inherits="ItemRackButtonVisualTemplate,SecureActionButtonTemplate" virtual="true"/>',
    'inventory slots must combine ItemRack visuals with SecureActionButtonTemplate');
  for (let slot = 0; slot < 20; slot += 1) {
    contains(buttonsXml,
      `<CheckButton name="ItemRackButton${slot}" inherits="ItemRackButtonsTemplate" id="${slot}"/>`,
      `inventory slot ${slot} must use the protected ItemRack template`);
  }
  contains(buttonsXml,
    '<CheckButton name="ItemRackButton20" inherits="ItemRackButtonVisualTemplate" id="20"/>',
    'set button must remain visual-only and unprotected');

  const quickBody = templateBody(buttonsXml, 'ItemRackButtonVisualTemplate');
  for (const suffix of ['ItemRackIcon', 'Border', 'Queue', 'Count', 'HotKey', 'Name', 'Cooldown']) {
    check(hasNamedRegion(quickBody, suffix), `quick-access template is missing $parent${suffix}`);
  }

  const menuBody = templateBody(buttonsXml, 'ItemRackMenuItemTemplate');
  for (const suffix of ['Icon', 'Border', 'Count', 'HotKey', 'Name', 'Cooldown']) {
    check(hasNamedRegion(menuBody, suffix), `popup template is missing $parent${suffix}`);
  }
  excludes(menuBody, /SecureActionButtonTemplate|ActionBarButtonTemplate|ActionButtonTemplate/,
    'popup item template must remain visual-only');
  contains(coreLua,
    'CreateFrame("CheckButton","ItemRackMenu"..idx,ItemRackMenuFrame,"ItemRackMenuItemTemplate")',
    'runtime popup creation must use the ItemRack-owned visual template');
  contains(coreLua, 'Icon = _G[name.."Icon"]',
    'popup Masque registration must provide its owned icon explicitly');
  contains(coreLua, 'Cooldown = _G[name.."Cooldown"]',
    'popup Masque registration must provide its owned cooldown explicitly');

  const optionBody = templateBody(optionsXml, 'ItemRackOptIconButtonTemplate');
  for (const suffix of ['Icon', 'Border']) {
    check(hasNamedRegion(optionBody, suffix), `options icon template is missing $parent${suffix}`);
  }
  contains(optionsXml,
    '<CheckButton name="ItemRackOptInvTemplate" inherits="ItemRackOptIconButtonTemplate" virtual="true">',
    'inventory options must use the owned visual template');
  contains(optionsXml,
    '<CheckButton name="ItemRackOptSetsCurrentSet" inherits="ItemRackOptIconButtonTemplate">',
    'set selector must use the owned visual template');

  excludes(buttonsLua,
    /ActionBarButtonEventsFrame|ActionBarActionEventsFrame|ActionBarButtonUpdateFrame|ActionBarButtonRangeCheckFrame/,
    'ItemRack must not edit Blizzard action-bar dispatcher tables');
  excludes(buttonsLua, /\.Show\s*=\s*function|\.SetText\s*=\s*function/,
    'owned regions and protected methods must not be monkey-patched');
  contains(buttonsLua, 'if ItemRackUser.Locked=="ON" or InCombatLockdown() then return end',
    'dragging protected slot buttons must be rejected during combat');
  contains(buttonsLua, 'button:SetAttribute("shift-type1",ATTRIBUTE_NOOP)',
    'shift-left ItemRack handling must suppress the secure item action');
  contains(buttonsLua, 'button:SetAttribute("alt-type2",ATTRIBUTE_NOOP)',
    'alt-right configuration clicks must suppress the secure item action');
  contains(buttonsLua, 'and ItemRackSettings.MenuOnRight ~= "ON"',
    'right-click secure use must be disabled while menu-on-right is active');

  console.log(`[SECURE TEMPLATES] ${checks} ownership, protection, and region checks passed.`);
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
