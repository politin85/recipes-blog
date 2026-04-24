if (process.env.NODE_ENV !== 'production') require('dotenv').config({ path: '../.env' });
const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });

const AMOUNT_RE = /\s*\(\s*[\d.,½¼¾⅓⅔]+\s*[-–]?\s*[\d.,½¼¾⅓⅔]*\s*(?:גרם|מ״ל|מ"ל|מל|כף|כפיות?|כפות|ק״ג|ק"ג|ליטר|יחידות?|יח׳|יח'|ס"מ|°C|מעלות|ג׳|ג'|כוס|כוסות|קורט|לפי הטעם|לפי הצורך)\s*\)/gi;

function removeDoubleParens(text) {
  // Remove two consecutive parentheticals that contain numbers + units (keep the first)
  return text.replace(
    /(\(\s*[\d.,½¼¾⅓⅔]+[^)]*\))\s*(\(\s*[\d.,½¼¾⅓⅔]+[^)]*\))/g,
    (match, first) => first
  );
}

function cleanText(text) {
  let t = text.replace(AMOUNT_RE, '').replace(/\s{2,}/g, ' ').trim();
  t = removeDoubleParens(t);
  t = t.replace(/\s{2,}/g, ' ').trim();
  return t;
}

async function cleanAllSteps() {
  const { rows: steps } = await pool.query('SELECT id, text FROM steps ORDER BY id');
  let updated = 0;
  for (const step of steps) {
    const cleaned = cleanText(step.text);
    if (cleaned !== step.text) {
      await pool.query('UPDATE steps SET text = $1 WHERE id = $2', [cleaned, step.id]);
      console.log(`Updated step ${step.id}:\n  BEFORE: ${step.text.slice(0, 80)}\n  AFTER:  ${cleaned.slice(0, 80)}\n`);
      updated++;
    }
  }
  console.log(`Done. Updated ${updated} / ${steps.length} steps.`);
  await pool.end();
}

cleanAllSteps().catch(err => { console.error(err); process.exit(1); });
