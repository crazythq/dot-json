"use strict";
const path = require("path");
const { assertSafeUserPath } = require("../lib/safe-path.js");

let failed = 0;
function assert(cond, name) {
  if (!cond) {
    failed += 1;
    console.error("FAIL", name);
    return;
  }
  console.log("ok  ", name);
}

assert(assertSafeUserPath("/tmp/a.json", path) === path.normalize("/tmp/a.json"), "absolute ok");

let relThrew = false;
try {
  assertSafeUserPath("tmp/a.json", path);
} catch (_e) {
  relThrew = true;
}
assert(relThrew, "relative rejected");

let dotsThrew = false;
try {
  assertSafeUserPath("/tmp/../etc/passwd", path);
} catch (_e) {
  dotsThrew = true;
}
assert(dotsThrew, "dotdot rejected");

let emptyThrew = false;
try {
  assertSafeUserPath("", path);
} catch (_e) {
  emptyThrew = true;
}
assert(emptyThrew, "empty rejected");

if (failed) process.exit(1);
console.log("\nall passed");
