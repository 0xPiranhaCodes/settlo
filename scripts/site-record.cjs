// Short, reproducible recordings of real scrolling. Requires Playwright's ffmpeg.
const { chromium } = require("playwright");
const fs = require("fs");
const output = process.env.SITE_CHECK_OUTPUT || "/tmp/settlo-site-record";
const url = process.env.SITE_CHECK_URL || "http://127.0.0.1:8765/";
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch({
    executablePath:
      process.env.CHROME_PATH ||
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  });
  for (const width of [390, 1440]) {
    const context = await browser.newContext({
      viewport: { width, height: width === 390 ? 844 : 900 },
      colorScheme: "light",
      reducedMotion: "no-preference",
      recordVideo: {
        dir: output,
        size: { width, height: width === 390 ? 844 : 900 },
      },
    });
    const page = await context.newPage();
    await page.goto(url);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(800);
    // Native smooth scrolling isn't accelerated by a synthetic screenshot stitch.
    await page.evaluate(async () => {
      const end = document.querySelector(".loan").offsetTop + 600;
      const start = performance.now(),
        duration = 22000;
      await new Promise((resolve) => {
        function frame(now) {
          const progress = Math.min(1, (now - start) / duration);
          scrollTo({ top: end * progress, behavior: "instant" });
          if (progress < 1) requestAnimationFrame(frame);
          else resolve();
        }
        requestAnimationFrame(frame);
      });
    });
    await page.waitForTimeout(800);
    const video = page.video();
    await context.close();
    await video.saveAs(`${output}/scroll-${width}.webm`);
    await video.delete();
  }
  await browser.close();
})();
