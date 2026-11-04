const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc } = require('firebase/firestore');

const host = process.env.FIRESTORE_EMULATOR_HOST;
test('clinic boundaries deny cross-clinic and inactive staff access', {
  skip: !host && 'local Firestore Emulator required',
}, async () => {
  const endpoint = /^127\.0\.0\.1:(\d+)$/.exec(host);
  assert.ok(endpoint, 'Use a loopback Firestore Emulator');
  const rules = fs.readFileSync(path.join(__dirname, '../../../firestore.rules'), 'utf8');
  const env = await initializeTestEnvironment({
    projectId: 'demo-innera-clinic-auth-test',
    firestore: { host: '127.0.0.1', port: Number(endpoint[1]), rules },
  });
  try {
    await env.withSecurityRulesDisabled(async context => {
      const db = context.firestore();
      const fixtures = {
        'clinics/a': { status: 'active' },
        'clinics/b': { status: 'active' },
        'clinics/c': { status: 'inactive' },
        'clinicStaff/staffA': { active: true, role: 'admin', clinicId: 'a' },
        'clinicStaff/disabledA': { active: false, status: 'active', role: 'admin', clinicId: 'a' },
        'clinicStaff/staffC': { active: true, role: 'admin', clinicId: 'c' },
        'inneraPatients/a': { clinicId: 'a' },
        'inneraPatients/b': { clinicId: 'b' },
        'inneraPatients/c': { clinicId: 'c' },
      };
      for (const [key, data] of Object.entries(fixtures)) await setDoc(doc(db, key), data);
    });
    const staff = env.authenticatedContext('staffA').firestore();
    // Positive control for this authenticated context under the current Rules.
    await assertSucceeds(getDoc(doc(staff, 'users/staffA')));
    await assertFails(getDoc(doc(staff, 'inneraPatients/b')));
    await assertFails(updateDoc(doc(staff, 'clinics/a'), { status: 'inactive' }));
    for (const [uid, clinicId] of [['disabledA', 'a'], ['staffC', 'c']]) {
      const db = env.authenticatedContext(uid).firestore();
      await assertFails(getDoc(doc(db, 'inneraPatients/' + clinicId)));
      await assertFails(setDoc(doc(db, 'inneraPatients/new'), { clinicId }));
    }
  } finally {
    await env.cleanup();
  }
});
