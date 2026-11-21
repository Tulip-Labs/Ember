const { chromium } = require('playwright');
(async () => {
  const [,, svg, out, w, h] = process.argv;
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: +w, height: +h } });
  const fs = require('fs');
  await p.setContent(`<html><body style="margin:0">${fs.readFileSync(svg,'utf8').replace('width="3840" height="2160"', `width="${w}" height="${h}"`)}</body></html>`);
  await p.screenshot({ path: out }); await b.close();
})();
