function normalizeSummaryInput({ messages, eventDrafts, detectSafety }) {
  const normalizedMessages = (Array.isArray(messages) ? messages : [])
    .map((item) => ({
      role: item?.role === "user" ? "user" : "assistant",
      content: String(item?.content || "").trim().slice(0, 1600),
    }))
    .filter((item) => item.content)
    .filter((item) => item.role !== "user" || !detectSafety || !detectSafety(item.content).detected);
  const effectiveMessages = [];
  let messageCharacters = 0;
  for (const item of normalizedMessages.slice().reverse()) {
    if (effectiveMessages.length && messageCharacters + item.content.length > 40000) break;
    effectiveMessages.unshift(item);
    messageCharacters += item.content.length;
  }
  const normalizedDrafts = (Array.isArray(eventDrafts) ? eventDrafts : [])
    .map((item) => {
      const id = String(item?.id || "").trim().slice(0, 240);
      if (!id) return null;
      return {
        id,
        eventTime: item?.eventTime == null ? null : String(item.eventTime).slice(0, 80),
        timeContext: item?.timeContext == null ? null : String(item.timeContext).slice(0, 120),
        timePrecision: ["exact", "approximate", "unspecified"].includes(item?.timePrecision) ? item.timePrecision : "unspecified",
        emotionMentions: Array.isArray(item?.emotionMentions) ? item.emotionMentions.slice(0, 20) : [],
        symptoms: Array.isArray(item?.symptoms) ? item.symptoms.map(String).map((v) => v.trim()).filter(Boolean).slice(0, 20) : [],
        stateChanges: item?.stateChanges && typeof item.stateChanges === "object" ? item.stateChanges : {},
        rawUserEntries: Array.isArray(item?.rawUserEntries) ? item.rawUserEntries.map(String).map((v) => v.trim()).filter(Boolean).slice(0, 20) : [],
        note: String(item?.note || "").trim().slice(0, 1000),
      };
    })
    .filter(Boolean)
    .filter((item, index, items) => items.findIndex((other) => other.id === item.id) === index)
    .slice(0, 20);
  return { messages: effectiveMessages, eventDrafts: normalizedDrafts };
}

function alignEventSummaries(rawSummaries, eventDrafts) {
  const byId = new Map((Array.isArray(rawSummaries) ? rawSummaries : [])
    .map((item) => [String(item?.eventId || "").trim(), String(item?.summary || "").trim().slice(0, 600)])
    .filter(([eventId, summary]) => eventId && summary));
  return eventDrafts.map((draft) => ({
    eventId: draft.id,
    summary: byId.get(draft.id) || draft.note || draft.rawUserEntries.join("，"),
  }));
}

module.exports = { alignEventSummaries, normalizeSummaryInput };
