// Captures the composed App Store screenshots from compose.html with
// headless Chromium at exact store pixel sizes.
//
//   node capture.js [--chromium /path/to/chrome]
//
// Writes into ../en-US/. These are faithful drafts composed from the real
// renderer math and palette; for pixel-perfect iOS type, re-capture on a
// simulator before shipping (docs/RELEASE_v1.2.md).

const path = require("path");
const { chromium } = require("playwright-core");

const chromiumPath =
  process.argv.includes("--chromium")
    ? process.argv[process.argv.indexOf("--chromium") + 1]
    : process.env.CHROMIUM || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome";

// App Store sizes: iPhone 6.9" = 1320×2868 (@3x 440×956pt),
// iPad 13" = 2064×2752 (@2x 1032×1376pt)
const DEVICES = [
  { tag: "6.9", device: "phone", w: 440, h: 956, scale: 3 },
  { tag: "13", device: "pad", w: 1032, h: 1376, scale: 2 },
];
const SCENES = ["play", "path", "journey", "fortune", "done"];

(async () => {
  const browser = await chromium.launch({ executablePath: chromiumPath });
  const page = await browser.newPage();
  const composeURL = "file://" + path.resolve(__dirname, "compose.html");
  const outDir = path.resolve(__dirname, "..", "en-US");

  for (const d of DEVICES) {
    await page.setViewportSize({ width: d.w, height: d.h });
    for (let i = 0; i < SCENES.length; i++) {
      const scene = SCENES[i];
      const context = await browser.newContext({
        viewport: { width: d.w, height: d.h },
        deviceScaleFactor: d.scale,
      });
      const p = await context.newPage();
      await p.goto(`${composeURL}?scene=${scene}&device=${d.device}`);
      await p.waitForTimeout(250); // fonts + canvas settle
      const file = path.join(outDir, `${d.tag}_0${i + 1}_${scene}.png`);
      await p.screenshot({ path: file });
      console.log("wrote", file);
      await context.close();
    }
  }
  await browser.close();
})();
