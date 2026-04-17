// Run once to seed the graham crackers recipe:  node seed.js
if (process.env.NODE_ENV !== 'production') {
  require('dotenv').config();
}

const { Pool } = require('pg');
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

const recipe = {
  title: 'גרהם קרקרס ביתיים',
  description: 'ביסקוויטים פריכים מקמח מלא עם טעם עדין של דבש וקינמון. מושלמים כחטיף, לבסיס עוגת גבינה, או עם שכבת שוקולד.',
  difficulty: 'easy',
  prep_time: 10,
  cook_time: 12,
  servings: 24,
  category: 'אפייה',
  tags: ['ביסקוויטים', 'אפייה', 'קמח מלא', 'חטיפים', 'טבעוני'],
  image_url: null,
};

const ingredients = [
  { name: 'קמח מלא', amount: 240, unit: 'גרם', note: null },
  { name: 'סוכר חום', amount: 50, unit: 'גרם', note: null },
  { name: 'קינמון', amount: 1, unit: 'כפית', note: null },
  { name: 'סודה לשתייה', amount: 0.5, unit: 'כפית', note: null },
  { name: 'מלח', amount: 0.25, unit: 'כפית', note: null },
  { name: 'חמאה', amount: 85, unit: 'גרם', note: 'קרה, חתוכה לקוביות' },
  { name: 'דבש', amount: 60, unit: 'מ"ל', note: null },
  { name: 'וניל', amount: 1, unit: 'כפית', note: 'תמצית וניל' },
  { name: 'מים', amount: 15, unit: 'מ"ל', note: 'קרים' },
];

const steps = [
  {
    title: 'ערבוב חומרים יבשים',
    text: 'מערבבים בקערה גדולה קמח מלא, סוכר חום, קינמון, סודה לשתייה ומלח עד לתערובת אחידה.',
    timer_seconds: null,
    image_url: null,
  },
  {
    title: 'הוספת החמאה',
    text: 'מוסיפים את קוביות החמאה הקרה לתערובת היבשה. משפשפים את החמאה עם הקמח בין האצבעות עד שמתקבלת תערובת פירורית דמוית חול גס.',
    timer_seconds: null,
    image_url: null,
  },
  {
    title: 'הוספת נוזלים',
    text: 'מערבבים בקערית קטנה דבש, תמצית וניל ומים קרים. יוצקים לתערובת הפירורים ומערבבים עם מזלג רק עד שהבצק מתלכד. אין ללוש יתר על המידה.',
    timer_seconds: null,
    image_url: null,
  },
  {
    title: 'מנוחה במקרר',
    text: 'עוטפים את הבצק בניילון נצמד ומשטחים לדיסק שטוח. מכניסים למקרר לחצי שעה לפחות. ניתן להשאיר לילה שלם.',
    timer_seconds: 1800,
    image_url: null,
  },
  {
    title: 'חימום תנור וקיטוע',
    text: 'מחממים תנור ל-180 מעלות. מרפדים תבנית בנייר אפייה. מוציאים את הבצק מהמקרר ומניחים בין שני ניירות אפייה.',
    timer_seconds: null,
    image_url: null,
  },
  {
    title: 'רידוד וחיתוך',
    text: 'מרדדים את הבצק לעובי 3-4 מ"מ. חותכים למלבנים בגודל 6x9 ס"מ בערך. מעבירים לתבנית המרופדת. דוקרים כל ביסקוויט כמה פעמים עם מזלג לדוגמה אופיינית.',
    timer_seconds: null,
    image_url: null,
  },
  {
    title: 'אפייה',
    text: 'אופים 10-12 דקות עד שהשוליים מזהיבים מעט. הביסקוויטים יתקשו עוד בזמן הצינון, אז אל תחכו שיהיו קשים בתנור.',
    timer_seconds: 660,
    image_url: null,
  },
  {
    title: 'צינון',
    text: 'מוציאים מהתנור ומניחים לצינון מלא על רשת לפחות שעה לפני שנוגעים. לאחר הצינון, שומרים בקופסה אטומה עד שבוע.',
    timer_seconds: 3600,
    image_url: null,
  },
];

async function seed() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Skip if already exists
    const { rows: existing } = await client.query(
      'SELECT id FROM recipes WHERE title = $1', [recipe.title]
    );
    if (existing.length) {
      console.log('Recipe already seeded, skipping.');
      await client.query('ROLLBACK');
      return;
    }

    const { rows: [{ id }] } = await client.query(
      `INSERT INTO recipes
         (title, description, difficulty, prep_time, cook_time, servings, category, tags, image_url)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
       RETURNING id`,
      [recipe.title, recipe.description, recipe.difficulty, recipe.prep_time,
       recipe.cook_time, recipe.servings, recipe.category, recipe.tags, recipe.image_url]
    );

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
         VALUES ($1,$2,$3,$4,$5)`,
        [id, row.id, ing.amount, ing.unit, ing.note]
      );
    }

    for (let i = 0; i < steps.length; i++) {
      const s = steps[i];
      await client.query(
        `INSERT INTO steps (recipe_id, step_order, title, text, image_url, timer_seconds)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [id, i + 1, s.title, s.text, s.image_url, s.timer_seconds]
      );
    }

    await client.query('COMMIT');
    console.log(`Seeded recipe id=${id}: ${recipe.title}`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Seed failed:', err);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

seed();
