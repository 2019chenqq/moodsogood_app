const { db } = require("../config/firebase");

function isStaffActive(staff) {
  return !!staff && staff.active !== false &&
    (staff.status === undefined || staff.status === "active") &&
    (staff.active === true || staff.status === "active");
}

async function isClinicActive(clinicId, reader = db) {
  if (typeof clinicId !== "string" || !clinicId || clinicId.includes("/")) return false;
  const ref = db.collection("clinics").doc(clinicId);
  const snap = reader === db ? await ref.get() : await reader.get(ref);
  return snap.exists && snap.data().status === "active";
}

async function allowsPatientInvite(clinicId, reader = db) {
  if (!await isClinicActive(clinicId, reader)) return false;
  const ref = db.collection("clinics").doc(clinicId);
  const snap = reader === db ? await ref.get() : await reader.get(ref);
  // Preserve the existing default for clinics created before this setting.
  return (snap.data().allowPatientInvite ?? true) === true;
}

module.exports = { isStaffActive, isClinicActive, allowsPatientInvite };
