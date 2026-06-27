const fs = require('fs');
const path = require('path');
const readline = require('readline');

const ROOT = path.resolve(__dirname, '..');
const SOURCES = [
  path.join(ROOT, 'assets', 'drug_dict', 'all1_11507_1.TXT'),
  path.join(ROOT, 'assets', 'drug_dict', 'all1_11507_2.TXT'),
];
const OUT = path.join(ROOT, 'assets', 'drug_dict', 'drug_dict_nhi.json');

const EN_START = 220;
const EN_END = 330;
const DOSE_START = 280;
const DOSE_END = 340;
const FORM_START = 340;
const FORM_END = 420;
const ZH_START = 720;
const ZH_END = 860;

function normalizeKey(input) {
  let out = '';
  for (const ch of String(input).trim()) {
    let code = ch.codePointAt(0);
    if (code === 0x3000) {
      code = 0x20;
    } else if (code >= 0xff01 && code <= 0xff5e) {
      code -= 0xfee0;
    }
    out += String.fromCodePoint(code);
  }
  return out.toLowerCase().replace(/[^0-9a-z\u4e00-\u9fff]/g, '');
}

function cleanZh(raw) {
  return String(raw)
    .trim()
    .replace(/^\d+\s+/, '')
    .replace(/\s{2,}.*/, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function cleanEn(raw) {
  return String(raw)
    .trim()
    .replace(/\s{2,}.*/, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function cleanDose(raw) {
  return String(raw)
    .trim()
    .replace(/\s+/g, ' ')
    .replace(/\s*$/g, '')
    .trim();
}

function cleanForm(raw) {
  return String(raw)
    .trim()
    .replace(/\s{2,}.*/, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractProductDose(line) {
  const tail = String(line).slice(ZH_START);
  const match = tail.match(
    /([0-9]+(?:\.[0-9]+)?)\s*(MG|ML|IU|MCG|UG)(?:\s*\/\s*([0-9]+(?:\.[0-9]+)?)\s*(MG|ML|IU|MCG|UG))?/i
  );
  if (!match) return '';

  const leftValue = match[1];
  const leftUnit = match[2].toUpperCase();
  const rightValue = match[3];
  const rightUnit = match[4] ? match[4].toUpperCase() : '';

  if (rightValue && rightUnit) {
    return `${leftValue} ${leftUnit}/${rightValue} ${rightUnit}`;
  }
  return `${leftValue} ${leftUnit}`;
}

async function readLines(filePath, onLine) {
  const rl = readline.createInterface({
    input: fs.createReadStream(filePath, { encoding: 'utf8' }),
    crlfDelay: Infinity,
  });

  for await (const line of rl) {
    await onLine(line);
  }
}

async function main() {
  const map = new Map();

  for (const source of SOURCES) {
    await readLines(source, async (line) => {
      if (!line || line.length < ZH_START + 5) return;

      const zh = cleanZh(line.slice(ZH_START, ZH_END));
      const en = cleanEn(line.slice(EN_START, EN_END));
      const form = cleanForm(line.slice(FORM_START, FORM_END));
      const baseDose = cleanDose(line.slice(DOSE_START, DOSE_END));
      const productDose = cleanDose(extractProductDose(line));
      const dose = form.includes('注射')
        ? (baseDose || productDose)
        : (productDose || baseDose);
      if (!zh || !en) return;

      const key = normalizeKey(zh);
      if (!key) return;

      const existing = map.get(key);
      if (!existing) {
        map.set(key, {
          zh: [zh],
          en,
          alias: [en],
          dose,
          form,
        });
        return;
      }

      if (!existing.zh.includes(zh)) {
        existing.zh.push(zh);
      }
      if (!existing.alias.includes(en)) {
        existing.alias.push(en);
      }
      if (!existing.dose && dose) {
        existing.dose = dose;
      }
      if (!existing.form && form) {
        existing.form = form;
      }
    });
  }

  const out = Array.from(map.values());
  fs.writeFileSync(OUT, JSON.stringify(out, null, 2), 'utf8');
  console.log(`wrote ${out.length} entries to ${OUT}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
