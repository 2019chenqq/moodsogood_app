const crypto = require("crypto");

const ALLOWED_MUSIC_TAGS = new Set([
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
]);

const UNWANTED_VERSION = /\b(live|karaoke|instrumental|cover|remix|remaster(?:ed)?)\b/i;

function normalizeTrackText(value) {
  return String(value || "")
    .toLowerCase()
    .normalize("NFKC")
    .replace(/\b(feat|ft)\.?\s+.*$/i, "")
    .replace(/\([^)]*(live|karaoke|instrumental|cover|remix|remaster(?:ed)?)[^)]*\)/gi, "")
    .replace(/\[[^\]]*(live|karaoke|instrumental|cover|remix|remaster(?:ed)?)[^\]]*\]/gi, "")
    .replace(/[^\p{L}\p{N}]+/gu, "");
}

function sameTrack(left, right) {
  const leftTitle = normalizeTrackText(left.title);
  const rightTitle = normalizeTrackText(right.title);
  const leftArtist = normalizeTrackText(left.artist);
  const rightArtist = normalizeTrackText(right.artist);
  return Boolean(
    leftTitle &&
      rightTitle &&
      leftArtist &&
      rightArtist &&
      leftTitle === rightTitle &&
      (leftArtist === rightArtist ||
        leftArtist.includes(rightArtist) ||
        rightArtist.includes(leftArtist)),
  );
}

async function fetchJson(url, options = {}, timeoutMs = 12000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    if (response.status === 429) {
      const error = new Error("rate_limit");
      error.status = 429;
      throw error;
    }
    if (!response.ok) {
      const error = new Error(`HTTP ${response.status}`);
      error.status = response.status;
      throw error;
    }
    return await response.json();
  } finally {
    clearTimeout(timer);
  }
}

async function getSpotifyToken(clientId, clientSecret) {
  const encoded = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
  const payload = await fetchJson(
    "https://accounts.spotify.com/api/token",
    {
      method: "POST",
      headers: {
        Authorization: `Basic ${encoded}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: "grant_type=client_credentials",
    },
    12000,
  );
  if (!payload.access_token) throw new Error("Missing Spotify access token");
  return payload.access_token;
}

function spotifyTrack(item, tags = [], discoverySources = 1) {
  return {
    provider: "spotify",
    providerTrackId: String(item?.id || ""),
    title: String(item?.name || "").trim(),
    artist: (item?.artists || [])
      .map((artist) => String(artist?.name || "").trim())
      .filter(Boolean)
      .join(", "),
    album: String(item?.album?.name || "").trim(),
    artworkUrl: String(item?.album?.images?.[0]?.url || "").trim(),
    externalUrl: String(item?.external_urls?.spotify || "").trim(),
    previewUrl: String(item?.preview_url || "").trim(),
    isExplicit: item?.explicit === true,
    isPlayable: item?.is_playable !== false,
    isrc: String(item?.external_ids?.isrc || "").trim(),
    durationMs: Number(item?.duration_ms || 0) || null,
    availableMarkets: Array.isArray(item?.available_markets)
      ? item.available_markets.slice(0, 250)
      : [],
    sourceTags: tags,
    discoverySources,
  };
}

async function spotifySearch(token, query, market = "TW", limit = 5) {
  const params = new URLSearchParams({
    q: query,
    type: "track",
    market,
    limit: String(limit),
  });
  const payload = await fetchJson(
    `https://api.spotify.com/v1/search?${params}`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  return Array.isArray(payload?.tracks?.items) ? payload.tracks.items : [];
}

function musicCacheKey(profile, market) {
  const stable = JSON.stringify({
    tags: profile.musicTags,
    keywords: profile.searchKeywords,
    languages: profile.preferredLanguages,
    market,
    energy: profile.energy,
    valence: profile.valence,
    provider: "spotify",
  });
  return crypto.createHash("sha256").update(stable).digest("hex");
}

module.exports = {
  ALLOWED_MUSIC_TAGS,
  musicCacheKey,
  getSpotifyToken,
  fetchJson,
  UNWANTED_VERSION,
  sameTrack,
  spotifySearch,
  spotifyTrack,
};
