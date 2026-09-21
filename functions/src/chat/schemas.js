const { createPhysicalHealthChatSchema } = require("./innera_physical_health");

const nullableStringSchema = {
  anyOf: [{ type: "string" }, { type: "null" }],
};

const nullableScoreSchema = {
  anyOf: [
    { type: "integer", minimum: 1, maximum: 5 },
    { type: "null" },
  ],
};

const inneraChatSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "reply",
    "followUpQuestion",
    "sources",
    "suggestedActions",
    "recordDraft",
    "eventDrafts",
    "safetyLevel",
    "requiresFixedSafetyUi",
  ],
  properties: {
    reply: { type: "string" },
    followUpQuestion: nullableStringSchema,
    sources: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["label", "dateRange", "count"],
        properties: {
          label: { type: "string" },
          dateRange: { type: "string" },
          count: { type: "integer" },
        },
      },
    },
    suggestedActions: {
      type: "array",
      maxItems: 4,
      items: { type: "string" },
    },
    recordDraft: {
      type: "object",
      additionalProperties: false,
      required: [
        "date",
        "moodScale",
        "overallMood",
        "emotionMentions",
        "symptoms",
        "stateChanges",
        "bodyMeasurement",
        "sleep",
        "events",
        "diaryText",
        "missingFields",
      ],
      properties: {
        date: { type: "string" },
        moodScale: { type: "integer", enum: [5] },
        overallMood: nullableScoreSchema,
        emotionMentions: {
          type: "array",
          maxItems: 20,
          items: {
            type: "object",
            additionalProperties: false,
            required: [
              "rawText",
              "normalizedDimensionId",
              "normalizedDimensionName",
              "value",
              "mentioned",
              "source",
              "needsFollowUp",
              "needsConfirmation",
              "confidence",
              "timeContext",
              "evidence",
              "subjectType",
              "subjectText",
              "isQuotedSpeech",
            ],
            properties: {
              rawText: { type: "string" },
              normalizedDimensionId: nullableStringSchema,
              normalizedDimensionName: nullableStringSchema,
              value: nullableScoreSchema,
              mentioned: { type: "boolean" },
              source: {
                type: "string",
                enum: ["explicit", "summarized", "inferred"],
              },
              needsFollowUp: { type: "boolean" },
              needsConfirmation: { type: "boolean" },
              confidence: { type: "number", minimum: 0, maximum: 1 },
              timeContext: nullableStringSchema,
              evidence: { type: "string" },
              subjectType: {
                type: "string",
                enum: ["user", "other", "shared", "unknown"],
              },
              subjectText: nullableStringSchema,
              isQuotedSpeech: { type: "boolean" },
            },
          },
        },
        symptoms: {
          type: "array",
          maxItems: 30,
          items: {
            type: "object",
            additionalProperties: false,
            required: ["name", "source"],
            properties: {
              name: { type: "string" },
              source: {
                type: "string",
                enum: ["explicit", "summarized", "inferred"],
              },
            },
          },
        },
        stateChanges: {
          type: "object",
          additionalProperties: false,
          required: ["energy_change", "appetite_change", "activity_change"],
          properties: {
            energy_change: nullableScoreSchema,
            appetite_change: nullableScoreSchema,
            activity_change: nullableScoreSchema,
          },
        },
        bodyMeasurement: {
          type: "object",
          additionalProperties: false,
          required: ["weightKg", "bodyFatPercent", "waistCm", "measurementTiming", "customMeasurementTime"],
          properties: {
            weightKg: { anyOf: [{ type: "number" }, { type: "null" }] },
            bodyFatPercent: { anyOf: [{ type: "number" }, { type: "null" }] },
            waistCm: { anyOf: [{ type: "number" }, { type: "null" }] },
            measurementTiming: {
              anyOf: [
                { type: "string", enum: ["afterWaking", "afterBreakfast", "afterLunch", "afterDinner", "beforeSleep", "other"] },
                { type: "null" },
              ],
            },
            customMeasurementTime: nullableStringSchema,
          },
        },
        sleep: {
          type: "object",
          additionalProperties: false,
          required: [
            "sleepTime",
            "wakeTime",
            "finalWakeTime",
            "quality",
            "midWakeList",
            "flags",
            "naps",
          ],
          properties: {
            sleepTime: nullableStringSchema,
            wakeTime: {
              ...nullableStringSchema,
              description: "離床活動時刻：起床、離床、下床開始活動。不是睜眼甦醒時刻。",
            },
            finalWakeTime: {
              ...nullableStringSchema,
              description: "甦醒時刻：醒來、醒著、睜眼、清醒。不是起床離床時刻。",
            },
            quality: nullableScoreSchema,
            midWakeList: nullableStringSchema,
            flags: {
              type: "array",
              items: {
                type: "string",
                enum: [
                  "good",
                  "ok",
                  "earlyWake",
                  "dreams",
                  "lightSleep",
                  "fragmented",
                  "insufficient",
                  "initInsomnia",
                  "interrupted",
                  "nocturia",
                ],
              },
            },
            naps: {
              type: "array",
              maxItems: 6,
              items: {
                type: "object",
                additionalProperties: false,
                required: ["startTime", "endTime", "durationMinutes"],
                properties: {
                  startTime: nullableStringSchema,
                  endTime: nullableStringSchema,
                  durationMinutes: {
                    anyOf: [{ type: "integer" }, { type: "null" }],
                  },
                },
              },
            },
          },
        },
        events: {
          type: "array",
          maxItems: 12,
          items: { type: "string" },
        },
        diaryText: { type: "string" },
        missingFields: {
          type: "array",
          maxItems: 20,
          items: { type: "string" },
        },
      },
    },
    eventDrafts: {
      type: "array",
      maxItems: 20,
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "id",
          "eventTime",
          "timeContext",
          "timePrecision",
          "emotionMentions",
          "symptoms",
          "stateChanges",
          "rawUserEntries",
          "note",
        ],
        properties: {
          id: { type: "string" },
          eventTime: nullableStringSchema,
          timeContext: nullableStringSchema,
          timePrecision: {
            type: "string",
            enum: ["exact", "approximate", "unspecified"],
          },
          emotionMentions: {
            type: "array",
            maxItems: 20,
            items: {
              type: "object",
              additionalProperties: false,
              required: ["rawText", "normalizedDimensionId", "normalizedDimensionName", "value"],
              properties: {
                rawText: { type: "string" },
                normalizedDimensionId: nullableStringSchema,
                normalizedDimensionName: nullableStringSchema,
                value: nullableScoreSchema,
              },
            },
          },
          symptoms: {
            type: "array",
            maxItems: 20,
            items: {
              type: "object",
              additionalProperties: false,
              required: ["name", "severity"],
              properties: {
                name: { type: "string" },
                severity: nullableScoreSchema,
              },
            },
          },
          stateChanges: {
            type: "object",
            additionalProperties: false,
            required: ["energy_change", "appetite_change", "activity_change"],
            properties: {
              energy_change: nullableScoreSchema,
              appetite_change: nullableScoreSchema,
              activity_change: nullableScoreSchema,
            },
          },
          rawUserEntries: {
            type: "array",
            maxItems: 20,
            items: { type: "string" },
          },
          note: { type: "string" },
        },
      },
    },
    safetyLevel: {
      type: "string",
      enum: [
        "normal",
        "possibleSelfHarm",
        "imminentDanger",
        "medicalUrgency",
      ],
    },
    requiresFixedSafetyUi: { type: "boolean" },
  },
};

const physicalHealthChatSchema = createPhysicalHealthChatSchema(
  inneraChatSchema.properties.eventDrafts,
);

const followUpQuestionsSchema = {
  type: "object",
  additionalProperties: false,
  required: ["questions"],
  properties: {
    questions: {
      type: "array",
      maxItems: 4,
      items: { type: "string" },
    },
  },
};

const followUpSummarySchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "keyChanges",
    "discussionItems",
    "userSharedNotes",
    "dataLimitations",
    "diaryHighlights",
  ],
  properties: {
    keyChanges: {
      type: "array",
      minItems: 3,
      maxItems: 5,
      items: { type: "string" },
    },
    discussionItems: {
      type: "array",
      maxItems: 5,
      items: { type: "string" },
    },
    userSharedNotes: { type: "array", items: { type: "string" } },
    dataLimitations: { type: "array", items: { type: "string" } },
    diaryHighlights: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["date", "category", "summary", "source"],
        properties: {
          date: { type: "string" },
          category: {
            type: "string",
            enum: [
              "life_event",
              "subjective_feeling",
              "sleep_note",
              "symptom_note",
              "share_with_doctor",
            ],
          },
          summary: { type: "string" },
          source: { type: "string", enum: ["diary"] },
        },
      },
    },
  },
};

module.exports = {
  followUpQuestionsSchema,
  followUpSummarySchema,
  inneraChatSchema,
  physicalHealthChatSchema,
};
