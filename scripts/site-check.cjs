const { waitForImages } = require("./site-images-ready.cjs");
const { chromium } = require("playwright");
const fs = require("fs");
const outputDir = process.env.SITE_CHECK_OUTPUT || "/tmp/settlo-site-check";
const localUrl = process.env.SITE_CHECK_URL || "http://127.0.0.1:8765/";
const publicUrl = "https://sabkijeb.app/";
const phonesClear = () => {
  const rect = (element) => element.getBoundingClientRect();
  const intersects = (a, b) =>
    a.left < b.right &&
    b.left < a.right &&
    a.top < b.bottom &&
    b.top < a.bottom;
  const images = [...document.querySelectorAll(".screen img")];
  const group = (image) => image.closest(".hero-screen, .loan-screens");
  const copies = [
    ...document.querySelectorAll(
      ".hero-copy, .flat-copy, .loan-copy, .trip-steps > li > p, section h2, .hero figcaption",
    ),
  ];
  return (
    images.every((image) =>
      copies.every((copy) => !intersects(rect(image), rect(copy))),
    ) &&
    // Phones may overlap only inside their composed group (#181).
    images.every((image, i) =>
      images
        .slice(i + 1)
        .every(
          (other) =>
            (group(image) !== null && group(image) === group(other)) ||
            !intersects(rect(image), rect(other)),
        ),
    )
  );
};
(async () => {
  fs.mkdirSync(outputDir, { recursive: true });
  const browser = await chromium.launch({
    executablePath:
      process.env.CHROME_PATH ||
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    headless: true,
    // Avoid GPU texture wrapping in full-page captures taller than 16k pixels.
    args: ["--disable-gpu"],
  });
  const results = [];
  const blogPaths = ["blog/", ...fs.readdirSync("site/blog", { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && fs.existsSync(`site/blog/${entry.name}/index.html`))
    .map((entry) => `blog/${entry.name}/`)];
  require("child_process").execFileSync("python3", ["scripts/site-build.py", "--check"]);
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
    // The SabkiJeb rebrand (#204) may change only the name and contact address.
    const rebranded = main(before)
      .replaceAll("settlo@hellojosh.studio", "support@sabkijeb.app")
      .replaceAll("Settlo", "SabkiJeb");
    if (rebranded !== main(current))
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
      page.on("requestfailed", (r) =>
        failures.push(`${r.failure()?.errorText} ${r.url()}`),
      );
      page.on("response", (r) => {
        if (r.status() >= 400) failures.push(`${r.status()} ${r.url()}`);
      });
      for (const path of ["", "privacy/", "support/", "delete-account/", "terms/", ...blogPaths]) {
        await page.goto(localUrl + path);
        await page.evaluate(() => document.fonts.ready);
        await waitForImages(page).catch((error) => {
          throw Error(
            `${width} ${colorScheme} ${path}: ${error.message}; ${failures.join(", ")}`,
          );
        });
        if (
          (await page.locator('link[rel="canonical"]').getAttribute("href")) !==
          publicUrl + path
        )
          throw Error("Canonical URL mismatch: " + path);
        const overflow = await page.evaluate(
          () => document.documentElement.scrollWidth > innerWidth,
        );
        if (overflow) throw new Error("Overflow " + width + " " + path);
        if (await page.locator('header nav a').filter({ hasText: /^Blog$/ }).count() !== 1)
          throw Error("Missing Blog header link: " + path);
        if (path !== "support/" && await page.locator('footer a').filter({ hasText: /^Blog$/ }).count() !== 1)
          throw Error("Missing Blog footer link: " + path);
        if (path.startsWith("blog/")) {
          for (const property of ["title", "description", "url", "image"]) {
            if (!await page.locator(`meta[property="og:${property}"]`).getAttribute("content"))
              throw Error("Missing blog OG metadata: " + path);
          }
          if (await page.locator('meta[property="og:url"]').getAttribute("content") !== publicUrl + path)
            throw Error("Blog OG URL mismatch: " + path);
          if (path !== "blog/") {
            const article = JSON.parse(await page.locator('script[type="application/ld+json"]').textContent());
            if (article["@type"] !== "Article" || article.headline !== await page.locator("h1").textContent()
              || article.mainEntityOfPage !== publicUrl + path)
              throw Error("Article schema mismatch: " + path);
          }
          // Check every same-site article link and asset, including fragment targets.
          const links = await page.locator('main a[href], main img[src]').evaluateAll((els) =>
            els.map((el) => el.href || el.src));
          for (const link of links) {
            const url = new URL(link);
            if (url.protocol === "mailto:") continue;
            if (url.origin !== new URL(localUrl).origin) throw Error("External blog link: " + link);
            const response = await context.request.get(url.href);
            if (!response.ok()) throw Error("Broken blog link: " + link);
            if (url.hash && !(await response.text()).includes(`id="${url.hash.slice(1)}"`))
              throw Error("Broken blog fragment: " + link);
          }
          if ([360, 390, 1440].includes(width)) await page.screenshot({
            path: `${outputDir}/${path.replaceAll("/", "-")}${width}-${colorScheme}.png`, fullPage: true,
          });
        }
        if (!path) {
          const blocks = await page
            .locator('script[type="application/ld+json"]')
            .allTextContents();
          const schemas = blocks.map(JSON.parse);
          const app = schemas.find((x) => x["@type"] === "SoftwareApplication");
          if (
            app.url !== publicUrl ||
            app.image !== publicUrl + "images/social.png"
          )
            throw Error("Application schema URL mismatch");
          for (const [selector, expected] of [
            ['meta[property="og:url"]', publicUrl],
            ['meta[property="og:image"]', publicUrl + "images/social.png"],
            ['meta[name="twitter:image"]', publicUrl + "images/social.png"],
          ]) {
            if (
              (await page.locator(selector).getAttribute("content")) !==
              expected
            )
              throw Error("Social URL mismatch: " + selector);
          }
          const faq = schemas.find((x) => x["@type"] === "FAQPage");
          const visible = await page.locator("details").evaluateAll((ds) =>
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
          const geometry = await page.evaluate(phonesClear);
          if (!geometry) throw Error("Phone overlaps copy or another phone");
          // Regression fixtures: grouped siblings may overlap; ungrouped phones may not.
          for (const [html, allowed] of [
            ['<figure class="screen hero-screen"><img><img></figure>', true],
            [
              '<div class="loan-screens"><figure class="screen"><img></figure><figure class="screen"><img></figure></div>',
              true,
            ],
            [
              '<div><figure class="screen"><img></figure><figure class="screen"><img></figure></div>',
              false,
            ],
          ]) {
            await page.evaluate((html) => {
              const fixture = document.createElement("div");
              fixture.id = "overlap-fixture";
              fixture.innerHTML = html;
              for (const img of fixture.querySelectorAll("img"))
                img.style.cssText =
                  "position:fixed;left:-100px;top:-100px;width:10px;height:10px";
              document.body.append(fixture);
            }, html);
            const clear = await page.evaluate(phonesClear);
            await page.evaluate(() =>
              document.getElementById("overlap-fixture").remove(),
            );
            if (clear !== allowed)
              throw Error("Overlap fixture misjudged: " + html);
          }
          const scalesMatch = await page
            .locator(".loan-screens img")
            .evaluateAll((images) => {
              const scales = images.map(
                (img) => img.getBoundingClientRect().width / img.naturalWidth,
              );
              return (
                Math.abs(scales[0] - scales[1]) < 0.001 &&
                images.every(
                  (img) =>
                    Math.abs(
                      Number(img.getAttribute("width")) - img.naturalWidth,
                    ) <= 1 &&
                    Math.abs(
                      Number(img.getAttribute("height")) - img.naturalHeight,
                    ) <= 1,
                )
              );
            });
          if (!scalesMatch)
            throw Error("Rendered loan phones use different physical scales");

          await page.evaluate(() => scrollTo({ top: 0, behavior: "instant" }));
          await page.screenshot({
            path: `${outputDir}/landing-${width}-${colorScheme}.png`,
            fullPage: true,
          });
          await page.locator("summary").first().click();
          if (
            (await page.locator("details").first().getAttribute("open")) ===
            null
          )
            throw Error("FAQ");
        } else if (width === 360)
          await page.screenshot({
            path: `${outputDir}/${path.slice(0, -1).replaceAll("/", "-")}-${width}-${colorScheme}.png`,
            fullPage: true,
          });
        results.push({ width, colorScheme, path, overflow, jsDisabled: true });
      }
      if (requests.some((u) => !u.startsWith(localUrl)))
        throw Error("External request");
      if (failures.length)
        throw Error("Failed resources: " + failures.join(", "));
      await context.close();
    }
  }
  // Active motion, reduced motion, and the small legacy-browser fallback.
  const motionResults = [];
  for (const width of [360, 390, 768, 1440]) {
    for (const colorScheme of ["light", "dark"]) {
      for (const mode of ["native", "fallback", "reduced"]) {
        const context = await browser.newContext({
          viewport: { width, height: 900 },
          colorScheme,
          reducedMotion: mode === "reduced" ? "reduce" : "no-preference",
        });
        if (mode === "fallback")
          await context.addInitScript(() => {
            const supports = CSS.supports.bind(CSS);
            CSS.supports = (...args) =>
              args[0] === "animation-timeline: view()"
                ? false
                : supports(...args);
          });
        const page = await context.newPage();
        await page.goto(localUrl);
        if (mode === "fallback")
          await page.addStyleTag({
            content: "* { animation: none !important; }",
          });
        const selector = ".trip-product";
        for (const target of [
          ".trip",
          ".trip-steps > li:nth-child(2)",
          ".flat",
          ".loan",
          ".closing",
        ]) {
          await page
            .locator(target)
            .evaluate((el) =>
              scrollTo({ top: el.offsetTop + 120, behavior: "instant" }),
            );
          await page.waitForTimeout(120);
          if (
            await page.evaluate(
              () => document.documentElement.scrollWidth > innerWidth,
            )
          )
            throw Error(`Motion overflow ${width} ${colorScheme} ${mode}`);
        }
        const sticky = await page
          .locator(selector)
          .evaluate((el) => getComputedStyle(el).position);
        if (
          sticky !== (mode === "reduced" || width <= 900 ? "static" : "sticky")
        )
          throw Error("Sticky/reduced motion mismatch");
        if (
          mode === "reduced" &&
          (await page
            .locator(".flat .screen")
            .evaluate((el) => getComputedStyle(el).animationName !== "none"))
        )
          throw Error("Reduced motion animation");
        if (
          mode === "fallback" &&
          !(await page
            .locator("html")
            .evaluate((el) => el.classList.contains("motion-fallback")))
        )
          throw Error("Fallback did not initialise");
        await page.locator(".flat .screen").scrollIntoViewIfNeeded();
        await page.waitForTimeout(800);
        if (
          mode === "fallback" &&
          (await page
            .locator(".flat .screen")
            .evaluate((el) => el.classList.contains("awaiting")))
        )
          throw Error("Fallback failed to reveal phone");
        motionResults.push({
          width,
          colorScheme,
          mode,
          sticky,
          overflow: false,
        });
        await context.close();
      }
    }
  }
  const densityResults = [];
  for (const density of [1, 2, 3]) {
    const context = await browser.newContext({
      viewport: { width: 390, height: 844 },
      deviceScaleFactor: density,
      reducedMotion: "reduce",
    });
    const page = await context.newPage();
    await page.goto(localUrl);
    await page.evaluate(() => document.fonts.ready);
    const hero = page.locator(".hero-front");
    await hero.evaluate((image) => image.decode());
    const state = await hero.evaluate((image) => ({
      src: image.currentSrc,
      top: image.getBoundingClientRect().top,
      bottom: image.getBoundingClientRect().bottom,
    }));
    if (Math.min(844, state.bottom) - state.top < 200)
      throw Error("Hero product below fold");
    if ((await page.locator(".hero .button").boundingBox()).y + 56 > 844)
      throw Error("Hero CTA below fold");
    const suffix = density === 1 ? "-phone.avif" : `-phone@${density}x.avif`;
    if (!state.src.endsWith(suffix))
      throw Error("Wrong density selected: " + state.src);
    densityResults.push({ density, ...state });
    const cdp = await context.newCDPSession(page);
    await cdp.send("Emulation.setEmulatedMedia", {
      features: [{ name: "prefers-reduced-transparency", value: "reduce" }],
    });
    const nav = await page.locator("header").evaluate((el) => ({
      filter: getComputedStyle(el).backdropFilter,
      background: getComputedStyle(el).backgroundColor,
    }));
    if (nav.filter !== "none" || nav.background.includes("rgba"))
      throw Error("Reduce transparency fallback");
    await context.close();
  }
  // Regression for #167: the tablet Goa canvas must match Flat 402's canvas.
  const tablet = await browser.newPage({
    viewport: { width: 768, height: 900 },
    reducedMotion: "reduce",
  });
  await tablet.goto(localUrl);
  const tabletWidths = await tablet.evaluate(() =>
    [".trip-product img", ".flat .screen img"].map(
      (selector) =>
        document.querySelector(selector).getBoundingClientRect().width,
    ),
  );
  if (Math.abs(tabletWidths[0] - tabletWidths[1]) > 1)
    throw Error("Goa tablet phone shrank");
  await tablet.close();
  fs.writeFileSync(
    `${outputDir}/density.json`,
    JSON.stringify({ densityResults, tabletWidths }, null, 2),
  );
  const manifest = JSON.parse(fs.readFileSync("site/images/sources.json"));
  const scales = Object.values(manifest.sources).map(
    (source) => source.phone.output_scale,
  );
  if (!scales.every((scale) => scale === scales[0]))
    throw Error("Inconsistent phone physical scale");
  // Each density is an alternative resource set, never downloaded together.
  const detailPaths = Object.values(manifest.details).map(
    (detail) => "site/images/" + detail.output,
  );
  const densityBytes = [0, 1, 2].map((density) =>
    [
      "site/images/mark.png",
      ...detailPaths,
      ...Object.values(manifest.sources).map(
        (source) => "site/images/" + source.phone.outputs[density],
      ),
    ].reduce((sum, file) => sum + fs.statSync(file).size, 0),
  );
  const imageBytes = Math.max(...densityBytes);
  if (imageBytes > 350 * 1024)
    throw Error("Landing image budget exceeded: " + imageBytes);
  fs.writeFileSync(
    `${outputDir}/motion.json`,
    JSON.stringify(
      { motionResults, imageBytes, densityBytes, deviceScales: scales },
      null,
      2,
    ) + "\n",
  );
  await browser.close();
  fs.writeFileSync(
    `${outputDir}/browser.json`,
    JSON.stringify(results, null, 2) + "\n",
  );
})();
