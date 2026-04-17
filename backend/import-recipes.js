// Usage: node import-recipes.js --password YOUR_ADMIN_PASSWORD
// Or:    ADMIN_PASSWORD=xxx node import-recipes.js

const fs    = require('fs');
const path  = require('path');
const fetch = require('node-fetch');

const API      = 'https://tts-proxy-production-675e.up.railway.app';
const MD_FILE  = path.join(__dirname, '..', 'ספר מתכונים 2026 לבלוג.md');
const ADMIN_PW = process.env.ADMIN_PASSWORD || process.argv[process.argv.indexOf('--password') + 1];

if (!ADMIN_PW || ADMIN_PW === 'undefined') {
  console.error('Usage: node import-recipes.js --password YOUR_ADMIN_PASSWORD');
  process.exit(1);
}

// ── Category inference ────────────────────────────────────────────────────────

function inferCategory(title) {
  const t = title;
  if (/מרק/.test(t))                              return 'מרקים';
  if (/עוגת|מאפינס|עוגיות|קרם ברולה|פנקייק/.test(t)) return 'קינוחים';
  if (/צ['׳]יפס|נאגטס/.test(t))                  return 'חטיפים';
  if (/ניוקי|רביולי|וונטון|כיסוני|פסטה/.test(t)) return 'עיקריות';
  return 'אפייה';
}

function inferDifficulty(ingredients, steps) {
  const n = ingredients.length + steps.length;
  if (n <= 10) return 'easy';
  if (n <= 18) return 'medium';
  return 'hard';
}

function inferTags(title, ingredients) {
  const tags = [];
  const t = title + ' ' + ingredients.map(i => i.name).join(' ');
  if (/שוקולד/.test(t))    tags.push('שוקולד');
  if (/שרימפס/.test(t))    tags.push('פירות ים');
  if (/עוף|פרגית/.test(t)) tags.push('עוף');
  if (/בצק|לחם|קמח/.test(t)) tags.push('אפייה');
  if (/מחמצת/.test(t))     tags.push('מחמצת');
  if (/שמרים/.test(t))     tags.push('שמרים');
  if (/ביצים|חלמון|חלבון/.test(t)) tags.push('ביצים');
  if (/טבעוני|טבעי/.test(t)) tags.push('טבעוני');
  return [...new Set(tags)].slice(0, 5);
}

// ── Ingredient parser ─────────────────────────────────────────────────────────

function parseIngredient(raw) {
  // Strip markdown bold, leading *, trailing spaces
  const cleaned = raw.replace(/\*\*/g, '').replace(/\\-/g, '-').trim();
  if (!cleaned || cleaned.length < 2) return null;

  // Find last colon (ingredient name may contain parens)
  const colonIdx = cleaned.lastIndexOf(':');

  if (colonIdx === -1) {
    // No colon — name only, possibly with (optional) note
    const noteMatch = cleaned.match(/^(.+?)\s*\(([^)]+)\)\s*$/);
    if (noteMatch) return { name: noteMatch[1].trim(), amount: null, unit: null, note: noteMatch[2].trim() };
    return { name: cleaned, amount: null, unit: null, note: null };
  }

  const name = cleaned.slice(0, colonIdx).trim();
  const rest = cleaned.slice(colonIdx + 1).trim();

  // "לפי הצורך" / "לפי הטעם" / empty
  if (!rest || /^(לפי|קמצוץ|קורט)/.test(rest)) {
    return { name, amount: null, unit: null, note: rest || null };
  }

  // Try to extract leading number (int, float, fraction, range)
  const numRe = /^([\d]+(?:[.,][\d]+)?(?:\/[\d]+)?(?:–[\d]+(?:[.,][\d]+)?)?)\s*(.*)/;
  const m = rest.match(numRe);
  if (m) {
    let amtStr = m[1];
    const unit  = m[2].split(/\s*\(/)[0].trim(); // strip trailing note like (120 גרם)
    const note  = m[2].includes('(') ? m[2].match(/\(([^)]+)\)/)?.[1] || null : null;

    // Fraction
    if (amtStr.includes('/')) {
      const [num, den] = amtStr.split('/').map(Number);
      return { name, amount: num / den, unit, note };
    }
    // Range — take lower bound
    if (amtStr.includes('–')) amtStr = amtStr.split('–')[0];
    const amount = parseFloat(amtStr.replace(',', '.'));
    return { name, amount: isNaN(amount) ? null : amount, unit, note };
  }

  // Couldn't parse amount — treat whole rest as note
  return { name, amount: null, unit: null, note: rest };
}

// ── MD parser ─────────────────────────────────────────────────────────────────

function parseRecipes(content) {
  const isSectionHeader = l =>
    /^#+\s+\*\*?(מצרכים|אופן ההכנה|טיפים)/.test(l) || /^##\s+/.test(l);

  const isTitleLine = l => /^#\s+\S/.test(l) && !isSectionHeader(l);

  const lines = content.split('\n');
  const recipes = [];
  let cur = null;
  let section = null;

  for (const rawLine of lines) {
    const line = rawLine.trim();

    // Skip empty
    if (!line) continue;

    // Section headers
    if (/^#+\s+\*\*?(מצרכים)/.test(line))      { section = 'ingredients'; continue; }
    if (/^#+\s+\*\*?(אופן ההכנה)/.test(line))   { section = 'steps';       continue; }
    if (/^#+\s+\*\*?(טיפים)/.test(line))         { section = 'tips';        continue; }
    if (/^##\s+/.test(line))                      { continue; } // sub-section label

    // Recipe title
    if (isTitleLine(line)) {
      const title = line.replace(/^#+\s+/, '').replace(/\\/g, '').trim();
      if (!title) continue;
      if (cur) recipes.push(cur);
      cur = { title, ingredients: [], steps: [], tips: [] };
      section = null;
      continue;
    }

    if (!cur) continue;

    if (section === 'ingredients' && line.startsWith('*')) {
      const ing = parseIngredient(line.slice(1).trim());
      if (ing && ing.name) cur.ingredients.push(ing);

    } else if (section === 'steps' && /^\d+\./.test(line)) {
      const text = line.replace(/^\d+\.\s*/, '').replace(/\\/g, '').trim();
      if (text) cur.steps.push({ text });

    } else if (section === 'tips') {
      const text = line.replace(/^[\*\d\.]+\s*/, '').replace(/\\/g, '').trim();
      if (text) cur.tips.push(text);
    }
  }

  if (cur) recipes.push(cur);

  return recipes.filter(r => r.title && r.steps.length > 0);
}

// ── Build API payload ─────────────────────────────────────────────────────────

function deduplicateNames(ingredients) {
  const seen = {};
  return ingredients.map(ing => {
    if (!seen[ing.name]) { seen[ing.name] = 1; return ing; }
    seen[ing.name]++;
    return { ...ing, name: `${ing.name} (${seen[ing.name]})` };
  });
}

function buildPayload(parsed) {
  const steps = parsed.steps.map((s, i) => ({
    title: null,
    text:  s.text,
    timer_seconds: null,
    image_url: null,
  }));

  // Append tips as a final step if they exist
  if (parsed.tips.length > 0) {
    steps.push({
      title: 'טיפים',
      text:  parsed.tips.join(' • '),
      timer_seconds: null,
      image_url: null,
    });
  }

  return {
    title:       parsed.title,
    description: null,
    difficulty:  inferDifficulty(parsed.ingredients, parsed.steps),
    prep_time:   null,
    cook_time:   null,
    servings:    null,
    category:    inferCategory(parsed.title),
    tags:        inferTags(parsed.title, parsed.ingredients),
    image_url:   null,
    ingredients: deduplicateNames(parsed.ingredients),
    steps,
  };
}

// ── Import ────────────────────────────────────────────────────────────────────

async function importRecipe(payload) {
  const res = await fetch(`${API}/api/recipes`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json', 'x-admin-password': ADMIN_PW },
    body:    JSON.stringify(payload),
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`${res.status} — ${err}`);
  }
  return res.json();
}

async function getExistingTitles() {
  const res = await fetch(`${API}/api/recipes`);
  const list = await res.json();
  return new Set(list.map(r => r.title));
}

// ── Main ──────────────────────────────────────────────────────────────────────

(async () => {
  console.log(`Reading: ${MD_FILE}`);
  const content  = fs.readFileSync(MD_FILE, 'utf8');
  const parsed   = parseRecipes(content);
  console.log(`Parsed ${parsed.length} recipes from MD\n`);

  console.log('Checking existing recipes in DB...');
  const existing = await getExistingTitles();

  let imported = 0, skipped = 0, failed = 0;

  for (const r of parsed) {
    if (existing.has(r.title)) {
      console.log(`  ⚪ SKIP   ${r.title}`);
      skipped++;
      continue;
    }

    const payload = buildPayload(r);

    try {
      const created = await importRecipe(payload);
      console.log(`  ✅ IMPORT #${created.id} — ${r.title}  [${payload.category} | ${payload.difficulty} | ${r.ingredients.length} מרכיבים | ${payload.steps.length} שלבים]`);
      imported++;
    } catch (err) {
      console.error(`  ❌ FAIL   ${r.title} — ${err.message}`);
      failed++;
    }

    // Small delay to avoid hammering the API
    await new Promise(r => setTimeout(r, 200));
  }

  console.log(`\nסיכום: ${imported} יובאו | ${skipped} קיימים | ${failed} נכשלו`);
})();
