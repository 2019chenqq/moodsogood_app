const { onCall, HttpsError } = require("firebase-functions/v2/https");
const {
  openAiApiKey,
  lastFmApiKey,
  spotifyClientId,
  spotifyClientSecret,
  revenueCatSecretApiKey,
  DEFAULT_AI_MODEL,
} = require("../config/params");
const { requireAiProAccess, requireAiCapacity } = require("../ai/access");
const {
  ALLOWED_MUSIC_TAGS,
  musicCacheKey,
  getSpotifyToken,
  fetchJson,
  UNWANTED_VERSION,
  sameTrack,
  spotifySearch,
  spotifyTrack,
} = require("./provider");
const { db, admin } = require("../config/firebase");
const { createAiUsageTracker, AI_QUOTED_POINTS } = require("../ai/ai_usage");
const OpenAI = require("openai");
const { stripMarkdownFence } = require("../shared/normalization");

exports.recommendInneraSongs = onCall(
  {
    secrets: [
      openAiApiKey,
      lastFmApiKey,
      spotifyClientId,
      spotifyClientSecret,
      revenueCatSecretApiKey,
    ],
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "請先登入後再取得歌曲推薦");
    }
    await requireAiProAccess(request.auth.uid);
    const raw = request.data?.profile;
    const profile = raw && typeof raw === "object" ? raw : {};
    const musicTags = (Array.isArray(profile.musicTags) ? profile.musicTags : [])
      .map((item) => String(item || "").trim().toLowerCase())
      .filter((item) => ALLOWED_MUSIC_TAGS.has(item))
      .slice(0, 4);
    const searchKeywords = (
      Array.isArray(profile.searchKeywords) ? profile.searchKeywords : []
    )
      .map((item) => String(item || "").trim().slice(0, 80))
      .filter(Boolean)
      .slice(0, 6);
    const preferredLanguages = (
      Array.isArray(profile.preferredLanguages)
        ? profile.preferredLanguages
        : []
    )
      .map((item) => String(item || "").trim().slice(0, 16))
      .filter(Boolean)
      .slice(0, 4);
    const avoidThemes = (
      Array.isArray(profile.avoidThemes) ? profile.avoidThemes : []
    )
      .map((item) => String(item || "").trim().toLowerCase())
      .filter(Boolean)
      .slice(0, 12);
    const market = String(request.data?.market || "TW")
      .trim()
      .toUpperCase()
      .slice(0, 2);
    if (musicTags.length === 0 && searchKeywords.length === 0) {
      return { recommendations: [], error: "missing_search_profile" };
    }

    await requireAiCapacity(request.auth.uid, "song_recommendation");
    const cacheProfile = {
      musicTags,
      searchKeywords,
      preferredLanguages,
      energy: Number(profile.energy || 3),
      valence: Number(profile.valence || 3),
    };
    const cacheKey = musicCacheKey(cacheProfile, market);
    const cacheRef = db.collection("musicRecommendationCache").doc(cacheKey);
    const cached = await cacheRef.get();
    const cachedData = cached.data();
    if (
      cachedData?.expiresAt?.toMillis &&
      cachedData.expiresAt.toMillis() > Date.now() &&
      Array.isArray(cachedData.recommendations)
    ) {
      return {
        recommendations: cachedData.recommendations,
        cached: true,
      };
    }

    const lastFmKey = lastFmApiKey.value();
    const spotifyId = spotifyClientId.value();
    const spotifySecret = spotifyClientSecret.value();
    if (!lastFmKey || !spotifyId || !spotifySecret) {
      return { recommendations: [], error: "music_service_not_configured" };
    }

    try {
      const spotifyToken = await getSpotifyToken(spotifyId, spotifySecret);
      const discovered = [];
      const lastFmResults = await Promise.allSettled(
        musicTags.map(async (tag) => {
          const params = new URLSearchParams({
            method: "tag.gettoptracks",
            tag,
            api_key: lastFmKey,
            format: "json",
            limit: "15",
          });
          const payload = await fetchJson(
            `https://ws.audioscrobbler.com/2.0/?${params}`,
          );
          return (payload?.tracks?.track || []).map((track) => ({
            title: String(track?.name || "").trim(),
            artist: String(track?.artist?.name || "").trim(),
            sourceTags: [tag],
            musicBrainzId: String(track?.mbid || "").trim(),
          }));
        }),
      );
      for (const result of lastFmResults) {
        if (result.status !== "fulfilled") continue;
        for (const track of result.value) {
          if (!track.title || !track.artist || UNWANTED_VERSION.test(track.title)) {
            continue;
          }
          const existing = discovered.find((item) => sameTrack(item, track));
          if (existing) {
            existing.sourceTags = [
              ...new Set([...existing.sourceTags, ...track.sourceTags]),
            ];
            existing.discoverySources += 1;
          } else {
            discovered.push({ ...track, discoverySources: 1 });
          }
        }
      }

      const verified = [];
      for (const candidate of discovered.slice(0, 20)) {
        const results = await spotifySearch(
          spotifyToken,
          `track:${candidate.title} artist:${candidate.artist}`,
          market,
          5,
        );
        const matched = results.find((item) =>
          sameTrack(candidate, {
            title: item?.name,
            artist: item?.artists?.[0]?.name,
          }),
        );
        if (!matched || UNWANTED_VERSION.test(matched.name || "")) continue;
        verified.push(
          spotifyTrack(
            matched,
            candidate.sourceTags,
            candidate.discoverySources,
          ),
        );
      }

      if (
        verified.length < 5 ||
        (preferredLanguages.some((item) => item.startsWith("zh")) &&
          !verified.some((item) =>
            /[\u3400-\u9fff]/u.test(`${item.title}${item.artist}`),
          ))
      ) {
        const fallbackQueries = [
          ...searchKeywords,
          ...(preferredLanguages.some((item) => item.startsWith("zh"))
            ? ["華語療癒", "Mandarin comforting", "Mandarin healing"]
            : []),
        ].slice(0, 8);
        for (const keyword of fallbackQueries) {
          const results = await spotifySearch(
            spotifyToken,
            keyword,
            market,
            3,
          );
          for (const item of results) {
            if (UNWANTED_VERSION.test(item?.name || "")) continue;
            const track = spotifyTrack(item, [], 1);
            if (!verified.some((existing) => sameTrack(existing, track))) {
              verified.push(track);
            }
          }
        }
      }

      const ranked = verified
        .filter((track) => {
          const text = `${track.title} ${track.artist}`.toLowerCase();
          return (
            track.providerTrackId &&
            track.externalUrl &&
            track.isPlayable &&
            !avoidThemes.some((theme) => theme && text.includes(theme))
          );
        })
        .map((track) => {
          const languageMatch =
            preferredLanguages.some((item) => item.startsWith("zh")) &&
            /[\u3400-\u9fff]/u.test(`${track.title}${track.artist}`);
          const score =
            track.sourceTags.length * 4 +
            Math.max(0, track.discoverySources - 1) * 2 +
            (languageMatch ? 3 : 0) +
            (track.externalUrl ? 1 : 0) +
            (track.artworkUrl ? 1 : 0) -
            (track.isExplicit ? 5 : 0);
          return { ...track, rankingScore: score };
        })
        .sort((a, b) => b.rankingScore - a.rankingScore)
        .slice(0, 10);

      if (ranked.length === 0) {
        return { recommendations: [], error: "no_verified_tracks" };
      }
      const candidates = ranked.map((track, index) => ({
        candidateId: `candidate_${String(index + 1).padStart(2, "0")}`,
        title: track.title,
        artist: track.artist,
        tags: track.sourceTags,
        provider: track.provider,
      }));
      let selected = [];
      let selection;
      const usageTracker = createAiUsageTracker({
        db,
        admin,
        uid: request.auth.uid,
        requestId: request.data?.requestId,
        feature: "song_recommendation",
        model: DEFAULT_AI_MODEL,
        promptVersion: "song_selection_v1",
        quotedPoints: AI_QUOTED_POINTS.song_recommendation,
      });
      await usageTracker.start();
      try {
        const ai = new OpenAI({ apiKey: openAiApiKey.value() });
        selection = await ai.chat.completions.create({
          model: DEFAULT_AI_MODEL,
          temperature: 0.2,
          response_format: {
            type: "json_schema",
            json_schema: {
              name: "innera_song_selection",
              strict: true,
              schema: {
                type: "object",
                additionalProperties: false,
                required: ["recommendations"],
                properties: {
                  recommendations: {
                    type: "array",
                    maxItems: 3,
                    items: {
                      type: "object",
                      additionalProperties: false,
                      required: ["candidateId", "reason"],
                      properties: {
                        candidateId: { type: "string" },
                        reason: { type: "string" },
                      },
                    },
                  },
                },
              },
            },
          },
          messages: [
            {
              role: "system",
              content: [
                "只能從 candidates 選最多三首，以 candidateId 回覆。",
                "不得新增或修改歌名、歌手、平台 ID 或連結。",
                "不要聲稱知道未提供的歌詞；理由只能描述推薦情境與整體陪伴方向。",
                "使用繁體中文，每個理由一至兩句。",
              ].join("\n"),
            },
            {
              role: "user",
              content: JSON.stringify({
                profile: {
                  primaryEmotion: String(profile.primaryEmotion || ""),
                  desiredEffect: String(profile.desiredEffect || ""),
                  preferredLanguages,
                },
                candidates,
              }),
            },
          ],
        });
        const parsed = JSON.parse(
          stripMarkdownFence(selection.choices?.[0]?.message?.content || ""),
        );
        selected = (Array.isArray(parsed.recommendations)
          ? parsed.recommendations
          : []
        ).filter((item) =>
          candidates.some(
            (candidate) => candidate.candidateId === item.candidateId,
          ),
        );
        await usageTracker.succeed(selection);
      } catch (error) {
        await usageTracker.fail(error, selection);
        console.warn("Song AI selection failed; using ranked verified tracks", {
          message: error?.message,
        });
      }
      if (selected.length === 0) {
        selected = candidates.slice(0, 3).map((candidate) => ({
          candidateId: candidate.candidateId,
          reason: "這首已由音樂平台驗證，整體標籤較接近今天想被陪伴的方向。",
        }));
      }
      const recommendations = selected
        .map((choice) => {
          const index = candidates.findIndex(
            (candidate) => candidate.candidateId === choice.candidateId,
          );
          if (index < 0) return null;
          return {
            ...ranked[index],
            candidateId: choice.candidateId,
            reason: String(choice.reason || "").trim().slice(0, 300),
          };
        })
        .filter(Boolean)
        .slice(0, 3);
      await cacheRef.set({
        recommendations,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromMillis(
          Date.now() + 12 * 60 * 60 * 1000,
        ),
      });
      return { recommendations, cached: false };
    } catch (error) {
      console.error("recommendInneraSongs failed", {
        message: error?.message,
        status: error?.status,
      });
      return {
        recommendations: [],
        error: error?.status === 429 ? "rate_limit" : "music_service_failed",
      };
    }
  },
);

exports.searchInneraSongs = onCall(
  {
    secrets: [spotifyClientId, spotifyClientSecret, revenueCatSecretApiKey],
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "請先登入後再搜尋歌曲");
    }
    await requireAiProAccess(request.auth.uid);
    const query = String(request.data?.query || "").trim().slice(0, 120);
    const market = String(request.data?.market || "TW")
      .trim()
      .toUpperCase()
      .slice(0, 2);
    if (!query) {
      throw new HttpsError("invalid-argument", "請輸入歌名、歌手或關鍵字");
    }
    await requireAiCapacity(request.auth.uid, "music_search");
    const clientId = spotifyClientId.value();
    const clientSecret = spotifyClientSecret.value();
    if (!clientId || !clientSecret) {
      return { tracks: [], error: "music_service_not_configured" };
    }
    try {
      const token = await getSpotifyToken(clientId, clientSecret);
      const results = await spotifySearch(token, query, market, 10);
      const seen = new Set();
      const tracks = results
        .filter((item) => !UNWANTED_VERSION.test(item?.name || ""))
        .map((item, index) => ({
          ...spotifyTrack(item),
          candidateId: `search_${String(index + 1).padStart(2, "0")}`,
          reason: "你自行搜尋並選擇的 Spotify 目錄結果。",
        }))
        .filter((item) => {
          if (!item.providerTrackId || seen.has(item.providerTrackId)) {
            return false;
          }
          seen.add(item.providerTrackId);
          return true;
        });
      return { tracks };
    } catch (error) {
      console.error("searchInneraSongs failed", {
        message: error?.message,
        status: error?.status,
      });
      return {
        tracks: [],
        error: error?.status === 429 ? "rate_limit" : "music_service_failed",
      };
    }
  },
);
