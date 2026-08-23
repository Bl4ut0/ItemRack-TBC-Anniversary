const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error('Usage: node .tools/check_lua.js <lua_file> [lua_file ...]');
  process.exit(1);
}

let failed = false;
for (const filePath of files) {
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    luaparse.parse(content, {
      comments: false,
      luaVersion: '5.1'
    });
    console.log(`[VALIDATOR] ${filePath} syntax is valid Lua 5.1.`);
  } catch (error) {
    failed = true;
    console.error(`[VALIDATOR] ${filePath}: ${error.message}`);
  }
}

if (failed) {
  process.exit(1);
}
