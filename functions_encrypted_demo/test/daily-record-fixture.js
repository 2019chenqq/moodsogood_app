"use strict";
const date = "2026-10-01T00:00:00.000Z";
module.exports = {
  page: { date, emotions: { "Synthetic-daily-emotion": 3 }, symptoms: ["Synthetic-daily-symptom"], bodySymptoms: ["Synthetic-daily-symptom"],
    stateChanges: { energy_change: 3 }, symptomSectionCompleted: true, emotionSectionCompleted: true, stateSectionCompleted: true,
    overallMood: 3, moodScale: 5, updatedAt: date, createdAt: date, savedAt: date, isPeriod: false, periodStartId: null,
    periodCycleLength: 28, periodNextExpectedStart: null, periodArrivalDeltaDays: null, dailyActivities: null, medicines: null,
    periodData: { isPeriod: false, periodStartId: null, periodEndId: null, cycleLength: 28, nextExpectedStart: null, arrivalDeltaDays: null } },
  confirmation: { date, emotions: [{ name: "Synthetic-daily-emotion", value: 4 }], symptoms: ["Synthetic-daily-symptom"], bodySymptoms: ["Synthetic-daily-symptom"],
    stateChanges: { energy_change: 3 }, symptomSectionCompleted: true, emotionSectionCompleted: true, stateSectionCompleted: true,
    overallMood: 4, moodScale: 5, updatedAt: date,
    bodyMeasurement: { weightKg: 60, bodyFatPercent: 20, waistCm: 75, measuredAt: date, measurementTiming: "afterWaking", customMeasurementTime: null },
    sleep: { sleepTime: "23:00", wakeTime: "07:00", finalWakeTime: "06:50", quality: 4, midWakeList: "Synthetic-daily-sleep", flags: ["synthetic"], naps: [] } },
};
