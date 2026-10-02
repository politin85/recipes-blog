#!/usr/bin/env node
// Builds RecipesTests/HighlightFixtures.json: the output of the website's own
// step-text functions (lifted verbatim from ../recipe.html) for every live recipe,
// so the Swift port can be checked against the real thing.
// Run from the ios/ directory: node scripts/make_highlight_fixtures.js
const fs = require('fs');
const path = require('path');

const API = 'https://tts-proxy-production-675e.up.railway.app';
const html = fs.readFileSync(path.join(__dirname, '..', '..', 'recipe.html'), 'utf8');

function slice(from, to) {
  const a = html.indexOf(from);
  const b = html.indexOf(to, a);
  if (a < 0 || b < 0) throw new Error(`could not find block: ${from}`);
  return html.slice(a, b);
}

const source = [
  slice('function formatAmount(n)', '// Servings controls'),
  slice('function cleanStepText(text)', 'function renderSteps()'),
  slice('const _AMOUNT_STRIP_RE', 'function toggleStepOpen(sid)'),
].join('\n');

const site = new Function(`
  let recipe, currentServings, baseServings;
  ${source}
  function mentions(ing, text) {
    const variants = [...new Set([ing.display_name, ing.name].filter(Boolean).map(n => n.trim()).filter(Boolean))]
      .sort((a, b) => b.length - a.length)
      .map(v => v.replace(/[.*+?^\${}()|[\\]\\\\]/g, '\\\\$&').replace(/\\s+/g, '\\\\s+'));
    if (!variants.length) return false;
    const re = new RegExp(\`(^|\${_ING_BOUNDARY})(?:\${_ING_PREFIX_ALT})?(?:\${variants.join('|')})\${_ING_SUFFIX}(?=$|\${_ING_BOUNDARY})\`);
    return re.test(text);
  }
  return {
    formatAmount,
    cleanStepText,
    mentions,
    highlight(r, servings, text) {
      recipe = r; baseServings = r.servings || 1; currentServings = servings;
      return highlightIngredients(text);
    },
  };
`)();

(async () => {
  const list = await (await fetch(`${API}/api/recipes`)).json();
  const out = { amounts: [], recipes: [] };

  for (const n of [0, 0.1, 0.124, 0.125, 0.25, 0.3, 0.5, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 2.75, 3, 7.5, 70, 333.3, 1000]) {
    out.amounts.push({ n, text: site.formatAmount(n) });
  }

  for (const row of list) {
    const r = await (await fetch(`${API}/api/recipes/${row.id}`)).json();
    const base = r.servings || 1;
    const fixture = {
      id: r.id,
      servings: r.servings,
      ingredients: r.ingredients.map(({ id, name, display_name, amount, unit, note }) => ({ id, name, display_name, amount, unit, note })),
      steps: [],
    };
    for (const s of r.steps) {
      fixture.steps.push({
        text: s.text,
        cleaned: site.cleanStepText(s.text),
        mentions: r.ingredients.map(ing => site.mentions(ing, s.text || '')),
        cases: [
          { servings: base, html: site.highlight(r, base, s.text) },
          { servings: base * 3, html: site.highlight(r, base * 3, site.cleanStepText(s.text)) },
          { servings: Math.max(1, Math.floor(base / 2)), html: site.highlight(r, Math.max(1, Math.floor(base / 2)), site.cleanStepText(s.text)) },
        ],
      });
    }
    out.recipes.push(fixture);
  }

  const dest = path.join(__dirname, '..', 'RecipesTests', 'HighlightFixtures.json');
  fs.writeFileSync(dest, JSON.stringify(out));
  const steps = out.recipes.reduce((n, r) => n + r.steps.length, 0);
  console.log(`wrote ${out.recipes.length} recipes, ${steps} steps → ${dest}`);
})();
