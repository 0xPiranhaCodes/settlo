const { chromium } = require("playwright");
const fs = require("fs");
const outputDir = process.env.SITE_CHECK_OUTPUT || "/tmp/settlo-site-check";
const localUrl = process.env.SITE_CHECK_URL || "http://127.0.0.1:8765/";
const publicUrl = "https://settlo.hellojosh.studio/";
(async () => {
  fs.mkdirSync(outputDir, { recursive: true });
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
      ["show", `0f610060b640b23f0a7a7b73f7783a140e70680b:${file}`],
      { env: { ...process.env, GIT_CONFIG_COUNT: "0" }, encoding: "utf8" },
    );
    const current = fs.readFileSync(file, "utf8");
    // Policy wording lives in <main>; the shared header and footer may change.
    const main = (html) => html.split("<main>")[1].split("</main>")[0];
    if (main(before) !== main(current))
      throw Error("Policy body changed: " + slug);
  }
  for (const width of [360, 390, 768, 1440]) {
    for (const colorScheme of ["light", "dark"]) {
      const context = await browser.newContext({
        viewport: { width, height: 900 },
        colorScheme,
        deviceScaleFactor: 1,
        javaScriptEnabled: false,
        reducedMotion: "reduce",
      });
      const page = await context.newPage();
      const requests = [];
      const failures = [];
      page.on("request", (r) => requests.push(r.url()));
      page.on("requestfailed", (r) => failures.push(r.url()));
      page.on("response", (r) => {
        if (r.status() >= 400) failures.push(`${r.status()} ${r.url()}`);
      });
      for (const path of ["", "privacy/", "support/"]) {
        await page.goto(localUrl + path);
        await page.evaluate(() => document.fonts.ready);
        // With JavaScript disabled Chrome loads lazy images eagerly. Decode all
        // images, including below-fold assets, without changing their srcset state.
        await page.locator("img").evaluateAll(async (images) => {
          await Promise.all(images.map(async (img) => {
            await img.decode();
          }));
        });
        if (await page.locator('link[rel="canonical"]').getAttribute("href") !== publicUrl + path)
          throw Error("Canonical URL mismatch: " + path);
        const overflow = await page.evaluate(
          () => document.documentElement.scrollWidth > innerWidth,
        );
        if (overflow) throw new Error("Overflow " + width + " " + path);
        if (!path) {
          const blocks = await page
            .locator('script[type="application/ld+json"]')
            .allTextContents();
          const schemas = blocks.map(JSON.parse);
          const app = schemas.find((x) => x["@type"] === "SoftwareApplication");
          if (app.url !== publicUrl || app.image !== publicUrl + "images/social.png")
            throw Error("Application schema URL mismatch");
          for (const [selector, expected] of [
            ['meta[property="og:url"]', publicUrl],
            ['meta[property="og:image"]', publicUrl + "images/social.png"],
            ['meta[name="twitter:image"]', publicUrl + "images/social.png"],
          ]) {
            if (await page.locator(selector).getAttribute("content") !== expected)
              throw Error("Social URL mismatch: " + selector);
          }
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
          const geometry = await page.evaluate(() => {
            const rect = (element) => element.getBoundingClientRect();
            const intersects = (a, b) => a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
            const images = [...document.querySelectorAll('.screen img')];
            const copies = [...document.querySelectorAll('.hero-copy, .flat-copy, .loan-copy, .trip-steps > li > p, section h2, .hero figcaption')];
            return images.every((image) => copies.every((copy) => !intersects(rect(image), rect(copy)))) &&
              images.every((image, i) => images.slice(i+1).every((other) => !intersects(rect(image), rect(other))));
          });
          if (!geometry) throw Error('Phone overlaps copy or another phone');
          await page.screenshot({
            path: `${outputDir}/landing-${width}-${colorScheme}.png`,
            fullPage: true,
          });
          await page.locator("summary").first().click();
          if (
            (await page.locator("details").first().getAttribute("open")) === null
          )
            throw Error("FAQ");
        } else if (width === 360)
          await page.screenshot({
            path: `${outputDir}/${path.slice(0, -1)}-${width}-${colorScheme}.png`,
            fullPage: true,
          });
        results.push({ width, colorScheme, path, overflow, jsDisabled: true });
      }
      if (requests.some((u) => !u.startsWith(localUrl)))
        throw Error("External request");
      if (failures.length) throw Error("Failed resources: " + failures.join(", "));
      await context.close();
    }
  }
  await browser.close();
  fs.writeFileSync(
    `${outputDir}/browser.json`,
    JSON.stringify(results, null, 2) + "\n",
  );
})();
