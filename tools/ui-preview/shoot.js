// Screenshots the generated preview pages: node shoot.js <out-dir> <name>...
const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const [out, ...names] = process.argv.slice(2);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  for (const n of names) {
    await page.goto('file://' + path.resolve(out, `_${n}.html`));
    await page.waitForTimeout(400);
    await page.screenshot({ path: path.resolve(out, `${n}.png`) });
    console.log('wrote', path.resolve(out, `${n}.png`));
  }
  await browser.close();
})();
