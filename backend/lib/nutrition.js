if (process.env.NODE_ENV !== 'production') {
  try { require('dotenv').config(); } catch {}
}
const fetch = require('node-fetch');

const NUTRIENT_IDS = {
  calories:  1008,
  protein_g: 1003,
  fat_g:     1004,
  carbs_g:   1005,
  fiber_g:   1079,
  sugar_g:   2000,
  sodium_mg: 1093,
};

// Weight in grams for units we can convert deterministically; null when the
// unit is a count ("יח׳"), missing, or unknown.
function knownGrams(amount, unit) {
  const a = Number(amount);
  if (!Number.isFinite(a) || a <= 0) return null;
  const u = (unit || '').trim();
  if (/^(גרם|ג[׳']?|ג|g|gr)$/i.test(u))           return a;
  if (/^(ק[״"']ג|kg)$/i.test(u))                 return a * 1000;
  if (/^(מ[״"']ל|ml|מל|מ'ל)$/i.test(u))          return a;
  if (/^(ליטר|l)$/i.test(u))                     return a * 1000;
  if (/^כף(ות)?$/.test(u))                       return a * 15;
  if (/^כפי(ת|ות)$/.test(u))                     return a * 5;
  if (/^כוס(ות)?$/.test(u))                      return a * 240;
  return null;
}

function toGrams(amount, unit) {
  return knownGrams(amount, unit) ?? 100;
}

const NUTRIENT_KEYS = Object.keys(NUTRIENT_IDS);

// One Claude call per recipe: for every ingredient, a precise USDA search query,
// an estimated weight for the given amount/unit (used when the unit can't be
// converted, e.g. "2 יח׳" onions), and per-100g reference values used to catch
// wrong USDA matches.
async function analyzeIngredients(ingredients, apiKey, stepsText = '') {
  const list = ingredients.map(i => ({
    name: (i.name || '').trim(), amount: i.amount ?? null, unit: i.unit ?? null, note: i.note ?? null,
  }));
  const prompt = `You are a nutrition assistant. For each Hebrew recipe ingredient below return an object with:
- "en": short English name
- "usda_query": a USDA FoodData Central search query for the RAW/plain form as used in cooking (e.g. "beef brisket raw" not corned beef; "salt table" for any salt; "onions raw"; stock/broth is the ready-to-serve liquid, never cubes or concentrate)
- "grams": estimated total weight in grams of the given amount+unit (e.g. 2 medium onions = 300, 4 garlic cloves = 20, 2 bay leaves = 0.5). If amount is missing or "to taste", estimate what a typical recipe uses (salt to taste ≈ 3, oil for frying ≈ 15).
- "eaten_fraction": share of the ingredient that ends up eaten (0-1). Usually 1. Deep-frying oil ≈ 0.1 (only what is absorbed), salt in pasta/boiling water ≈ 0.1, marinade or brine that is discarded ≈ 0.2, dusting flour ≈ 0.5.
- "per100g": typical values per 100 g of the form used in the recipe (e.g. ready-to-serve beef broth ≈ 7 kcal and 370 mg sodium): calories, protein_g, fat_g, carbs_g, fiber_g, sugar_g, sodium_mg (numbers)
Return ONLY a JSON array, same order and length as the input.
Input: ${JSON.stringify(list)}${stepsText ? `\nRecipe steps (use them to judge eaten_fraction, e.g. a soaking brine that is drained): ${stepsText.slice(0, 4000)}` : ''}`;

  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: process.env.NUTRITION_MODEL || 'claude-haiku-4-5-20251001',
      max_tokens: 8192,
      messages: [{ role: 'user', content: prompt }],
    }),
  });
  if (!res.ok) throw new Error(`Claude API ${res.status}: ${await res.text()}`);
  const data = await res.json();
  const text = data.content[0].text.trim();
  const match = text.match(/\[[\s\S]*\]/);
  if (!match) throw new Error('Claude response not a JSON array');
  const arr = JSON.parse(match[0]);
  if (arr.length !== list.length) throw new Error(`Claude returned ${arr.length} items for ${list.length} ingredients`);
  return arr;
}

// Kept for scripts that only need names translated.
async function translateIngredients(names, apiKey) {
  const arr = await analyzeIngredients(names.map(name => ({ name })), apiKey);
  return arr.map(a => a.en);
}

function readFood(food) {
  const result = { description: food.description };
  for (const [key, id] of Object.entries(NUTRIENT_IDS)) {
    let n = food.foodNutrients?.find(fn => fn.nutrientId === id);
    if (!n && key === 'sugar_g') n = food.foodNutrients?.find(fn => fn.nutrientId === 1063);
    if (!n && key === 'calories') n = food.foodNutrients?.find(fn => fn.nutrientId === 2047 || fn.nutrientId === 2048);
    result[key] = n ? n.value : null;
  }
  return result;
}

// Top USDA matches for a query (first = USDA's best match).
async function fetchCandidates(query, usdaKey, pageSize = 5) {
  const url = `https://api.nal.usda.gov/fdc/v1/foods/search?query=${encodeURIComponent(query)}&api_key=${usdaKey}&dataType=Foundation,SR%20Legacy&pageSize=${pageSize}`;
  const res = await fetch(url);
  if (!res.ok) return [];
  const data = await res.json();
  return (data.foods || []).map(readFood);
}

async function fetchNutrients(query, usdaKey) {
  return (await fetchCandidates(query, usdaKey, 1))[0] || null;
}

const far = (a, b, absTol, ratio) =>
  Math.abs(a - b) > absTol && (Math.min(a, b) <= 0 || Math.max(a, b) / Math.min(a, b) > ratio);

// The USDA candidate closest to the reference values, otherwise the
// reference estimate. Accepts a single candidate or a list.
function pickNutrients(usda, est) {
  const e = {};
  for (const k of NUTRIENT_KEYS) e[k] = Number(est?.[k]) || 0;
  const candidates = (Array.isArray(usda) ? usda : [usda]).filter(Boolean);
  const dist = c => Math.abs(c.calories - e.calories) / Math.max(e.calories, 20)
                  + Math.abs((c.sodium_mg ?? 0) - e.sodium_mg) / Math.max(e.sodium_mg, 200);
  const match = candidates
    .filter(c => c.calories != null &&
      !far(c.calories, e.calories, 40, 1.6) &&
      !far(c.sodium_mg ?? 0, e.sodium_mg, 300, 3))
    .sort((a, b) => dist(a) - dist(b))[0];
  if (!match) return { values: e, source: 'estimate' };
  const values = {};
  for (const k of NUTRIENT_KEYS) values[k] = match[k] ?? e[k];
  return { values, source: 'usda', description: match.description };
}

async function calculateNutrition(recipe, apiKey, usdaKey) {
  if (usdaKey === 'DEMO_KEY') {
    console.warn('[nutrition] Using USDA DEMO_KEY — rate limited to 30 req/hr. Register a free key at https://fdc.nal.usda.gov/api-guide.html');
  }
  const ingredients = (recipe.ingredients || []).filter(i => (i.name || '').trim());
  if (!ingredients.length) return null;

  const stepsText = (recipe.steps || []).map(st => st.text || '').filter(Boolean).join(' | ');
  const analysis = await analyzeIngredients(ingredients, apiKey, stepsText);
  const usdaList = await Promise.all(
    analysis.map(a => (a?.usda_query || a?.en) ? fetchCandidates(a.usda_query || a.en, usdaKey).catch(() => []) : [])
  );

  const totals = Object.fromEntries(NUTRIENT_KEYS.map(k => [k, 0]));
  let totalGrams = 0;
  for (let i = 0; i < ingredients.length; i++) {
    const a = analysis[i] || {};
    const grams = knownGrams(ingredients[i].amount, ingredients[i].unit) ?? (Number(a.grams) > 0 ? Number(a.grams) : 100);
    const frac = Number(a.eaten_fraction);
    const eaten = grams * (frac >= 0 && frac <= 1 ? frac : 1);
    const { values, source, description } = pickNutrients(usdaList[i], a.per100g);
    console.log(`[nutrition] ${ingredients[i].name} → ${grams}g${eaten !== grams ? ` (eaten ${+eaten.toFixed(1)}g)` : ''}, ${source}${description ? ` (${description})` : ''}`);
    totalGrams += eaten;
    for (const k of NUTRIENT_KEYS) totals[k] += (values[k] * eaten) / 100;
  }

  if (totals.calories === 0) return null;

  const servings = recipe.servings || 1;
  return {
    calories:       Math.round(totals.calories   / servings),
    protein_g:      +(totals.protein_g  / servings).toFixed(1),
    fat_g:          +(totals.fat_g      / servings).toFixed(1),
    carbs_g:        +(totals.carbs_g    / servings).toFixed(1),
    fiber_g:        +(totals.fiber_g    / servings).toFixed(1),
    sugar_g:        +(totals.sugar_g    / servings).toFixed(1),
    sodium_mg:      Math.round(totals.sodium_mg  / servings),
    total_weight_g: +(totalGrams        / servings).toFixed(1),
    per_servings:   servings,
  };
}

module.exports = { toGrams, knownGrams, pickNutrients, analyzeIngredients, translateIngredients, fetchNutrients, fetchCandidates, calculateNutrition, NUTRIENT_IDS };
