"use strict";

function buildSleepTimeStats(records) {
  const entries = (Array.isArray(records) ? records : [])
    .map((record) => {
      const rawTime = String(record?.sleep?.sleepTime || "").trim();
      const match = /^([01]?\d|2[0-3]):([0-5]\d)$/.exec(rawTime);
      if (!match) return null;
      const hour = Number(match[1]);
      const minute = Number(match[2]);
      const normalizedTime =
        `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
      return {
        date: String(record?.date || "").trim().slice(0, 10),
        sleepTime: normalizedTime,
        adjustedMinutes:
          hour < 6 ? hour * 60 + minute + 1440 : hour * 60 + minute,
      };
    })
    .filter(Boolean)
    .sort((left, right) => left.date.localeCompare(right.date));
  const adjustedTimes = entries
    .map((entry) => entry.adjustedMinutes)
    .sort((left, right) => left - right);
  const formatAdjustedTime = (value) => {
    if (!Number.isFinite(value)) return null;
    const rounded = Math.round(value) % 1440;
    return `${String(Math.floor(rounded / 60)).padStart(2, "0")}:${String(rounded % 60).padStart(2, "0")}`;
  };
  const middle = Math.floor(adjustedTimes.length / 2);
  const median =
    adjustedTimes.length === 0
      ? null
      : adjustedTimes.length % 2 === 1
        ? adjustedTimes[middle]
        : (adjustedTimes[middle - 1] + adjustedTimes[middle]) / 2;
  const afterMidnightEntries = entries.filter(
    (entry) => entry.adjustedMinutes >= 1440,
  );
  return {
    validSleepTimeDays: entries.length,
    typicalSleepTime: formatAdjustedTime(median),
    earliestSleepTime: formatAdjustedTime(adjustedTimes[0]),
    latestSleepTime: formatAdjustedTime(adjustedTimes.at(-1)),
    afterMidnightSleepDays: afterMidnightEntries.length,
    frequentAfterMidnightSleep:
      entries.length >= 2 && afterMidnightEntries.length * 2 >= entries.length,
    afterMidnightSleepDates: afterMidnightEntries
      .map((entry) => entry.date)
      .filter(Boolean),
    bedtimeEvidence: entries.map(({ date, sleepTime }) => ({ date, sleepTime })),
  };
}

module.exports = { buildSleepTimeStats };
