const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const patch = fs.readFileSync(path.join(__dirname, 'patches/fullcone/luci.patch'), 'utf8');
const code = patch.split('\n').filter(line => line.startsWith('+') && !line.startsWith('+++'))
  .map(line => line.slice(1)).join('\n');
const values = new Map();
const choices = [];
const control = { value: value => choices.push(value) };
vm.runInNewContext(code, {
  o: null,
  s: { option: () => control },
  form: { ListValue: 'list' },
  _: text => text,
  uci: {
    get: (config, section, key) => values.get(key),
    set: (config, section, key, value) => values.set(key, value),
  },
});
assert.deepEqual(choices, ['0', '1', '2']);
assert.equal(control.cfgvalue('defaults'), '0');
assert.equal(values.size, 0, 'Opening the page must not enable or save FullCone');
for (const [mode, v4, v6] of [['1', '1', '0'], ['2', '1', '1'], ['0', '0', '0']]) {
  control.write('defaults', mode);
  assert.equal(values.get('fullcone4'), v4);
  assert.equal(values.get('fullcone6'), v6);
  assert.equal(control.cfgvalue('defaults'), mode);
}
console.log('FullCone UI defaults and all switch modes passed (mock UCI, no router access)');
