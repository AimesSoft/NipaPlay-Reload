import { normalizeBaseUrl } from "./hosts.js";

async function fetchJson(url, options = {}) {
  const response = await fetch(url, {
    headers: {
      Accept: "application/json",
      ...(options.headers || {}),
    },
    ...options,
  });

  if (!response.ok) {
    const text = await response.text();
    const error = new Error(text || `HTTP ${response.status}`);
    error.status = response.status;
    throw error;
  }

  return response.json();
}

export function buildImageProxyUrl(baseUrl, imageUrl) {
  if (!imageUrl) return "";
  try {
    const encoded = btoa(unescape(encodeURIComponent(imageUrl)));
    return `${baseUrl}/api/image_proxy?url=${encoded}`;
  } catch {
    return imageUrl;
  }
}

export async function getServerInfo(baseUrl) {
  return fetchJson(`${baseUrl}/api/info`);
}

export async function getSharedAnimes(baseUrl) {
  return fetchJson(`${baseUrl}/api/media/local/share/animes`);
}

export async function getSharedAnimeEpisodes(baseUrl, animeId) {
  return fetchJson(`${baseUrl}/api/media/local/share/animes/${animeId}`);
}

export async function getManagementFolders(baseUrl) {
  return fetchJson(`${baseUrl}/api/media/local/manage/folders`);
}

export async function getScanStatus(baseUrl) {
  return fetchJson(`${baseUrl}/api/media/local/manage/scan/status`);
}

export async function browseRemoteDirectory(baseUrl, path) {
  const url = new URL(`${baseUrl}/api/media/local/manage/browse`);
  url.searchParams.set("path", path);
  return fetchJson(url.toString());
}

export async function addRemoteFolder(baseUrl, payload) {
  return fetchJson(`${baseUrl}/api/media/local/manage/folders`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
}

export async function removeRemoteFolder(baseUrl, path) {
  const url = new URL(`${baseUrl}/api/media/local/manage/folders`);
  url.searchParams.set("path", path);
  return fetchJson(url.toString(), {
    method: "DELETE",
  });
}

export async function rescanRemote(baseUrl, payload) {
  return fetchJson(`${baseUrl}/api/media/local/manage/scan/rescan`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
}

export async function getDanmaku(baseUrl, episodeId, animeId) {
  const url = new URL(`${baseUrl}/api/danmaku/load`);
  url.searchParams.set("episodeId", episodeId);
  url.searchParams.set("animeId", String(animeId));
  return fetchJson(url.toString());
}

export async function sendDanmaku(baseUrl, payload) {
  return fetchJson(`${baseUrl}/api/dandanplay/send_danmaku`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
}

export function normalizeUrl(input) {
  return normalizeBaseUrl(input);
}

export function buildStreamUrl(baseUrl, streamPath) {
  if (!streamPath) return "";
  try {
    const base = new URL(`${baseUrl}/`);
    const path = streamPath.startsWith("/") ? streamPath.slice(1) : streamPath;
    return new URL(path, base).toString();
  } catch {
    return `${baseUrl}/${streamPath.replace(/^\/+/, "")}`;
  }
}

export function buildManageStreamUrl(baseUrl, path) {
  const url = new URL(`${baseUrl}/api/media/local/manage/stream`);
  url.searchParams.set("path", path);
  return url.toString();
}
