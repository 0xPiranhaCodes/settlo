// Rendering checks must load below-fold assets too. Chrome can briefly report
// complete=true/naturalWidth=0 while selecting a candidate, especially with JS
// disabled. Poll loaded state on a timer (not rAF), then decode the stable URL.
async function waitForImages(page, timeout = 10000) {
  await page.locator("img").evaluateAll((images) =>
    images.forEach((image) => {
      image.loading = "eager";
    }),
  );
  await page
    .waitForFunction(
      () =>
        [...document.images].every(
          (image) => image.complete && image.naturalWidth > 0,
        ),
      null,
      { polling: 100, timeout },
    )
    .catch(async (error) => {
      const state = await page.locator("img").evaluateAll((images) =>
        images.map((image) => ({
          src: image.currentSrc,
          complete: image.complete,
          width: image.naturalWidth,
        })),
      );
      throw Error(
        `Images did not load: ${JSON.stringify(state)}: ${error.message}`,
      );
    });
  await page.locator("img").evaluateAll(async (images) => {
    await Promise.all(
      images.map(async (image) => {
        try {
          await image.decode();
        } catch {
          // A candidate switch invalidates an in-flight decode. Decode the actual
          // selected resource independently; corrupt/missing bytes still reject.
          const probe = new Image();
          probe.src = image.currentSrc;
          await probe.decode();
        }
      }),
    );
  });
}
module.exports = { waitForImages };
