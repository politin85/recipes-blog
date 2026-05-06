const assert = require('assert');
const { toGrams } = require('../lib/nutrition');

assert.strictEqual(toGrams(200, 'גרם'),  200,  'grams pass-through');
assert.strictEqual(toGrams(1,   'ק"ג'), 1000, 'kg to grams');
assert.strictEqual(toGrams(2,   'כף'),   30,   'tablespoon = 15g each');
assert.strictEqual(toGrams(1,   'כפית'), 5,    'teaspoon = 5g');
assert.strictEqual(toGrams(1,   'כוס'),  240,  'cup = 240g');
assert.strictEqual(toGrams(500, 'מל'),   500,  'ml ≈ grams');
assert.strictEqual(toGrams(null,'גרם'),  100,  'null amount → 100g default');
assert.strictEqual(toGrams(0,   'גרם'),  100,  'zero amount → 100g default');
assert.strictEqual(toGrams(50,  'unk'),  100,  'unknown unit → 100g default');
console.log('All toGrams tests passed ✓');
