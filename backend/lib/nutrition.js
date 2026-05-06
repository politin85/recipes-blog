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

function toGrams(amount, unit) {
  if (!amount || amount <= 0) return 100;
  const u = (unit || '').trim();
  if (/^(גרם|ג[׳']?|ג|g|gr)$/i.test(u))           return amount;
  if (/^(ק[״"']ג|kg)$/i.test(u))                 return amount * 1000;
  if (/^(מ[״"']ל|ml|מל|מ'ל)$/i.test(u))          return amount;
  if (/^(ליטר|l)$/i.test(u))                     return amount * 1000;
  if (/^כף(ות)?$/.test(u))                       return amount * 15;
  if (/^כפי(ת|ות)$/.test(u))                     return amount * 5;
  if (/^כוס(ות)?$/.test(u))                      return amount * 240;
  return 100;
}

async function translateIngredients(names, apiKey) {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 1024,
      messages: [{
        role: 'user',
        content: `Translate these Hebrew ingredient names to English, return JSON array only with same order: ${JSON.stringify(names)}`,
      }],
    }),
  });
  if (!res.ok) throw new Error(`Claude API ${res.status}: ${await res.text()}`);
  const data = await res.json();
  const text = data.content[0].text.trim();
  const match = text.match(/\[[\s\S]*\]/);
  if (!match) throw new Error('Claude response not a JSON array');
  return JSON.parse(match[0]);
}

async function fetchNutrients(ingredientEnglish, usdaKey) {
  const url = `https://api.nal.usda.gov/fdc/v1/foods/search?query=${encodeURIComponent(ingredientEnglish)}&api_key=${usdaKey}&dataType=Foundation,SR%20Legacy&pageSize=1`;
  const res = await fetch(url);
  if (!res.ok) return null;
  const data = await res.json();
  const food = data.foods?.[0];
  if (!food) return null;
  const result = {};
  for (const [key, id] of Object.entries(NUTRIENT_IDS)) {
    const n = food.foodNutrients?.find(fn => fn.nutrientId === id);
    result[key] = n?.value ?? 0;
  }
  return result;
}

async function calculateNutrition(recipe, apiKey, usdaKey) {
  if (usdaKey === 'DEMO_KEY') {
    console.warn('[nutrition] Using USDA DEMO_KEY — rate limited to 30 req/hr. Register a free key at https://fdc.nal.usda.gov/api-guide.html');
  }
  const ingredients = recipe.ingredients || [];
  if (!ingredients.length) return null;

  const names = ingredients.map(i => (i.name || '').trim()).filter(Boolean);
  if (!names.length) return null;

  const englishNames = await translateIngredients(names, apiKey);
  const totals = { calories: 0, protein_g: 0, fat_g: 0, carbs_g: 0, fiber_g: 0, sugar_g: 0, sodium_mg: 0 };
  let totalGrams = 0;

  const nutrientsList = await Promise.all(
    ingredients.map((ing, i) => {
      const engName = (englishNames[i] || names[i] || '').trim();
      return engName ? fetchNutrients(engName, usdaKey) : Promise.resolve(null);
    })
  );

  for (let i = 0; i < ingredients.length; i++) {
    const nutrients = nutrientsList[i];
    if (!nutrients) continue;
    const grams = toGrams(ingredients[i].amount, ingredients[i].unit);
    totalGrams += grams;
    for (const key of Object.keys(totals)) {
      totals[key] += (nutrients[key] * grams) / 100;
    }
  }

  if (totals.calories === 0) return null;

  const servings = recipe.servings || 1;
  console.log(`[nutrition] recipe "${recipe.title}" — raw servings value: ${JSON.stringify(recipe.servings)}, using: ${servings}, total calories before division: ${totals.calories.toFixed(1)}`);
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

module.exports = { toGrams, translateIngredients, fetchNutrients, calculateNutrition, NUTRIENT_IDS };
