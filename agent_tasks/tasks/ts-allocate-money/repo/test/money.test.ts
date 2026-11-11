import { test } from "node:test";
import assert from "node:assert/strict";
import { allocate } from "../src/money.js";

test("parts sum to the total", () => {
  for (const [total, weights] of [[100, [1, 1, 1]], [1001, [3, 3, 4]], [5, [1, 1, 1, 1, 1, 1]], [999, [0.5, 0.25, 0.25]]] as [number, number[]][]) {
    const parts = allocate(total, weights);
    assert.equal(parts.reduce((a, b) => a + b, 0), total, `${total} ${weights}`);
  }
});

test("remainder goes to the largest weights first", () => {
  assert.deepEqual(allocate(100, [1, 1, 1]), [34, 33, 33]);
  assert.deepEqual(allocate(10, [1, 2]), [3, 7]);
});

test("zero weights get nothing", () => {
  assert.deepEqual(allocate(50, [0, 1]), [0, 50]);
});
