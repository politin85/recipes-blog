if (process.env.NODE_ENV !== 'production') {
  require('dotenv').config();
}

const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const fetch = require('node-fetch');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json({ limit: '10mb' }));

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

// ─── DB init ──────────────────────────────────────────────────────────────────

async function initDB() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS recipes (
      id          SERIAL PRIMARY KEY,
      title       TEXT NOT NULL,
      description TEXT,
      difficulty  VARCHAR(10) CHECK (difficulty IN ('easy', 'medium', 'hard')),
      prep_time   INTEGER,
      cook_time   INTEGER,
      servings    INTEGER,
      category    TEXT,
      tags        TEXT[]    DEFAULT '{}',
      image_url   TEXT,
      created_at  TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS ingredients (
      id               SERIAL PRIMARY KEY,
      name             TEXT UNIQUE NOT NULL,
      is_pantry_staple BOOLEAN DEFAULT FALSE
    );

    CREATE TABLE IF NOT EXISTS recipe_ingredients (
      recipe_id     INTEGER REFERENCES recipes(id)     ON DELETE CASCADE,
      ingredient_id INTEGER REFERENCES ingredients(id) ON DELETE CASCADE,
      amount        NUMERIC,
      unit          TEXT,
      note          TEXT,
      PRIMARY KEY (recipe_id, ingredient_id)
    );

    CREATE TABLE IF NOT EXISTS steps (
      id            SERIAL PRIMARY KEY,
      recipe_id     INTEGER REFERENCES recipes(id) ON DELETE CASCADE,
      step_order    INTEGER NOT NULL,
      title         TEXT,
      text          TEXT NOT NULL,
      image_url     TEXT,
      timer_seconds INTEGER
    );

    CREATE TABLE IF NOT EXISTS user_notes (
      id          SERIAL PRIMARY KEY,
      recipe_id   INTEGER REFERENCES recipes(id) ON DELETE CASCADE,
      note_text   TEXT NOT NULL,
      created_at  TIMESTAMP DEFAULT NOW()
    );
  `);

  // Seed pantry staples (idempotent)
  await pool.query(`
    INSERT INTO ingredients (name, is_pantry_staple) VALUES
      ('קמח', true), ('סוכר', true), ('מלח', true), ('שמן', true),
      ('ביצים', true), ('חמאה', true), ('שום', true), ('בצל', true),
      ('פלפל שחור', true), ('שמן זית', true), ('חומץ', true),
      ('סודה לשתייה', true), ('אבקת אפייה', true), ('וניל', true),
      ('קינמון', true), ('מים', true), ('חלב', true)
    ON CONFLICT (name) DO NOTHING;
  `);

  // Add new columns idempotently
  await pool.query(`
    ALTER TABLE recipes ADD COLUMN IF NOT EXISTS is_hidden  BOOLEAN DEFAULT FALSE;
    ALTER TABLE recipes ADD COLUMN IF NOT EXISTS story_text TEXT;
  `);

  console.log('DB ready');
}

// ─── Auth middleware ───────────────────────────────────────────────────────────

function requireAdmin(req, res, next) {
  const pw = req.headers['x-admin-password'];
  if (!process.env.ADMIN_PASSWORD || pw !== process.env.ADMIN_PASSWORD) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
}

// ─── Health ───────────────────────────────────────────────────────────────────

app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', db: 'connected' });
  } catch {
    res.status(500).json({ status: 'error', db: 'disconnected' });
  }
});

// ─── TTS proxy ────────────────────────────────────────────────────────────────

app.post('/tts', async (req, res) => {
  const { text, voice, gender } = req.body;
  if (!text) return res.status(400).json({ error: 'text required' });

  const voiceName =
    voice ||
    (gender === 'female' ? 'he-IL-Wavenet-A' : 'he-IL-Wavenet-B');

  try {
    const response = await fetch(
      `https://texttospeech.googleapis.com/v1/text:synthesize?key=${process.env.GOOGLE_TTS_API_KEY}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          input: { text },
          voice: { languageCode: 'he-IL', name: voiceName },
          audioConfig: { audioEncoding: 'MP3' },
        }),
      }
    );

    if (!response.ok) {
      const err = await response.text();
      return res.status(response.status).json({ error: err });
    }

    const data = await response.json();
    res.json({ audioContent: data.audioContent });
  } catch (err) {
    console.error('TTS error:', err);
    res.status(500).json({ error: 'TTS request failed' });
  }
});

// ─── Ingredients ──────────────────────────────────────────────────────────────

app.get('/api/ingredients', async (req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT i.*, COUNT(DISTINCT ri.recipe_id)::int AS recipe_count
       FROM ingredients i
       LEFT JOIN recipe_ingredients ri ON ri.ingredient_id = i.id
       GROUP BY i.id
       ORDER BY recipe_count DESC, i.name`
    );
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

// ─── Recipes: by-ingredients (must be before /:id) ───────────────────────────

app.post('/api/recipes/by-ingredients', async (req, res) => {
  const { ingredient_ids = [], include_pantry = true, mode } = req.body;
  if (!ingredient_ids.length) return res.json([]);

  try {
    if (mode === 'simple') {
      // Simple mode: rank by how many selected ingredients appear in the recipe (at least 1)
      const { rows } = await pool.query(
        `SELECT r.*,
           COUNT(DISTINCT ri.ingredient_id)
             FILTER (WHERE ri.ingredient_id = ANY($1::int[]))::int AS matched_count
         FROM recipes r
         JOIN recipe_ingredients ri ON ri.recipe_id = r.id
         WHERE r.is_hidden IS NOT TRUE
         GROUP BY r.id
         HAVING COUNT(DISTINCT ri.ingredient_id)
           FILTER (WHERE ri.ingredient_id = ANY($1::int[])) > 0
         ORDER BY matched_count DESC, r.created_at DESC`,
        [ingredient_ids]
      );
      return res.json(rows);
    }

    // % match mode: rank by selected matches first, then by coverage with pantry
    let available;
    if (include_pantry) {
      const { rows: staples } = await pool.query(
        'SELECT id FROM ingredients WHERE is_pantry_staple = TRUE'
      );
      available = [...new Set([...ingredient_ids, ...staples.map((r) => r.id)])];
    } else {
      available = [...new Set(ingredient_ids)];
    }

    const { rows: recipes } = await pool.query(
      `SELECT
         r.*,
         COUNT(DISTINCT ri.ingredient_id)::int AS total_ingredients,
         COUNT(DISTINCT ri.ingredient_id)
           FILTER (WHERE ri.ingredient_id = ANY($1::int[]))::int AS matched_selected,
         COUNT(DISTINCT ri.ingredient_id)
           FILTER (WHERE ri.ingredient_id = ANY($2::int[]))::int AS matched_available
       FROM recipes r
       JOIN recipe_ingredients ri ON ri.recipe_id = r.id
       WHERE r.is_hidden IS NOT TRUE
       GROUP BY r.id
       HAVING COUNT(DISTINCT ri.ingredient_id)
         FILTER (WHERE ri.ingredient_id = ANY($1::int[])) > 0`,
      [ingredient_ids, available]
    );

    const result = await Promise.all(
      recipes.map(async (recipe) => {
        const pct = Math.round(
          (recipe.matched_available / recipe.total_ingredients) * 100
        );
        let missing = [];
        if (pct < 100) {
          const { rows } = await pool.query(
            `SELECT i.id, i.name
             FROM recipe_ingredients ri
             JOIN ingredients i ON i.id = ri.ingredient_id
             WHERE ri.recipe_id = $1
               AND ri.ingredient_id != ALL($2::int[])`,
            [recipe.id, available]
          );
          missing = rows;
        }
        return { ...recipe, match_percent: pct, missing_ingredients: missing };
      })
    );

    res.json(
      result.sort((a, b) =>
        b.matched_selected - a.matched_selected || b.match_percent - a.match_percent
      )
    );
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

// ─── Recipes: list + create ───────────────────────────────────────────────────

app.get('/api/recipes', async (req, res) => {
  const { search, category, difficulty, include_hidden } = req.query;
  const isAdmin = req.headers['x-admin-password'] === process.env.ADMIN_PASSWORD;
  const conditions = [];
  const params = [];
  let i = 1;

  if (!(isAdmin && include_hidden === 'true')) {
    conditions.push('r.is_hidden = FALSE');
  }

  if (search) {
    conditions.push(
      `(r.title ILIKE $${i} OR EXISTS (
         SELECT 1 FROM unnest(r.tags) t WHERE t ILIKE $${i}
       ))`
    );
    params.push(`%${search}%`);
    i++;
  }
  if (category) {
    conditions.push(`r.category = $${i}`);
    params.push(category);
    i++;
  }
  if (difficulty) {
    conditions.push(`r.difficulty = $${i}`);
    params.push(difficulty);
    i++;
  }

  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

  try {
    const { rows } = await pool.query(
      `SELECT r.*, COUNT(ri.ingredient_id)::int AS ingredient_count
       FROM recipes r
       LEFT JOIN recipe_ingredients ri ON ri.recipe_id = r.id
       ${where}
       GROUP BY r.id
       ORDER BY r.created_at DESC`,
      params
    );
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

app.post('/api/recipes', requireAdmin, async (req, res) => {
  const {
    title, description, difficulty, prep_time, cook_time,
    servings, category, tags, image_url, ingredients, steps,
    is_hidden, story_text,
  } = req.body;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows: [recipe] } = await client.query(
      `INSERT INTO recipes
         (title, description, difficulty, prep_time, cook_time, servings, category, tags, image_url, is_hidden, story_text)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
       RETURNING *`,
      [title, description, difficulty, prep_time, cook_time, servings, category, tags ?? [], image_url, is_hidden ?? false, story_text ?? null]
    );

    await insertIngredientsAndSteps(client, recipe.id, ingredients, steps);

    await client.query('COMMIT');
    res.status(201).json(recipe);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  } finally {
    client.release();
  }
});

// ─── Recipes: single + update + delete ───────────────────────────────────────

app.get('/api/recipes/:id', async (req, res) => {
  const { id } = req.params;

  try {
    const { rows: [recipe] } = await pool.query(
      'SELECT * FROM recipes WHERE id = $1', [id]
    );
    if (!recipe) return res.status(404).json({ error: 'Not found' });

    const [{ rows: ingredients }, { rows: steps }, { rows: notes }, { rows: related }] =
      await Promise.all([
        pool.query(
          `SELECT i.id, i.name, i.is_pantry_staple, ri.amount, ri.unit, ri.note
           FROM recipe_ingredients ri
           JOIN ingredients i ON i.id = ri.ingredient_id
           WHERE ri.recipe_id = $1`,
          [id]
        ),
        pool.query(
          'SELECT * FROM steps WHERE recipe_id = $1 ORDER BY step_order', [id]
        ),
        pool.query(
          'SELECT * FROM user_notes WHERE recipe_id = $1 ORDER BY created_at DESC', [id]
        ),
        pool.query(
          `SELECT id, title, image_url, prep_time, cook_time, difficulty, category
           FROM recipes
           WHERE id != $1 AND (category = $2 OR tags && $3::text[])
           ORDER BY created_at DESC
           LIMIT 3`,
          [id, recipe.category, recipe.tags ?? []]
        ),
      ]);

    res.json({ ...recipe, ingredients, steps, notes, related });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

app.put('/api/recipes/:id', requireAdmin, async (req, res) => {
  const { id } = req.params;
  const {
    title, description, difficulty, prep_time, cook_time,
    servings, category, tags, image_url, ingredients, steps,
    is_hidden, story_text,
  } = req.body;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows: [recipe] } = await client.query(
      `UPDATE recipes
       SET title=$1, description=$2, difficulty=$3, prep_time=$4, cook_time=$5,
           servings=$6, category=$7, tags=$8, image_url=$9, is_hidden=$10, story_text=$11
       WHERE id=$12 RETURNING *`,
      [title, description, difficulty, prep_time, cook_time, servings, category, tags ?? [], image_url, is_hidden ?? false, story_text ?? null, id]
    );
    if (!recipe) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Not found' });
    }

    if (ingredients !== undefined) {
      await client.query('DELETE FROM recipe_ingredients WHERE recipe_id = $1', [id]);
    }
    if (steps !== undefined) {
      await client.query('DELETE FROM steps WHERE recipe_id = $1', [id]);
    }
    await insertIngredientsAndSteps(client, id, ingredients, steps);

    await client.query('COMMIT');
    res.json(recipe);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  } finally {
    client.release();
  }
});

app.delete('/api/recipes/:id', requireAdmin, async (req, res) => {
  try {
    const { rowCount } = await pool.query(
      'DELETE FROM recipes WHERE id = $1', [req.params.id]
    );
    if (!rowCount) return res.status(404).json({ error: 'Not found' });
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

// ─── User notes ───────────────────────────────────────────────────────────────

app.post('/api/recipes/:id/notes', async (req, res) => {
  const { note_text } = req.body;
  if (!note_text?.trim()) return res.status(400).json({ error: 'note_text required' });

  try {
    const { rows: [note] } = await pool.query(
      'INSERT INTO user_notes (recipe_id, note_text) VALUES ($1, $2) RETURNING *',
      [req.params.id, note_text.trim()]
    );
    res.status(201).json(note);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

app.delete('/api/recipes/:recipeId/notes/:noteId', async (req, res) => {
  try {
    await pool.query(
      'DELETE FROM user_notes WHERE id = $1 AND recipe_id = $2',
      [req.params.noteId, req.params.recipeId]
    );
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

// ─── Shared helper ────────────────────────────────────────────────────────────

async function insertIngredientsAndSteps(client, recipeId, ingredients, steps) {
  if (ingredients?.length) {
    for (const ing of ingredients) {
      const { rows: [row] } = await client.query(
        `INSERT INTO ingredients (name)
         VALUES ($1)
         ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
         RETURNING id`,
        [ing.name]
      );
      await client.query(
        `INSERT INTO recipe_ingredients (recipe_id, ingredient_id, amount, unit, note)
         VALUES ($1, $2, $3, $4, $5)`,
        [recipeId, row.id, ing.amount ?? null, ing.unit ?? null, ing.note ?? null]
      );
    }
  }

  if (steps?.length) {
    for (let i = 0; i < steps.length; i++) {
      const s = steps[i];
      await client.query(
        `INSERT INTO steps (recipe_id, step_order, title, text, image_url, timer_seconds)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [recipeId, i + 1, s.title ?? null, s.text, s.image_url ?? null, s.timer_seconds ?? null]
      );
    }
  }
}

// ─── Start ────────────────────────────────────────────────────────────────────

initDB()
  .then(() => app.listen(PORT, () => console.log(`Listening on ${PORT}`)))
  .catch((err) => {
    console.error('DB init failed:', err);
    process.exit(1);
  });
