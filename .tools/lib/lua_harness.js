const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

function memberName(identifier) {
  if (!identifier) return undefined;
  if (identifier.type === 'Identifier') return identifier.name;
  if (identifier.type !== 'MemberExpression') return undefined;
  const base = memberName(identifier.base);
  const member = identifier.identifier && identifier.identifier.name;
  return base && member ? `${base}.${member}` : undefined;
}

function visit(node, callback) {
  if (!node || typeof node !== 'object') return;
  callback(node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) {
      for (const child of value) visit(child, callback);
    } else if (value && typeof value === 'object') {
      visit(value, callback);
    }
  }
}

function extractFunction(file, qualifiedName) {
  const source = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
  const ast = luaparse.parse(source, { luaVersion: '5.1', ranges: true });
  let match;
  visit(ast, (node) => {
    if (
      !match &&
      node.type === 'FunctionDeclaration' &&
      memberName(node.identifier) === qualifiedName
    ) {
      match = node;
    }
  });
  if (!match) throw new Error(`Could not find ${qualifiedName} in ${file}`);
  return source.slice(match.range[0], match.range[1]);
}

function luaError(L, context) {
  const message = lua.lua_tojsstring(L, -1);
  lua.lua_pop(L, 1);
  return new Error(`${context}: ${message}`);
}

function runLua(source, chunkName = 'runtime-test') {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const status = lauxlib.luaL_loadbuffer(
    L,
    to_luastring(source),
    null,
    to_luastring(path.basename(chunkName))
  );
  if (status !== lua.LUA_OK) throw luaError(L, `Lua load failed for ${chunkName}`);
  const callStatus = lua.lua_pcall(L, 0, 0, 0);
  if (callStatus !== lua.LUA_OK) throw luaError(L, `Lua execution failed for ${chunkName}`);
}

module.exports = { extractFunction, runLua };
