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

    CREATE TABLE IF NOT EXISTS site_settings (
      key   TEXT PRIMARY KEY,
      value TEXT
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
    ALTER TABLE steps   ADD COLUMN IF NOT EXISTS prep_minutes      INTEGER DEFAULT 0;
    ALTER TABLE steps   ADD COLUMN IF NOT EXISTS cook_minutes      INTEGER DEFAULT 0;
    ALTER TABLE steps   ADD COLUMN IF NOT EXISTS show_timer        BOOLEAN DEFAULT true;
    ALTER TABLE steps   ADD COLUMN IF NOT EXISTS show_prep_timer   BOOLEAN DEFAULT true;
    ALTER TABLE steps   ADD COLUMN IF NOT EXISTS show_cook_timer   BOOLEAN DEFAULT true;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS ingredient_aliases (
      id            SERIAL PRIMARY KEY,
      original_name TEXT NOT NULL,
      display_name  TEXT NOT NULL CHECK (display_name <> ''),
      note          TEXT NOT NULL DEFAULT '',
      updated_at    TIMESTAMP DEFAULT NOW()
    );
    ALTER TABLE ingredient_aliases ADD COLUMN IF NOT EXISTS note TEXT DEFAULT '';
    UPDATE ingredient_aliases SET note = '' WHERE note IS NULL;
    ALTER TABLE ingredient_aliases ALTER COLUMN note SET NOT NULL;
    ALTER TABLE ingredient_aliases ALTER COLUMN note SET DEFAULT '';
    ALTER TABLE ingredient_aliases DROP CONSTRAINT IF EXISTS ingredient_aliases_original_name_key;
    CREATE UNIQUE INDEX IF NOT EXISTS ingredient_aliases_name_note_idx
      ON ingredient_aliases (original_name, note);
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
      `SELECT i.*, COALESCE(a.display_name, i.name) AS display_name,
              COUNT(DISTINCT ri.recipe_id)::int AS recipe_count
       FROM ingredients i
       LEFT JOIN ingredient_aliases a ON a.original_name = i.name
       LEFT JOIN recipe_ingredients ri ON ri.ingredient_id = i.id
       GROUP BY i.id, a.display_name
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
      // Expand each selected ingredient to all DB ingredients whose name starts with it.
      // matched_count = how many of the ORIGINAL selections had at least one expanded match.
      const { rows } = await pool.query(
        `WITH sel_exp AS (
           SELECT sel.id AS sel_id, exp.id AS exp_id
           FROM   ingredients sel
           JOIN   ingredients exp ON exp.name ILIKE sel.name || '%'
           WHERE  sel.id = ANY($1::int[])
         )
         SELECT r.*,
           COUNT(DISTINCT se.sel_id)::int AS matched_count
         FROM   recipes r
         JOIN   recipe_ingredients ri ON ri.recipe_id = r.id
         JOIN   sel_exp se            ON se.exp_id    = ri.ingredient_id
         WHERE  r.is_hidden IS NOT TRUE
         GROUP  BY r.id
         ORDER  BY matched_count DESC, r.created_at DESC`,
        [ingredient_ids]
      );
      return res.json(rows);
    }

    // % match mode — expand ingredient_ids via prefix first, then existing coverage logic
    const { rows: expRows } = await pool.query(
      `SELECT DISTINCT exp.id
       FROM   ingredients sel
       JOIN   ingredients exp ON exp.name ILIKE sel.name || '%'
       WHERE  sel.id = ANY($1::int[])`,
      [ingredient_ids]
    );
    const expandedIds = expRows.map(r => r.id);
    if (!expandedIds.length) return res.json([]);

    let available;
    if (include_pantry) {
      const { rows: staples } = await pool.query(
        'SELECT id FROM ingredients WHERE is_pantry_staple = TRUE'
      );
      available = [...new Set([...expandedIds, ...staples.map(r => r.id)])];
    } else {
      available = [...new Set(expandedIds)];
    }

    const { rows: recipes } = await pool.query(
      `SELECT
         r.*,
         COUNT(DISTINCT ri.ingredient_id)::int AS total_ingredients,
         COUNT(DISTINCT ri.ingredient_id)
           FILTER (WHERE ri.ingredient_id = ANY($1::int[]))::int AS matched_selected,
         COUNT(DISTINCT ri.ingredient_id)
           FILTER (WHERE ri.ingredient_id = ANY($2::int[]))::int AS matched_available
       FROM   recipes r
       JOIN   recipe_ingredients ri ON ri.recipe_id = r.id
       WHERE  r.is_hidden IS NOT TRUE
       GROUP  BY r.id
       HAVING COUNT(DISTINCT ri.ingredient_id)
                FILTER (WHERE ri.ingredient_id = ANY($1::int[])) > 0`,
      [expandedIds, available]
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
             FROM   recipe_ingredients ri
             JOIN   ingredients i ON i.id = ri.ingredient_id
             WHERE  ri.recipe_id = $1
               AND  ri.ingredient_id != ALL($2::int[])`,
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

  const pSteps = processSteps(steps);
  const auto   = calcAutoTimes(pSteps);
  const fPrep  = prep_time  != null ? prep_time  : auto.prep_time;
  const fCook  = cook_time  != null ? cook_time  : auto.cook_time;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows: [recipe] } = await client.query(
      `INSERT INTO recipes
         (title, description, difficulty, prep_time, cook_time, servings, category, tags, image_url, is_hidden, story_text)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
       RETURNING *`,
      [title, description, difficulty, fPrep, fCook, servings, category, tags ?? [], image_url, is_hidden ?? false, story_text ?? null]
    );

    await insertIngredientsAndSteps(client, recipe.id, ingredients, pSteps);

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
          `SELECT i.id, i.name, COALESCE(a.display_name, i.name) AS display_name,
                  i.is_pantry_staple, ri.amount, ri.unit, ri.note
           FROM recipe_ingredients ri
           JOIN ingredients i ON i.id = ri.ingredient_id
           LEFT JOIN ingredient_aliases a
             ON a.original_name = i.name AND a.note = COALESCE(ri.note, '')
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

  const pSteps = processSteps(steps);
  const auto   = calcAutoTimes(pSteps);
  const fPrep  = prep_time  != null ? prep_time  : auto.prep_time;
  const fCook  = cook_time  != null ? cook_time  : auto.cook_time;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows: [recipe] } = await client.query(
      `UPDATE recipes
       SET title=$1, description=$2, difficulty=$3, prep_time=$4, cook_time=$5,
           servings=$6, category=$7, tags=$8, image_url=$9, is_hidden=$10, story_text=$11
       WHERE id=$12 RETURNING *`,
      [title, description, difficulty, fPrep, fCook, servings, category, tags ?? [], image_url, is_hidden ?? false, story_text ?? null, id]
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
    await insertIngredientsAndSteps(client, id, ingredients, pSteps);

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

app.patch('/api/recipes/:id', requireAdmin, async (req, res) => {
  const allowed = ['is_hidden'];
  const sets = [], vals = [];
  let p = 1;
  for (const key of allowed) {
    if (req.body[key] !== undefined) { sets.push(`${key} = $${p++}`); vals.push(req.body[key]); }
  }
  if (!sets.length) return res.status(400).json({ error: 'Nothing to update' });
  vals.push(req.params.id);
  try {
    const { rows: [recipe] } = await pool.query(
      `UPDATE recipes SET ${sets.join(', ')} WHERE id = $${p} RETURNING *`, vals
    );
    if (!recipe) return res.status(404).json({ error: 'Not found' });
    res.json(recipe);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
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

// ─── Ingredient aliases (admin) ───────────────────────────────────────────────

app.get('/api/admin/ingredients/all', requireAdmin, async (req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT
         i.name AS original_name,
         ri.note,
         COALESCE(ia.display_name, i.name) AS display_name,
         COUNT(DISTINCT ri.recipe_id)::int AS recipe_count
       FROM recipe_ingredients ri
       JOIN ingredients i ON i.id = ri.ingredient_id
       LEFT JOIN ingredient_aliases ia
         ON ia.original_name = i.name
         AND (ia.note = ri.note
              OR (ia.note = '' AND (ri.note IS NULL OR ri.note = '')))
       GROUP BY i.name, ri.note, ia.display_name
       ORDER BY i.name ASC, ri.note ASC NULLS FIRST`
    );
    console.log('[ingredients/all] rows:', rows.length, JSON.stringify(rows.slice(0, 3)));
    res.json(rows);
  } catch (err) {
    console.error('[ingredients/all] error:', err);
    res.status(500).json({ error: 'DB error' });
  }
});

app.put('/api/admin/ingredients/alias', requireAdmin, async (req, res) => {
  const { original_name, display_name, note, new_note } = req.body;
  if (!original_name) return res.status(400).json({ error: 'original_name required' });
  const effectiveName    = display_name?.trim() || original_name;
  const effectiveNote    = note?.trim() ?? '';
  const effectiveNewNote = new_note !== undefined ? (new_note?.trim() ?? '') : effectiveNote;
  try {
    if (effectiveNewNote !== effectiveNote) {
      await pool.query(
        `DELETE FROM ingredient_aliases WHERE original_name = $1 AND note = $2`,
        [original_name, effectiveNote]
      );
    }
    await pool.query(
      `INSERT INTO ingredient_aliases (original_name, display_name, note)
       VALUES ($1, $2, $3)
       ON CONFLICT (original_name, note) DO UPDATE
         SET display_name = EXCLUDED.display_name,
             updated_at   = NOW()`,
      [original_name, effectiveName, effectiveNewNote]
    );
    console.log('[alias PUT] saved:', original_name, '->', effectiveName, 'note:', effectiveNewNote);
    res.json({ original_name, display_name: effectiveName, note: effectiveNewNote });
  } catch (err) {
    console.error('[alias PUT] error:', err);
    res.status(500).json({ error: 'DB error' });
  }
});

app.post('/api/admin/ingredients/suggest-aliases', requireAdmin, async (req, res) => {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return res.status(503).json({ error: 'ANTHROPIC_API_KEY לא מוגדר ב-Railway Variables' });

  try {
    // Only suggest for ingredients without a manual alias yet
    const { rows } = await pool.query(
      `SELECT i.name FROM ingredients i
       LEFT JOIN ingredient_aliases a ON a.original_name = i.name
       WHERE a.original_name IS NULL
       ORDER BY i.name`
    );
    if (!rows.length) return res.json({ saved: 0, suggestions: [] });

    const names = rows.map(r => r.name).join('\n');
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 4096,
        messages: [{
          role: 'user',
          content: `קבץ מצרכים דומים בעברית והצע שם תצוגה אחד לכל קבוצה. למשל: שמרים / שמרים יבשים / שמרים אינסטנט → שמרים יבשים מיידיים. אם מצרך ייחודי — השאר את שמו כפי שהוא. החזר JSON בלבד, ללא הסבר, ללא markdown:\n[{"original_name": "...", "display_name": "..."}]\n\nרשימת מצרכים:\n${names}`,
        }],
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      return res.status(502).json({ error: `Claude API: ${errText}` });
    }

    const data = await response.json();
    const text = data.content[0].text.trim();
    const jsonMatch = text.match(/\[[\s\S]*\]/);
    if (!jsonMatch) return res.status(502).json({ error: 'Invalid Claude response format' });

    const suggestions = JSON.parse(jsonMatch[0]);
    let saved = 0;
    for (const s of suggestions) {
      if (!s.original_name || !s.display_name) continue;
      await pool.query(
        `INSERT INTO ingredient_aliases (original_name, display_name)
         VALUES ($1, $2)
         ON CONFLICT (original_name) DO NOTHING`,
        [s.original_name, s.display_name]
      );
      saved++;
    }
    res.json({ saved, suggestions });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// ─── Site settings ────────────────────────────────────────────────────────────

app.get('/api/settings', async (req, res) => {
  try {
    const { rows } = await pool.query('SELECT key, value FROM site_settings');
    const settings = Object.fromEntries(rows.map(r => [r.key, r.value]));
    res.json(settings);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

app.put('/api/settings', requireAdmin, async (req, res) => {
  const allowed = ['site_name', 'hero_title', 'site_description', 'hero_image', 'hero_image_url'];
  const entries = Object.entries(req.body).filter(([k]) => allowed.includes(k));
  if (!entries.length) return res.status(400).json({ error: 'No valid keys' });

  try {
    for (const [key, value] of entries) {
      await pool.query(
        `INSERT INTO site_settings (key, value) VALUES ($1, $2)
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
        [key, value]
      );
    }
    const { rows } = await pool.query('SELECT key, value FROM site_settings');
    res.json(Object.fromEntries(rows.map(r => [r.key, r.value])));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

// ─── Batch step operations (admin) ───────────────────────────────────────────

app.post('/api/admin/steps/generate-titles', requireAdmin, async (req, res) => {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return res.status(503).json({ error: 'ANTHROPIC_API_KEY לא מוגדר ב-Railway Variables' });

  const { recipe_id } = req.body;
  try {
    const where = recipe_id ? 'WHERE s.recipe_id = $1 AND' : 'WHERE';
    const params = recipe_id ? [recipe_id] : [];
    const { rows: steps } = await pool.query(
      `SELECT s.id, s.text FROM steps s
       ${where} (s.title IS NULL OR s.title = '')
       ORDER BY s.recipe_id, s.step_order`,
      params
    );
    if (!steps.length) return res.json({ updated: 0 });

    let updated = 0;
    for (const step of steps) {
      try {
        const resp = await fetch('https://api.anthropic.com/v1/messages', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'x-api-key': apiKey, 'anthropic-version': '2023-06-01' },
          body: JSON.stringify({
            model: 'claude-haiku-4-5-20251001',
            max_tokens: 64,
            messages: [{ role: 'user', content: `כתוב כותרת קצרה (3-5 מילים) בעברית לשלב ההכנה הבא. החזר רק את הכותרת, ללא סימני פיסוק מיוחדים:\n${step.text.slice(0, 300)}` }],
          }),
        });
        if (!resp.ok) continue;
        const data = await resp.json();
        const title = data.content[0].text.trim().replace(/^["״]|["״]$/g, '');
        await pool.query('UPDATE steps SET title = $1 WHERE id = $2', [title, step.id]);
        updated++;
      } catch {}
    }
    res.json({ updated });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

app.post('/api/admin/steps/sync-ingredient-names', requireAdmin, async (req, res) => {
  const { recipe_id } = req.body;
  try {
    const { rows: aliases } = await pool.query(
      `SELECT original_name, display_name FROM ingredient_aliases
       WHERE original_name <> display_name`
    );
    if (!aliases.length) return res.json({ updated: 0 });

    const where = recipe_id ? 'WHERE recipe_id = $1' : '';
    const params = recipe_id ? [recipe_id] : [];
    const { rows: steps } = await pool.query(`SELECT id, text FROM steps ${where}`, params);

    let updated = 0;
    for (const step of steps) {
      let newText = step.text;
      for (const { original_name, display_name } of aliases) {
        if (newText.includes(original_name)) {
          newText = newText.split(original_name).join(display_name);
        }
      }
      if (newText !== step.text) {
        await pool.query('UPDATE steps SET text = $1 WHERE id = $2', [newText, step.id]);
        updated++;
      }
    }
    res.json({ updated });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

// Strips ALL parenthetical amounts from step text (used before dynamic re-insertion by frontend)
const AMOUNT_UNITS = 'גרם|מ״ל|מ"ל|מ\'ל|כף|כפות|כפית|כפיות|ק״ג|ק"ג|ליטר|יחידות?|יח׳|יח\'|ס"מ|°C|מעלות|ג׳|ג\'|מל|כוס|כוסות|מ"מ';
const AMOUNT_RE = new RegExp(
  '\\s*\\([^)]*(?:' + AMOUNT_UNITS + ')[^)]*\\)',
  'gi'
);

function stripAmountsFromText(text) {
  return text.replace(AMOUNT_RE, '').replace(/\s{2,}/g, ' ').trim();
}

// Legacy dedup helper kept for /clean-duplicates endpoint
function cleanDuplicateAmounts(text) {
  return text
    .replace(/(\([^)]*(?:גרם|מ״ל|מ"ל|כף|כפית|ק״ג|ק"ג|ליטר|יחידות?|ס"מ|°C|מעלות|מ"מ)[^)]*\))\s*\1+/g, '$1')
    .replace(/(\(\d+[^)]*\))\s*\1+/g, '$1')
    .replace(/\s{2,}/g, ' ')
    .trim();
}

app.post('/api/admin/recipes/:id/clean-duplicates', requireAdmin, async (req, res) => {
  const recipeId = parseInt(req.params.id);
  try {
    const { rows: steps } = await pool.query(
      'SELECT id, text FROM steps WHERE recipe_id = $1', [recipeId]
    );
    let updated = 0;
    for (const step of steps) {
      const newText = cleanDuplicateAmounts(step.text);
      if (newText !== step.text) {
        await pool.query('UPDATE steps SET text = $1 WHERE id = $2', [newText, step.id]);
        updated++;
      }
    }
    res.json({ updated });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

app.post('/api/admin/steps/clean-all-duplicates', requireAdmin, async (req, res) => {
  try {
    const { rows: steps } = await pool.query('SELECT id, text FROM steps');
    let updated = 0;
    for (const step of steps) {
      const newText = cleanDuplicateAmounts(step.text);
      if (newText !== step.text) {
        await pool.query('UPDATE steps SET text = $1 WHERE id = $2', [newText, step.id]);
        updated++;
      }
    }
    res.json({ updated });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

app.post('/api/admin/steps/strip-amounts', requireAdmin, async (req, res) => {
  try {
    const { rows: steps } = await pool.query(
      'SELECT s.id, s.text, s.recipe_id, s.step_order, r.title AS recipe_title FROM steps s JOIN recipes r ON r.id = s.recipe_id'
    );
    let updated = 0;
    const remaining = [];
    const checkRe = new RegExp('\\([^)]*(?:' + AMOUNT_UNITS + ')[^)]*\\)', 'i');

    for (const step of steps) {
      const newText = stripAmountsFromText(step.text);
      if (newText !== step.text) {
        await pool.query('UPDATE steps SET text = $1 WHERE id = $2', [newText, step.id]);
        updated++;
        console.log(`[strip-amounts] step ${step.id} (${step.recipe_title} #${step.step_order}): updated`);
      }
      if (checkRe.test(newText)) {
        remaining.push({ id: step.id, recipe_title: step.recipe_title, step_order: step.step_order, text: newText });
        console.warn(`[strip-amounts] step ${step.id} still has amount pattern: ${newText}`);
      }
    }
    res.json({ updated, remaining_count: remaining.length, remaining });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'DB error' });
  }
});

// ─── Timer helpers ────────────────────────────────────────────────────────────

function parseTimerFromText(text) {
  if (!text) return null;
  if (/חצי\s*שעה/.test(text)) return 1800;
  if (/רבע\s*שעה/.test(text)) return 900;
  let m = text.match(/(\d+)\s*[-–]\s*(\d+)\s*דק/);
  if (m) return Math.round((+m[1] + +m[2]) / 2) * 60;
  m = text.match(/(\d+)\s*[-–]\s*(\d+)\s*שע/);
  if (m) return Math.round((+m[1] + +m[2]) / 2) * 3600;
  m = text.match(/(?:כ[-\s]?)?(\d+(?:\.\d+)?)\s*(?:דקות|דקה|דק[׳'"ׇ]?)\b/);
  if (m) return Math.round(parseFloat(m[1]) * 60);
  m = text.match(/(?:כ[-\s]?)?(\d+(?:\.\d+)?)\s*(?:שעות|שעה)\b/);
  if (m) return Math.round(parseFloat(m[1]) * 3600);
  return null;
}

function isCookingStep(text) {
  return /אפ[יה]|תנור|טג[ונ]|מטגן|טיגון|בש[לו]|בישול|מבשל|צל[יה]|קל[הוי]|הרתח|בסיר|איד[וא]|מאד[הי]|גריל|מחב[תי]|פרייר/.test(text);
}

function processSteps(steps) {
  if (!steps?.length) return steps || [];
  return steps.map(s => ({
    ...s,
    timer_seconds: s.timer_seconds ?? parseTimerFromText(s.text || '') ?? null,
    prep_minutes:     s.prep_minutes     ?? 0,
    cook_minutes:     s.cook_minutes     ?? 0,
    show_timer:       s.show_timer       !== false,
    show_prep_timer:  s.show_prep_timer  !== false,
    show_cook_timer:  s.show_cook_timer  !== false,
  }));
}

function calcAutoTimes(steps) {
  let prepMin = 0, cookMin = 0;
  for (const s of steps || []) {
    prepMin += s.prep_minutes || 0;
    cookMin += s.cook_minutes || 0;
  }
  // Fallback to timer-based heuristic for recipes without explicit per-step times
  if (prepMin === 0 && cookMin === 0) {
    let prepSec = 0, cookSec = 0;
    for (const s of steps || []) {
      if (!s.timer_seconds) continue;
      const ctx = (s.title || '') + ' ' + (s.text || '');
      if (isCookingStep(ctx)) cookSec += s.timer_seconds;
      else prepSec += s.timer_seconds;
    }
    return {
      prep_time: prepSec > 0 ? Math.round(prepSec / 60) : null,
      cook_time: cookSec > 0 ? Math.round(cookSec / 60) : null,
    };
  }
  return {
    prep_time: prepMin > 0 ? prepMin : null,
    cook_time: cookMin > 0 ? cookMin : null,
  };
}

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
        `INSERT INTO steps (recipe_id, step_order, title, text, image_url, timer_seconds, prep_minutes, cook_minutes, show_timer, show_prep_timer, show_cook_timer)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
        [recipeId, i + 1, s.title ?? null, s.text, s.image_url ?? null, s.timer_seconds ?? null,
         s.prep_minutes ?? 0, s.cook_minutes ?? 0, s.show_timer !== false,
         s.show_prep_timer !== false, s.show_cook_timer !== false]
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
