const fs = require('fs');
const path = require('path');

const files = [
  'd:/Software/Nuztrack/Nuztrack-win32-x64/resources/app/style.css'
];

function rgbaToHex(r, g, b, a) {
  const hex = [r, g, b].map(x => parseInt(x, 10).toString(16).padStart(2, '0')).join('');
  const alpha = Math.round(parseFloat(a) * 255).toString(16).padStart(2, '0');
  return `#${hex}${alpha}`;
}

files.forEach(file => {
  let content = fs.readFileSync(file, 'utf8');
  content = content.replace(/rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\)/g, (match, r, g, b, a) => {
    return rgbaToHex(r, g, b, a);
  });
  fs.writeFileSync(file, content, 'utf8');
  console.log(`Updated ${file}`);
});
