const assert = require("node:assert");
const { median } = require("./stats");

assert.strictEqual(median([3, 1, 2]), 2);
console.log("ok");
