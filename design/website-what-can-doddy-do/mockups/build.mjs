// Assembles the mockup pages from src/*.html and src/partials/*.html.
//   node build.mjs
// A page starts with an HTML comment of "key: value" lines (title, active, nav).
// {{> name}} inserts src/partials/name.html; {{active:key}} prints aria-current="page"
// when the page's "active" is that key; {{title}} prints the page title.
import fs from 'node:fs';
import path from 'node:path';

const here = path.dirname(new URL(import.meta.url).pathname);
const srcDir = path.join(here, 'src');
const partialsDir = path.join(srcDir, 'partials');

const partials = Object.fromEntries(
  fs.readdirSync(partialsDir).filter((f) => f.endsWith('.html'))
    .map((f) => [f.replace(/\.html$/, ''), fs.readFileSync(path.join(partialsDir, f), 'utf8')]),
);

function render(source, vars) {
  let out = source;
  for (let i = 0; i < 5; i += 1) { // partials may include partials
    out = out.replace(/\{\{>\s*([\w-]+)\s*\}\}/g, (_, name) => {
      if (!(name in partials)) throw new Error(`unknown partial ${name}`);
      return partials[name];
    });
  }
  out = out.replace(/\{\{active:([\w-]+)\}\}/g, (_, key) => (vars.active === key ? ' aria-current="page"' : ''));
  out = out.replace(/\{\{menu\}\}/g, vars.nav === 'open' ? ' is-open' : '');
  out = out.replace(/\{\{title\}\}/g, vars.title || 'Doddy');
  return out;
}

for (const file of fs.readdirSync(srcDir).filter((f) => f.endsWith('.html'))) {
  const source = fs.readFileSync(path.join(srcDir, file), 'utf8');
  const head = source.match(/^<!--([\s\S]*?)-->/);
  const vars = {};
  if (head) {
    for (const line of head[1].trim().split('\n')) {
      const m = line.match(/^\s*([\w-]+):\s*(.*)$/);
      if (m) vars[m[1]] = m[2].trim();
    }
  }
  const body = head ? source.slice(head[0].length).replace(/^\s+/, '') : source;
  fs.writeFileSync(path.join(here, file), render(body, vars));
  console.log('built', file);
}
