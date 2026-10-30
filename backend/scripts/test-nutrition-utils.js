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

const { knownGrams, pickNutrients } = require('../lib/nutrition');
assert.strictEqual(knownGrams('1000', 'גרם'), 1000, 'string amount from DB is a number');
assert.strictEqual(typeof knownGrams('300', 'מ״ל'), 'number', 'ml from DB string is a number');
assert.strictEqual(knownGrams('2', 'יח׳'), null, 'count unit is not convertible');
const est = { calories: 250, protein_g: 17, fat_g: 20, carbs_g: 0, fiber_g: 0, sugar_g: 0, sodium_mg: 60 };
assert.strictEqual(pickNutrients({ calories: 251, protein_g: 17.4, fat_g: 19.6, carbs_g: 0, fiber_g: 0, sugar_g: null, sodium_mg: 66 }, est).source, 'usda', 'matching USDA food is used');
assert.strictEqual(pickNutrients({ calories: 251, protein_g: 18, fat_g: 19, carbs_g: 0, fiber_g: 0, sugar_g: 0, sodium_mg: 973 }, est).source, 'estimate', 'corned (salty) match is rejected');
assert.strictEqual(pickNutrients({ calories: 0, sodium_mg: 0 }, { calories: 0, sodium_mg: 38758 }).source, 'estimate', 'salt with 0 sodium is rejected');
assert.strictEqual(pickNutrients(null, est).source, 'estimate', 'no USDA result → estimate');
console.log('All nutrition picking tests passed ✓');
const broth = { calories: 7, protein_g: 1, fat_g: 0, carbs_g: 0, fiber_g: 0, sugar_g: 0, sodium_mg: 370 };
const r = pickNutrients([{ description: 'cube', calories: 170, sodium_mg: 24000 }, { description: 'canned', calories: 8, sodium_mg: 372 }], broth);
assert.strictEqual(r.description, 'canned', 'skips wrong first candidate, picks matching one');
console.log('Candidate picking test passed ✓');
