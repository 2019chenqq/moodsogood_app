"use strict";

const {
  createClinicPatient,
  updateClinicPatientAppointment,
} = require("./src/clinic/patients");

const {
  createClinicInvite,
} = require("./src/clinic/invites");

exports.createClinicPatient = createClinicPatient;

exports.updateClinicPatientAppointment =
  updateClinicPatientAppointment;

exports.createClinicInvite = createClinicInvite;

const {
  createStaffInvite,
  listPendingStaffInvites,
  resendStaffInvite,
  revokeStaffInvite,
  getStaffInvite,
  getStaffInviteActivationEmail,
  acceptStaffInvite,
} = require("./src/clinic/staff_invites");

exports.createStaffInvite = createStaffInvite;
exports.listPendingStaffInvites = listPendingStaffInvites;
exports.resendStaffInvite = resendStaffInvite;
exports.revokeStaffInvite = revokeStaffInvite;
exports.getStaffInvite = getStaffInvite;
exports.getStaffInviteActivationEmail = getStaffInviteActivationEmail;
exports.acceptStaffInvite = acceptStaffInvite;

const {
  updateClinicStaffRole,
  disableClinicStaff,
  enableClinicStaff,
} = require("./src/clinic/staff");

exports.updateClinicStaffRole = updateClinicStaffRole;
exports.disableClinicStaff = disableClinicStaff;
exports.enableClinicStaff = enableClinicStaff;

const {
  listClinicAuditLogs,
} = require("./src/clinic/audit");

exports.listClinicAuditLogs =
  listClinicAuditLogs;

const {
  createClinic,
  resendInitialAdminInvite,
  setClinicStatus,
} = require("./src/clinic/clinics");

exports.createClinic = createClinic;
exports.getClinicDetails = require("./src/clinic/clinics").getClinicDetails;
exports.updateClinicOperations = require("./src/clinic/clinics").updateClinicOperations;
exports.updateClinicTrial = require("./src/clinic/clinics").updateClinicTrial;
exports.resendInitialAdminInvite = resendInitialAdminInvite;
exports.setClinicStatus = setClinicStatus;
