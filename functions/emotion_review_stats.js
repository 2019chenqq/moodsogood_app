"use strict";

function buildEmotionStats(records) {
  const byEmotion = new Map();
  let daysWithEmotionData = 0;

  for (const [index, record] of (Array.isArray(records) ? records : []).entries()) {
    const rawEmotions = record?.emotions;
    const entries = Array.isArray(rawEmotions)
      ? rawEmotions
      : rawEmotions && typeof rawEmotions === "object"
        ? Object.entries(rawEmotions).map(([name, value]) => ({ name, value }))
        : [];
    const emotionsForDay = new Map();
    for (const item of entries) {
      const name = String(item?.name || "").trim().slice(0, 80);
      if (!name || name === "整體情緒" || name === "overall") continue;
      const numericValue = Number(item?.value);
      const value =
        Number.isFinite(numericValue) && numericValue >= 1 && numericValue <= 5
          ? numericValue
          : null;
      const previous = emotionsForDay.get(name);
      emotionsForDay.set(
        name,
        value == null
          ? previous ?? null
          : previous == null
            ? value
            : Math.max(previous, value),
      );
    }
    if (emotionsForDay.size === 0) continue;
    daysWithEmotionData++;
    const date = String(record?.date || "").trim().slice(0, 10);
    const dayKey = date || `record-${index}`;
    for (const [name, value] of emotionsForDay.entries()) {
      const stats = byEmotion.get(name) || {
        name,
        dayKeys: new Set(),
        dates: new Set(),
        intensitySamples: [],
      };
      stats.dayKeys.add(dayKey);
      if (date) stats.dates.add(date);
      if (value != null) stats.intensitySamples.push(value);
      byEmotion.set(name, stats);
    }
  }

  const emotions = [...byEmotion.values()]
    .map((stats) => {
      const averageIntensity =
        stats.intensitySamples.length === 0
          ? null
          : Math.round(
              (stats.intensitySamples.reduce((sum, value) => sum + value, 0) /
                stats.intensitySamples.length) *
                10,
            ) / 10;
      const occurrenceDays = stats.dayKeys.size;
      return {
        name: stats.name,
        occurrenceDays,
        occurrenceRate:
          daysWithEmotionData === 0
            ? 0
            : Math.round((occurrenceDays / daysWithEmotionData) * 1000) / 1000,
        frequent:
          daysWithEmotionData >= 2 && occurrenceDays * 2 >= daysWithEmotionData,
        dates: [...stats.dates].sort(),
        averageIntensity,
        intensitySamples: stats.intensitySamples,
      };
    })
    .sort(
      (left, right) =>
        right.occurrenceDays - left.occurrenceDays ||
        (right.averageIntensity ?? 0) - (left.averageIntensity ?? 0) ||
        left.name.localeCompare(right.name),
    );
  const highestOccurrence = emotions[0]?.occurrenceDays ?? 0;

  return {
    daysWithEmotionData,
    mostFrequentEmotions: emotions
      .filter((item) => item.occurrenceDays === highestOccurrence)
      .map((item) => item.name),
    emotions,
  };
}

module.exports = { buildEmotionStats };
