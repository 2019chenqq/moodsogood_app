

const diarySuggestionSchema = {
  type: "object",
  additionalProperties: false,
  required: ["value", "source", "confidence", "evidence", "reason"],
  properties: {
    value: { type: "string" },
    source: {
      type: "string",
      enum: ["explicit", "summarized", "inferred", "suggested", "missing"],
    },
    confidence: { type: "number", minimum: 0, maximum: 1 },
    evidence: { type: "string" },
    reason: { type: "string" },
  },
};

const diaryExtractionSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "titleSuggestions",
    "content",
    "memorableMomentSuggestions",
    "didWellSuggestions",
    "selfCareSuggestions",
    "gratitudeSuggestions",
    "emotionAnalysis",
    "emotionMetaphorSuggestions",
    "songRecommendationProfile",
    "missingFields",
    "followUpQuestions",
    "safetyRisk",
  ],
  properties: {
    titleSuggestions: {
      type: "array",
      maxItems: 3,
      items: diarySuggestionSchema,
    },
    content: diarySuggestionSchema,
    memorableMomentSuggestions: {
      type: "array",
      maxItems: 3,
      items: diarySuggestionSchema,
    },
    didWellSuggestions: {
      type: "array",
      maxItems: 3,
      items: diarySuggestionSchema,
    },
    selfCareSuggestions: {
      type: "array",
      maxItems: 3,
      items: diarySuggestionSchema,
    },
    gratitudeSuggestions: {
      type: "array",
      maxItems: 3,
      items: diarySuggestionSchema,
    },
    emotionAnalysis: {
      type: "object",
      additionalProperties: false,
      required: [
        "primaryEmotion",
        "secondaryEmotions",
        "valence",
        "energy",
        "intensity",
      ],
      properties: {
        primaryEmotion: { type: "string" },
        secondaryEmotions: {
          type: "array",
          maxItems: 5,
          items: { type: "string" },
        },
        valence: { type: "integer", minimum: 1, maximum: 5 },
        energy: { type: "integer", minimum: 1, maximum: 5 },
        intensity: { type: "integer", minimum: 1, maximum: 5 },
      },
    },
    emotionMetaphorSuggestions: {
      type: "array",
      maxItems: 3,
      items: diarySuggestionSchema,
    },
    songRecommendationProfile: {
      type: "object",
      additionalProperties: false,
      required: [
        "primaryEmotion",
        "secondaryEmotions",
        "desiredEffect",
        "musicTags",
        "searchKeywords",
        "preferredLanguages",
        "energy",
        "valence",
        "avoidThemes",
      ],
      properties: {
        primaryEmotion: { type: "string" },
        secondaryEmotions: {
          type: "array",
          maxItems: 5,
          items: { type: "string" },
        },
        desiredEffect: { type: "string" },
        musicTags: {
          type: "array",
          maxItems: 5,
          items: {
            type: "string",
            enum: [
              "calm",
              "comforting",
              "healing",
              "hopeful",
              "peaceful",
              "uplifting",
              "gentle",
              "reflective",
              "melancholic",
              "energetic",
              "motivational",
            ],
          },
        },
        searchKeywords: {
          type: "array",
          maxItems: 6,
          items: { type: "string" },
        },
        preferredLanguages: {
          type: "array",
          maxItems: 4,
          items: { type: "string" },
        },
        energy: { type: "integer", minimum: 1, maximum: 5 },
        valence: { type: "integer", minimum: 1, maximum: 5 },
        avoidThemes: {
          type: "array",
          maxItems: 10,
          items: { type: "string" },
        },
      },
    },
    missingFields: {
      type: "array",
      maxItems: 8,
      items: { type: "string" },
    },
    followUpQuestions: {
      type: "array",
      maxItems: 3,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["targetField", "question"],
        properties: {
          targetField: { type: "string" },
          question: { type: "string" },
        },
      },
    },
    safetyRisk: {
      type: "object",
      additionalProperties: false,
      required: ["detected", "level", "reason"],
      properties: {
        detected: { type: "boolean" },
        level: {
          type: "string",
          enum: ["none", "low", "medium", "high", "imminent"],
        },
        reason: { type: "string" },
      },
    },
  },
};

module.exports = {
  diaryExtractionSchema,
};
