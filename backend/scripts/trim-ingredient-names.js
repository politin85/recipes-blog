// One-shot cleanup: trims leading/trailing whitespace from ingredient names
// across both `ingredients` and `ingredient_aliases`. Safe to re-run.
//
// Usage:
//   - Railway shell (DATABASE_URL already in env): node scripts/trim-ingredient-names.js
//   - Local (with backend/.env present):           node scripts/trim-ingredient-names.js
if (process.env.NODE_ENV !== 'production') require('dotenv').config();

const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });

async function main() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // ingredients.name — collapse trimmed duplicates by repointing recipe_ingredients
    // to whichever row already holds the trimmed name (or the trimmed row itself).
    const { rows: dirtyIngs } = await client.query(
      `SELECT id, name FROM ingredients WHERE name <> btrim(name)`
    );
    let mergedIngs = 0, renamedIngs = 0;
    for (const row of dirtyIngs) {
      const trimmed = row.name.trim();
      const { rows: existing } = await client.query(
        `SELECT id FROM ingredients WHERE name = $1 AND id <> $2 LIMIT 1`,
        [trimmed, row.id]
      );
      if (existing.length) {
        // Merge: repoint recipe_ingredients to the canonical (trimmed) row, then drop the dirty row.
        await client.query(
          `UPDATE recipe_ingredients SET ingredient_id = $1 WHERE ingredient_id = $2`,
          [existing[0].id, row.id]
        );
        await client.query(`DELETE FROM ingredients WHERE id = $1`, [row.id]);
        mergedIngs++;
      } else {
        await client.query(`UPDATE ingredients SET name = $1 WHERE id = $2`, [trimmed, row.id]);
        renamedIngs++;
      }
    }

    // ingredient_aliases — UPDATE in place; conflicts are resolved by deleting the dirty row.
    const { rows: dirtyAliases } = await client.query(
      `SELECT original_name, note, display_name
         FROM ingredient_aliases
        WHERE original_name <> btrim(original_name)
           OR display_name  <> btrim(display_name)`
    );
    let renamedAliases = 0, droppedAliases = 0;
    for (const a of dirtyAliases) {
      const newOrig    = (a.original_name || '').trim();
      const newDisplay = (a.display_name  || '').trim();
      const { rows: clash } = await client.query(
        `SELECT 1 FROM ingredient_aliases
          WHERE original_name = $1 AND COALESCE(note, '') = COALESCE($2, '')
            AND (original_name <> $3 OR display_name <> $4)
          LIMIT 1`,
        [newOrig, a.note, a.original_name, a.display_name]
      );
      if (clash.length) {
        await client.query(
          `DELETE FROM ingredient_aliases
            WHERE original_name = $1 AND COALESCE(note, '') = COALESCE($2, '')`,
          [a.original_name, a.note]
        );
        droppedAliases++;
      } else {
        await client.query(
          `UPDATE ingredient_aliases
              SET original_name = $1,
                  display_name  = $2
            WHERE original_name = $3 AND COALESCE(note, '') = COALESCE($4, '')`,
          [newOrig, newDisplay, a.original_name, a.note]
        );
        renamedAliases++;
      }
    }

    await client.query('COMMIT');
    console.log(`ingredients: ${renamedIngs} renamed, ${mergedIngs} merged into existing rows`);
    console.log(`ingredient_aliases: ${renamedAliases} renamed, ${droppedAliases} dropped (duplicate of trimmed key)`);
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

main()
  .then(() => pool.end())
  .catch(err => { console.error(err); pool.end().finally(() => process.exit(1)); });
