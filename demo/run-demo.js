// Launches the self-running Vesper demo in headless Chromium at iPhone
// size, records one full scripted session (~40 s) to demo/out/vesper-demo.webm,
// and grabs three stills along the way.
//
//   node run-demo.js [--chromium /path/to/chrome]
//
// (Sound exists in the demo but browser recordings are video-only; open
// vesper-demo.html in a normal browser and click once to hear the pops.)

const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright-core");

const chromiumPath =
  process.argv.includes("--chromium")
    ? process.argv[process.argv.indexOf("--chromium") + 1]
    : process.env.CHROMIUM || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome";

const outDir = path.resolve(__dirname, "out");

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch({ executablePath: chromiumPath });
  const context = await browser.newContext({
    viewport: { width: 440, height: 956 },
    deviceScaleFactor: 2,
    recordVideo: { dir: outDir, size: { width: 440, height: 956 } },
  });
  const page = await context.newPage();
  await page.goto("file://" + path.resolve(__dirname, "vesper-demo.html"));
  console.log("demo running — recording one full session…");

  const still = async (name, ms) => {
    await page.waitForTimeout(ms);
    await page.screenshot({ path: path.join(outDir, name) });
    console.log("still:", name);
  };
  await still("demo-1-field.png", 6500);     // mid-play, bursts and whispers
  await still("demo-2-fortune.png", 2500);   // the fortune card (visible ~7.4–10.8s)
  await still("demo-3-cascade.png", 6000);   // chains through the cluster
  await still("demo-4-done.png", 6500);      // the done card (~20–24s)

  await page.waitForTimeout(3000);
  const video = page.video();
  await context.close();
  const raw = await video.path();
  const finalPath = path.join(outDir, "vesper-demo.webm");
  fs.renameSync(raw, finalPath);
  await browser.close();
  console.log("wrote", finalPath);
})();
