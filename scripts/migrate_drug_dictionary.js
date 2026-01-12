/*
Usage:
  1. Install dependencies: `npm init -y && npm install firebase-admin`
  2. Run:
     node scripts/migrate_drug_dictionary.js /path/to/serviceAccountKey.json

This script will:
 - read all documents in `drug_dictionary`
 - normalize `zh` into an array of trimmed unique strings
 - normalize `en` to string
 - normalize `alias` to include generic lowercase names (adds en lowercased)
 - generate `keywords` (lowercase prefixes up to 12 chars) from zh/en/alias
 - update each document with the normalized fields (merge)

Be careful: run on a backup copy or test project first.
*/

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

async function main() {
  const keyPath = process.argv[2] || process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!keyPath) {
    console.error('Service account key JSON path required as first arg or GOOGLE_APPLICATION_CREDENTIALS env var.');
    process.exit(1);
  }
  if (!fs.existsSync(keyPath)) {
    console.error('Key file not found:', keyPath);
    process.exit(1);
  }

  const serviceAccount = require(path.resolve(keyPath));

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });

  const db = admin.firestore();
  const col = db.collection('drug_dictionary');

  console.log('Fetching documents...');
  const snap = await col.get();
  console.log('Found', snap.size, 'documents');

  let i = 0;
  for (const doc of snap.docs) {
    i++;
    const data = doc.data();

    // normalize zh -> array of strings
    let zhList = [];
    if (Array.isArray(data.zh)) {
      zhList = data.zh.filter(x => typeof x === 'string').map(s => s.trim()).filter(s => s.length);
    } else if (typeof data.zh === 'string') {
      zhList = data.zh.split(/[，,\/=\\]/).map(s => s.trim()).filter(s => s.length);
    }

    // unique
    zhList = [...new Set(zhList)];

    // en
    const en = (typeof data.en === 'string') ? data.en.trim() : '';

    // alias normalize: gather existing aliases + en (lowercased)
    const aliasIn = Array.isArray(data.alias) ? data.alias.filter(x => typeof x === 'string').map(s => s.trim()) : [];
    const aliasSet = new Set();
    if (en) aliasSet.add(en.toLowerCase());
    for (const a of aliasIn) {
      if (!a) continue;
      aliasSet.add(a.toLowerCase());
    }

    // Heuristic: keep aliases that look like generic names (letters, numbers, hyphen)
    const aliasFiltered = [...aliasSet].filter(s => /^[a-z0-9\-]+$/.test(s));

    // keywords generation (prefixes up to 12 chars)
    const kw = new Set();
    function addKeywordsFrom(s) {
      if (!s) return;
      const t = s.toLowerCase();
      for (let k = 1; k <= Math.min(12, t.length); k++) kw.add(t.substring(0, k));
      kw.add(t);
    }

    for (const z of zhList) addKeywordsFrom(z);
    if (en) addKeywordsFrom(en);
    for (const a of aliasFiltered) addKeywordsFrom(a);

    const update = {
      zh: zhList.length ? zhList : (typeof data.zh === 'string' ? data.zh : ''),
      en: en,
      alias: aliasFiltered,
      keywords: Array.from(kw),
    };

    try {
      await doc.ref.set(update, { merge: true });
      console.log(`${i}/${snap.size} updated: ${doc.id}`);
    } catch (e) {
      console.error(`Failed to update ${doc.id}:`, e);
    }
  }

  console.log('Done');
  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
