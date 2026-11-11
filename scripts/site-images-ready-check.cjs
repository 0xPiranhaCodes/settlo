// Focused reproduction for #167: five fresh no-JS contexts per retina density,
// followed by a corrupt resource that must fail rather than be swallowed.
const { chromium } = require("playwright");
const { waitForImages } = require("./site-images-ready.cjs");
(async () => {
  const browser = await chromium.launch({
    executablePath:
      process.env.CHROME_PATH ||
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  });
  const url = process.env.SITE_CHECK_URL || "http://127.0.0.1:8765/";
  try {
    for (const density of [1, 2, 3]) {
      for (let run = 0; run < 5; run++) {
        const context = await browser.newContext({
          viewport: { width: 390, height: 844 },
          deviceScaleFactor: density,
          javaScriptEnabled: false,
        });
        const page = await context.newPage();
        await page.goto(url);
        await waitForImages(page);
        await context.close();
      }
    }
    const page = await browser.newPage();
    await page.route("**/images/mark.png", (route) =>
      route.fulfill({ contentType: "image/png", body: "corrupt image" }),
    );
    await page.goto(url);
    let rejected = false;
    try {
      await waitForImages(page, 1500);
    } catch {
      rejected = true;
    }
    if (!rejected) throw Error("Corrupt image was accepted");
    console.log("PASS: 15 fresh no-JS density runs; corrupt image rejected");
  } finally {
    await browser.close();
  }
})();
