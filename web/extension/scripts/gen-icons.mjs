// Generate every raster brand asset from one source of truth. The Android
// launcher uses vector drawables; these PNGs are only for browser/store targets.
// Run with: pnpm --dir web/extension run icons

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { Resvg } from '@resvg/resvg-js';

const source = readFileSync(new URL('../../app/public/favicon.svg', import.meta.url), 'utf8');
const extensionDir = fileURLToPath(new URL('../public/icon/', import.meta.url));
const pwaDir = fileURLToPath(new URL('../../icons/', import.meta.url));
const webDir = fileURLToPath(new URL('../../', import.meta.url));
const playStorePath = fileURLToPath(new URL('../../../app/src/main/ic_launcher-playstore.png', import.meta.url));

function render(size) {
  return new Resvg(source, {
    fitTo: { mode: 'width', value: size },
  }).render().asPng();
}

function write(path, size) {
  const bytes = render(size);
  mkdirSync(fileURLToPath(new URL('.', `file://${path}`)), { recursive: true });
  writeFileSync(path, bytes);
}

mkdirSync(extensionDir, { recursive: true });
for (const size of [16, 32, 48, 96, 128]) {
  writeFileSync(`${extensionDir}${size}.png`, render(size));
  console.log(`extension icon ${size}px`);
}

mkdirSync(pwaDir, { recursive: true });
for (const size of [192, 512]) {
  const bytes = render(size);
  writeFileSync(`${pwaDir}Icon-${size}.png`, bytes);
  writeFileSync(`${pwaDir}Icon-maskable-${size}.png`, bytes);
  console.log(`PWA icon ${size}px`);
}

writeFileSync(`${webDir}favicon.png`, render(64));
mkdirSync(fileURLToPath(new URL('../../../app/src/main/', import.meta.url)), { recursive: true });
writeFileSync(playStorePath, render(512));
console.log('web favicon 64px');
console.log('Android Play Store artwork 512px');
