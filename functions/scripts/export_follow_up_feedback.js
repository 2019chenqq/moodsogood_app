"use strict";

const fs = require("node:fs");
const { validateFeedback, COLLECTION } = require("../follow_up_feedback");

const columns = ["shownToDoctor", "surfacedForgottenInfo", "hadDeeperDiscussion",
  "doctorRequestedAgain", "submittedAt"];

function buildReport(records) {
  const counts = { total: 0, shownToDoctor: { true: 0, false: 0 },
    surfacedForgottenInfo: { yes: 0, no: 0, unsure: 0 },
    hadDeeperDiscussion: { yes: 0, no: 0, unsure: 0 },
    doctorRequestedAgain: { yes: 0, no: 0, notMentioned: 0 } };
  const rows = [columns.join(",")];
  for (const record of records) {
    // Whitelist codes again: never export unexpected fields or spreadsheet formulas.
    const data = validateFeedback({ summaryId: "export",
      ...Object.fromEntries(columns.slice(0, 4).map((key) => [key, record[key]])) });
    const time = record.submittedAt?.toDate?.() ?? record.submittedAt;
    if (!(time instanceof Date) || !Number.isFinite(time.getTime())) {
      throw new Error("Invalid submittedAt; export stopped.");
    }
    counts.total++;
    counts.shownToDoctor[String(data.shownToDoctor)]++;
    if (data.shownToDoctor) {
      for (const key of columns.slice(1, 4)) counts[key][data[key]]++;
    }
    rows.push(columns.map((key) => key === "submittedAt"
      ? time.toISOString() : data[key] ?? "").join(","));
  }
  const rates = {};
  for (const key of columns.slice(0, 4)) {
    const denominator = key === "shownToDoctor" ? counts.total : counts.shownToDoctor.true;
    rates[key] = { denominator, percent: Object.fromEntries(
      Object.entries(counts[key]).map(([answer, count]) =>
        [answer, denominator ? Math.round(count / denominator * 10000) / 100 : null])) };
  }
  return { csv: "\uFEFF" + rows.join("\r\n") + "\r\n", counts, rates };
}

async function main() {
  const [projectId, output] = process.argv.slice(2);
  if (!projectId || !output || process.argv.length !== 4) {
    throw new Error("Usage: node functions/scripts/export_follow_up_feedback.js PROJECT_ID OUTPUT.csv");
  }
  const admin = require("firebase-admin");
  admin.initializeApp({ projectId, credential: admin.credential.applicationDefault() });
  const db = admin.firestore();
  const records = [];
  let cursor;
  while (true) {
    let query = db.collection(COLLECTION).orderBy(admin.firestore.FieldPath.documentId()).limit(500);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    records.push(...page.docs.map((doc) => doc.data()));
    if (page.size < 500) break;
    cursor = page.docs.at(-1);
  }
  const report = buildReport(records);
  // Never silently overwrite an earlier export.
  fs.writeFileSync(output, report.csv, { encoding: "utf8", flag: "wx" });
  console.log(JSON.stringify({ output, counts: report.counts, rates: report.rates }, null, 2));
}

if (require.main === module) main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
module.exports = { buildReport };
