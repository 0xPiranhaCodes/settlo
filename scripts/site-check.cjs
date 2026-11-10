const { chromium } = require("playwright");
const fs = require("fs");
(async () => {
  const browser = await chromium.launch({
    executablePath:
      process.env.CHROME_PATH ||
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    headless: true,
  });
  const results = [];
  const { execFileSync } = require("child_process");
  for (const slug of ["privacy", "support"]) {
    const file = `site/${slug}/index.html`;
    const before = execFileSync(
      "git",
      ["show", `ca9ee2c84aac85feb4ec742c6b535faf83c9e9ac:${file}`],
      { env: { ...process.env, GIT_CONFIG_COUNT: "0" }, encoding: "utf8" },
    );
    const current = fs.readFileSync(file, "utf8");
    if (before.split("<body>")[1] !== current.split("<body>")[1])
      throw Error("Policy body changed: " + slug);
  }
  for (const width of [360, 1440]) {
    const context = await browser.newContext({
      viewport: { width, height: 900 },
      deviceScaleFactor: 1,
      javaScriptEnabled: false,
      reducedMotion: "reduce",
    });
    const page = await context.newPage();
    const requests = [];
    page.on("request", (r) => requests.push(r.url()));
    for (const path of ["", "privacy/", "support/"]) {
      await page.goto("http://127.0.0.1:8765/" + path);
      await page.evaluate(() => document.fonts.ready);
      const overflow = await page.evaluate(
        () => document.documentElement.scrollWidth > innerWidth,
      );
      if (overflow) throw new Error("Overflow " + width + " " + path);
      if (!path) {
        const blocks = await page
          .locator('script[type="application/ld+json"]')
          .allTextContents();
        const schemas = blocks.map(JSON.parse);
        const faq = schemas.find((x) => x["@type"] === "FAQPage");
        const visible = await page
          .locator("details")
          .evaluateAll((ds) =>
            ds.map((d) => ({
              q: d.querySelector("summary").textContent,
              a: d.querySelector("p").textContent,
            })),
          );
        if (
          JSON.stringify(visible) !==
          JSON.stringify(
            faq.mainEntity.map((q) => ({
              q: q.name,
              a: q.acceptedAnswer.text,
            })),
          )
        )
          throw Error("FAQ schema mismatch");
        if (JSON.stringify(schemas).includes("aggregateRating"))
          throw Error("Invented rating");
        await page.screenshot({
          path: `docs/evidence/140/landing-${width}.png`,
          fullPage: true,
        });
        await page.locator("summary").first().click();
        if (
          (await page.locator("details").first().getAttribute("open")) === null
        )
          throw Error("FAQ");
      } else if (width === 360)
        await page.screenshot({
          path: `docs/evidence/140/${path.slice(0, -1)}-${width}.png`,
          fullPage: true,
        });
      results.push({ width, path, overflow, jsDisabled: true });
    }
    if (requests.some((u) => !u.startsWith("http://127.0.0.1:8765/")))
      throw Error("External request");
    await context.close();
  }
  await browser.close();
  fs.writeFileSync(
    "docs/evidence/140/browser.json",
    JSON.stringify(results, null, 2) + "\n",
  );
})();
