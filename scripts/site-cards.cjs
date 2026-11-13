// Render the 1200x630 social cards from the SVG illustrations (docs/brand.md › Illustration).
// Needs Playwright with Chromium; commit site/images/cards/ and scripts/cards/manifest.json.
// site-build.py --check compares the manifest hashes, so any art, copy or card change needs a rerun.
const { chromium } = require("playwright");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const file = (name) => "file://" + path.join(root, name);
const posts = fs.readdirSync(path.join(root, "scripts/blog/posts")).filter((name) => name.endsWith(".md")).sort()
  .map((name) => ({ slug: name.slice(0, -3), ...JSON.parse(fs.readFileSync(path.join(root, "scripts/blog/posts", name), "utf8").split("---\n")[1]) }));
const cover = (name) => `scripts/blog/covers/${name}.svg`;
const cards = [
  { name: "home", kicker: "Shared expenses and loans", title: "Good friends. Clear balances.", art: "site/images/art/chai.svg" },
  { name: "blog", kicker: "The SabkiJeb blog", title: "Good friends. Clear stories.", fan: posts.map((post) => cover(post.cover)) },
  ...posts.map((post) => ({ name: post.slug, kicker: post.type, title: post.title, cover: cover(post.cover) })),
  { name: "privacy", kicker: "Privacy policy", title: "What we store, and what stays yours.", art: "scripts/cards/art/privacy.svg" },
  { name: "support", kicker: "Support", title: "Questions? Write to us.", art: "scripts/cards/art/letter.svg" },
  { name: "terms", kicker: "Terms of use", title: "A record-keeping app, not a bank.", art: "scripts/cards/art/terms.svg" },
  { name: "delete-account", kicker: "Delete your account", title: "What is removed, and what remains.", art: "scripts/cards/art/delete.svg" },
];

const panel = (card) => card.cover
  ? `<img class="cover" src="${file(card.cover)}">`
  : card.fan
    ? `<div class="fan">${card.fan.map((name) => `<img src="${file(name)}">`).join("")}</div>`
    : `<img class="spot" src="${file(card.art)}">`;
const page = (card) => `<!doctype html><meta charset="utf-8"><style>
@font-face{font-family:Figtree;font-weight:500;src:url(${file("site/fonts/Figtree-Medium.ttf")})}
@font-face{font-family:Figtree;font-weight:400;src:url(${file("site/fonts/Figtree-Regular.ttf")})}
*{box-sizing:border-box;margin:0}
body{width:1200px;height:630px;overflow:hidden;background:#fbf8ef;color:#18271f;font-family:Figtree;position:relative}
.brand{position:absolute;left:64px;top:56px;display:flex;align-items:center;gap:14px;font-weight:500;font-size:26px;letter-spacing:.08em;text-transform:uppercase}
.brand img{width:44px;height:44px}
.copy{position:absolute;left:64px;top:150px;width:500px;height:350px;display:flex;flex-direction:column;justify-content:center}
.kicker{color:#01672d;font-weight:500;font-size:24px;margin-bottom:20px}
h1{font-weight:500;letter-spacing:-.035em;line-height:1.04;text-wrap:balance}
.url{position:absolute;left:64px;bottom:52px;font-size:22px;color:#50645a}
.panel{position:absolute;right:48px;top:48px;width:540px;height:534px;border-radius:24px;overflow:hidden;background:#fef0ce}
.cover{width:100%;height:100%;object-fit:cover}
.spot{position:absolute;inset:0;margin:auto;width:500px}
.fan{background:#01381e;width:100%;height:100%;position:relative}
.fan img{position:absolute;width:360px;border-radius:12px;box-shadow:8px 10px 0 rgba(0,0,0,.25)}
.fan img:nth-child(1){left:24px;top:52px;transform:rotate(-7deg)}
.fan img:nth-child(2){left:150px;top:180px;transform:rotate(4deg)}
.fan img:nth-child(3){left:96px;top:316px;transform:rotate(-2deg)}
</style><div class="brand"><img src="${file("site/images/mark.png")}">SabkiJeb</div>
<div class="copy"><p class="kicker">${card.kicker}</p><h1>${card.title.replace(/&/g, "&amp;").replace(/</g, "&lt;")}</h1></div>
<p class="url">sabkijeb.app</p><div class="panel">${panel(card)}</div>`;

const sha = (name) => crypto.createHash("sha256").update(fs.readFileSync(path.join(root, name))).digest("hex");

(async () => {
  const browser = await chromium.launch();
  const tab = await browser.newPage({ viewport: { width: 1200, height: 630 }, colorScheme: "light" });
  const html = path.join(root, "scripts/cards/.render.html");
  const outputs = {};
  fs.mkdirSync(path.join(root, "site/images/cards"), { recursive: true });
  try {
    for (const card of cards) {
      fs.writeFileSync(html, page(card));
      await tab.goto("file://" + html);
      await tab.evaluate(() => document.fonts.ready);
      // Largest title size that fits the copy column.
      await tab.evaluate(() => {
        const h1 = document.querySelector("h1");
        const copy = document.querySelector(".copy");
        for (let size = 72; size >= 40; size -= 2) {
          h1.style.fontSize = size + "px";
          if (copy.scrollHeight <= copy.clientHeight && h1.scrollWidth <= h1.clientWidth) break;
        }
      });
      await tab.waitForFunction(() => [...document.images].every((image) => image.complete && image.naturalWidth));
      const output = `site/images/cards/${card.name}.png`;
      await tab.screenshot({ path: path.join(root, output) });
      outputs[output] = sha(output);
    }
  } finally {
    fs.rmSync(html, { force: true });
    await browser.close();
  }
  const inputs = ["scripts/site-cards.cjs", "site/fonts/Figtree-Medium.ttf", "site/fonts/Figtree-Regular.ttf", "site/images/mark.png",
    ...posts.map((post) => `scripts/blog/posts/${post.slug}.md`),
    ...new Set(cards.flatMap((card) => [card.cover, card.art, ...(card.fan || [])]).filter(Boolean))].sort();
  const manifest = { inputs: Object.fromEntries(inputs.map((name) => [name, sha(name)])), outputs };
  fs.writeFileSync(path.join(root, "scripts/cards/manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  console.log(`Rendered ${cards.length} cards`);
})();
