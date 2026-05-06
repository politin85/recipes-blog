if (process.env.NODE_ENV !== 'production') { try { require('dotenv').config(); } catch {} }
const { Pool } = require('pg');
const { calculateNutrition } = require('../lib/nutrition');

const args = process.argv.slice(2);
const limitArg     = args.find(a => a.startsWith('--limit='));
const recipeIdArg  = args.find(a => a.startsWith('--recipe-id='));
const skipExisting = args.includes('--skip-existing');

const LIMIT     = limitArg    ? parseInt(limitArg.split('=')[1])    : null;
const RECIPE_ID = recipeIdArg ? parseInt(recipeIdArg.split('=')[1]) : null;

const apiKey  = process.env.ANTHROPIC_API_KEY;
const usdaKey = process.env.USDA_API_KEY || 'DEMO_KEY';
if (usdaKey === 'DEMO_KEY') console.warn('[fetch-nutrition] Using USDA DEMO_KEY — rate limited to 30 req/hr. Register free at https://fdc.nal.usda.gov/api-guide.html');

if (!apiKey) { console.error('Error: ANTHROPIC_API_KEY is required'); process.exit(1); }

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

async function main() {
  const params = [];
  let query = `
    SELECT r.id, r.title, r.servings,
           json_agg(json_build_object('name', i.name, 'amount', ri.amount, 'unit', ri.unit) ORDER BY ri.id) AS ingredients
    FROM recipes r
    JOIN recipe_ingredients ri ON ri.recipe_id = r.id
    JOIN ingredients i ON i.id = ri.ingredient_id
  `;

  if (RECIPE_ID) {
    params.push(RECIPE_ID);
    query += ` WHERE r.id = $${params.length}`;
  }
  query += ' GROUP BY r.id ORDER BY r.id';
  if (LIMIT) {
    params.push(LIMIT);
    query += ` LIMIT $${params.length}`;
  }

  let { rows: recipes } = await pool.query(query, params);

  if (skipExisting) {
    const { rows: existing } = await pool.query('SELECT recipe_id FROM nutrition');
    const existingIds = new Set(existing.map(r => r.recipe_id));
    recipes = recipes.filter(r => !existingIds.has(r.id));
  }

  console.log(`Processing ${recipes.length} recipe(s)...`);
  let processed = 0, skipped = 0, errors = 0;

  for (const recipe of recipes) {
    try {
      process.stdout.write(`[${processed + skipped + errors + 1}/${recipes.length}] ${recipe.title}... `);
      const result = await calculateNutrition(recipe, apiKey, usdaKey);
      if (!result) {
        console.log('skipped (no ingredients)');
        skipped++;
        continue;
      }
      await pool.query(
        `INSERT INTO nutrition
           (recipe_id, calories, protein_g, fat_g, carbs_g, sugar_g, fiber_g, sodium_mg, per_servings, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,NOW())
         ON CONFLICT (recipe_id) DO UPDATE SET
           calories=$2, protein_g=$3, fat_g=$4, carbs_g=$5, sugar_g=$6, fiber_g=$7,
           sodium_mg=$8, per_servings=$9, updated_at=NOW()`,
        [recipe.id, result.calories, result.protein_g, result.fat_g, result.carbs_g,
         result.sugar_g, result.fiber_g, result.sodium_mg, result.per_servings]
      );
      console.log(`✓ ${result.calories} kcal | protein ${result.protein_g}g | fat ${result.fat_g}g | carbs ${result.carbs_g}g`);
      processed++;
    } catch (err) {
      console.log(`✗ Error: ${err.message}`);
      errors++;
    }
  }

  console.log(`\nDone: ${processed} saved, ${skipped} skipped, ${errors} errors`);
}

main()
  .then(() => pool.end())
  .catch(err => { console.error(err); pool.end().finally(() => process.exit(1)); });
