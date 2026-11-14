set -eu
node -e '
const assert = require("node:assert");
const { median } = require("/work/stats.js");
assert.strictEqual(median([3, 1, 2]), 2);
assert.strictEqual(median([4, 1, 3, 2]), 2.5);
assert.strictEqual(median([10, 9, 100]), 10);
const input = [5, 1, 4];
median(input);
assert.deepStrictEqual(input, [5, 1, 4], "median must not mutate its input");
console.log("verify ok");
'
