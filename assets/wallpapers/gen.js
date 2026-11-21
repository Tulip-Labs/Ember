// Ember's wallpapers: Iris, goddess of the rainbow, in liquid glass.
// node gen.js -> iris-light.svg, iris-dark.svg
const fs = require('fs');
const icon = fs.readFileSync(process.argv[2], 'utf8');
const pick = id => icon.match(new RegExp(`<path id="${id}" d="([^"]+)"`))[1];
const head = pick('head'), wing = pick('wing');
const hair = icon.match(/<!-- the hair[\s\S]*?<\/g>/)[0];
const face = icon.match(/<!-- brow, eye and lips[\s\S]*?(?=\n    <\/g>)/)[0];
const glints = icon.match(/<!-- glints[\s\S]*?<\/g>/)[0];

function rng(seed) { return () => (seed = (seed * 16807) % 2147483647) / 2147483647; }

function svg(dark) {
  const T = 'translate(950 96) scale(1.08)';
  const sky = dark
    ? [['0', '#07051a'], ['0.45', '#16104a'], ['0.8', '#1d1a6b'], ['1', '#052a46']]
    : [['0', '#fbf6f1'], ['0.4', '#f4e9f7'], ['0.75', '#e4ecff'], ['1', '#d9f1fb']];
  const glowA = dark ? ['#ff5fc8', 0.30] : ['#ffb3dc', 0.55];
  const glowB = dark ? ['#2fb4ff', 0.26] : ['#9fdcff', 0.55];
  const bowOp = dark ? 0.95 : 0.62;
  const stars = [];
  if (dark) {
    const r = rng(7);
    for (let i = 0; i < 220; i++) {
      const x = r() * 1920, y = r() * 760, s = r() * 1.3 + 0.3, o = (r() * 0.6 + 0.25).toFixed(2);
      stars.push(`<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${s.toFixed(2)}" fill="#fff" opacity="${o}"/>`);
    }
  }
  const orbs = [];
  {
    const r = rng(dark ? 11 : 5);
    for (let i = 0; i < 9; i++) {
      const x = 80 + r() * 900, y = 120 + r() * 860, s = 10 + r() * 34;
      orbs.push(`<g opacity="${dark ? 0.55 : 0.75}"><circle cx="${x.toFixed(0)}" cy="${y.toFixed(0)}" r="${s.toFixed(0)}" fill="url(#orb)"/><circle cx="${x.toFixed(0)}" cy="${y.toFixed(0)}" r="${s.toFixed(0)}" fill="none" stroke="url(#rim)" stroke-width="1.6"/></g>`);
    }
  }
  const tint = dark ? '#1b0f4a' : '#8c7bd6';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1920 1080" width="3840" height="2160">
  <!-- Iris, goddess of the rainbow, in liquid glass: Ember's ${dark ? 'dark' : 'light'} wallpaper.
       An original drawing made for Ember (Tulip Labs), GPL-3.0 like Ember. -->
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0.9" y2="1">${sky.map(([o, c]) => `<stop offset="${o}" stop-color="${c}"/>`).join('')}</linearGradient>
    <radialGradient id="glowA" cx="0.72" cy="0.18" r="0.6"><stop offset="0" stop-color="${glowA[0]}" stop-opacity="${glowA[1]}"/><stop offset="1" stop-color="${glowA[0]}" stop-opacity="0"/></radialGradient>
    <radialGradient id="glowB" cx="0.12" cy="0.95" r="0.7"><stop offset="0" stop-color="${glowB[0]}" stop-opacity="${glowB[1]}"/><stop offset="1" stop-color="${glowB[0]}" stop-opacity="0"/></radialGradient>
    <linearGradient id="bow" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#ff3b6b"/><stop offset="0.18" stop-color="#ff9f0a"/><stop offset="0.36" stop-color="#ffe14d"/>
      <stop offset="0.54" stop-color="#34d399"/><stop offset="0.7" stop-color="#38bdf8"/><stop offset="0.86" stop-color="#6366f1"/><stop offset="1" stop-color="#d08cff"/>
    </linearGradient>
    <filter id="soft" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="34"/></filter>
    <filter id="haze" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="90"/></filter>
    <filter id="lensblur"><feGaussianBlur stdDeviation="3"/></filter>
    <linearGradient id="glassFill" x1="0.2" y1="0.05" x2="0.8" y2="1">
      <stop offset="0" stop-color="#fff" stop-opacity="${dark ? 0.40 : 0.62}"/><stop offset="0.42" stop-color="#fff" stop-opacity="${dark ? 0.06 : 0.14}"/>
      <stop offset="0.8" stop-color="#fff" stop-opacity="${dark ? 0.10 : 0.2}"/><stop offset="1" stop-color="#fff" stop-opacity="${dark ? 0.30 : 0.5}"/>
    </linearGradient>
    <linearGradient id="rim" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset="0.35" stop-color="#fff" stop-opacity="0.3"/>
      <stop offset="0.65" stop-color="#fff" stop-opacity="0.12"/><stop offset="1" stop-color="#fff" stop-opacity="0.9"/>
    </linearGradient>
    <radialGradient id="orb" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#fff" stop-opacity="0.55"/><stop offset="0.6" stop-color="#fff" stop-opacity="0.08"/><stop offset="1" stop-color="#fff" stop-opacity="0.22"/></radialGradient>
    <filter id="inner" x="-10%" y="-10%" width="120%" height="120%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="16" result="b"/><feOffset dx="-12" dy="16" result="o"/>
      <feComposite in="SourceAlpha" in2="o" operator="out" result="edge"/><feFlood flood-color="#fff" flood-opacity="0.9"/><feComposite in2="edge" operator="in"/>
    </filter>
    <filter id="innerDark" x="-10%" y="-10%" width="120%" height="120%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="14" result="b"/><feOffset dx="14" dy="-14" result="o"/>
      <feComposite in="SourceAlpha" in2="o" operator="out" result="edge"/><feFlood flood-color="${tint}" flood-opacity="0.35"/><feComposite in2="edge" operator="in"/>
    </filter>
    <filter id="shade" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="22"/><feOffset dx="14" dy="28"/>
      <feComponentTransfer><feFuncA type="linear" slope="${dark ? 0.55 : 0.22}"/></feComponentTransfer>
    </filter>
    <linearGradient id="fadeDown" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0.66" stop-color="#fff"/><stop offset="0.93" stop-color="#fff" stop-opacity="0"/>
    </linearGradient>
    <mask id="neck" maskUnits="userSpaceOnUse" x="0" y="0" width="1920" height="1080"><rect width="1920" height="1080" fill="url(#fadeDown)"/></mask>
    <path id="head" d="${head}"/>
    <path id="wing" d="${wing}"/>
    <g id="scene">
      <rect width="1920" height="1080" fill="url(#sky)"/>
      <rect width="1920" height="1080" fill="url(#glowA)"/>
      <rect width="1920" height="1080" fill="url(#glowB)"/>
      <path d="M 520 1500 A 1060 1060 0 0 1 2640 1500" fill="none" stroke="url(#bow)" stroke-width="420" filter="url(#haze)" opacity="${dark ? 0.55 : 0.4}"/>
      <path d="M 520 1500 A 1060 1060 0 0 1 2640 1500" fill="none" stroke="url(#bow)" stroke-width="150" filter="url(#soft)" opacity="${bowOp}"/>
      <path d="M 520 1500 A 1060 1060 0 0 1 2640 1500" fill="none" stroke="url(#bow)" stroke-width="64" opacity="${dark ? 0.85 : 0.55}"/>
    </g>
    <clipPath id="hc"><use href="#head" transform="${T}"/></clipPath>
    <clipPath id="wc"><use href="#wing" transform="${T}"/></clipPath>
  </defs>
  <use href="#scene"/>
  ${stars.join('')}
  ${orbs.join('')}
  <g mask="url(#neck)">
    <use href="#wing" transform="${T}" filter="url(#shade)"/>
    <g clip-path="url(#wc)">
      <g filter="url(#lensblur)" transform="translate(1310 650) scale(1.15) translate(-1310 -650)"><use href="#scene"/></g>
      <use href="#wing" transform="${T}" fill="url(#glassFill)"/>
      <use href="#wing" transform="${T}" filter="url(#inner)"/>
    </g>
    <use href="#wing" transform="${T}" fill="none" stroke="url(#rim)" stroke-width="4"/>
    <use href="#head" transform="${T}" filter="url(#shade)"/>
    <g clip-path="url(#hc)">
      <g filter="url(#lensblur)" transform="translate(1510 640) scale(1.12) translate(-1510 -660)"><use href="#scene"/></g>
      <g transform="${T}">
        <use href="#head" fill="url(#glassFill)"/>
        <use href="#head" filter="url(#innerDark)"/>
        <use href="#head" filter="url(#inner)"/>
        ${hair}
        ${face}
      </g>
    </g>
    <g transform="${T}">
      <use href="#head" fill="none" stroke="url(#rim)" stroke-width="5"/>
      ${glints}
    </g>
  </g>
</svg>`;
}
fs.writeFileSync('iris-light.svg', svg(false));
fs.writeFileSync('iris-dark.svg', svg(true));
