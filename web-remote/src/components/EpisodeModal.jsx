import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  IoCheckmarkCircle,
  IoCloudOutline,
  IoClose,
  IoDocumentTextOutline,
  IoFilmOutline,
  IoPlayCircleOutline,
  IoStar,
  IoStarHalf,
  IoStarOutline,
  IoSwapVerticalOutline,
} from "react-icons/io5";
import {
  buildImageProxyUrl,
  buildStreamUrl,
  getBangumiDetail,
  getSharedAnimeEpisodes,
} from "../lib/api.js";

const RATING_EVALUATION = {
  1: "不忍直视",
  2: "很差",
  3: "差",
  4: "较差",
  5: "不过不失",
  6: "还行",
  7: "推荐",
  8: "力荐",
  9: "神作",
  10: "超神作",
};

const EPISODE_NUMBER_MAX = 300;
const EPISODE_NUMBER_PATTERNS = [
  /第\s*(\d{1,3})\s*[话話集期]/,
  /\bS\d{1,2}E(\d{1,3})\b/i,
  /\b(?:EP|Ep|ep)\s*(\d{1,3})\b/,
  /\bE(\d{1,3})\b/i,
  /[\[【](\d{1,3})[\]】]/,
];
const EPISODE_NUMBER_IGNORE = new Set([264, 265, 480, 720, 1080, 2160]);

function isValidEpisodeNumber(value) {
  return (
    Number.isInteger(value) &&
    value > 0 &&
    value <= EPISODE_NUMBER_MAX &&
    !EPISODE_NUMBER_IGNORE.has(value)
  );
}

function extractEpisodeNumber(text) {
  if (!text) return null;
  const base = String(text).trim();
  if (!base) return null;
  for (const pattern of EPISODE_NUMBER_PATTERNS) {
    const match = base.match(pattern);
    if (!match) continue;
    const parsed = Number.parseInt(match[1], 10);
    if (isValidEpisodeNumber(parsed)) return parsed;
  }
  let candidate = null;
  for (const match of base.matchAll(/\d{1,4}/g)) {
    const parsed = Number.parseInt(match[0], 10);
    if (!isValidEpisodeNumber(parsed)) continue;
    candidate = parsed;
  }
  return candidate;
}

function compareEpisodes(a, b) {
  const aNumber = a.episodeNumber;
  const bNumber = b.episodeNumber;
  if (aNumber != null && bNumber != null && aNumber !== bNumber) {
    return aNumber - bNumber;
  }
  if (aNumber != null && bNumber == null) return -1;
  if (aNumber == null && bNumber != null) return 1;
  const aText = (a.title || a.fileName || "").trim();
  const bText = (b.title || b.fileName || "").trim();
  const textCompare = aText.localeCompare(bText, undefined, {
    numeric: true,
    sensitivity: "base",
  });
  if (textCompare !== 0) return textCompare;
  return (a._index ?? 0) - (b._index ?? 0);
}

function normalizeEpisodes(payload) {
  const raw = (payload?.data?.episodes ?? payload?.episodes ?? []).map((item) => ({
    shareId: item.shareId,
    title: item.title || "未命名剧集",
    fileName: item.fileName,
    streamPath: item.streamPath,
    fileExists: item.fileExists !== false,
    animeId: item.animeId,
    episodeId: item.episodeId,
    progress: item.progress,
    duration: item.duration,
    lastPosition: item.lastPosition,
  }));
  return raw
    .map((episode, index) => ({
      ...episode,
      episodeNumber:
        extractEpisodeNumber(episode.title) ?? extractEpisodeNumber(episode.fileName),
      _index: index,
    }))
    .sort(compareEpisodes);
}

function normalizeSharedAnime(data, baseUrl) {
  if (!data) return null;
  return {
    id: data.animeId ?? data.id,
    name: data.name || "",
    nameCn: data.nameCn || data.name_cn || data.name || "",
    summary: data.summary || "",
    imageUrl: data.imageUrl ? buildImageProxyUrl(baseUrl, data.imageUrl) : "",
    rating: data.rating,
    ratingDetails: data.ratingDetails,
    tags: Array.isArray(data.tags) ? data.tags : [],
    metadata: Array.isArray(data.metadata) ? data.metadata : [],
    titles: Array.isArray(data.titles) ? data.titles : [],
    airDate: data.airDate || data.air_date || "",
    airWeekday: data.airWeekday ?? data.airDay ?? null,
    totalEpisodes: data.totalEpisodes ?? null,
    typeDescription: data.typeDescription ?? null,
    isOnAir: data.isOnAir ?? null,
    isNSFW: data.isNSFW ?? null,
    bangumiUrl: data.bangumiUrl ?? null,
  };
}

function normalizeBangumiDetail(payload, baseUrl) {
  const data = payload?.data ?? payload;
  if (!data) return null;
  return {
    id: data.id ?? data.animeId,
    name: data.name || "",
    nameCn: data.name_cn || data.nameCn || data.name || "",
    summary: data.summary || "",
    imageUrl: data.imageUrl ? buildImageProxyUrl(baseUrl, data.imageUrl) : "",
    rating: data.rating,
    ratingDetails: data.ratingDetails,
    tags: Array.isArray(data.tags) ? data.tags : [],
    metadata: Array.isArray(data.metadata) ? data.metadata : [],
    titles: Array.isArray(data.titles) ? data.titles : [],
    airDate: data.air_date || data.airDate || "",
    airWeekday: data.airDay ?? data.airWeekday ?? null,
    totalEpisodes: data.totalEpisodes ?? null,
    typeDescription: data.typeDescription ?? null,
    isOnAir: data.isOnAir ?? null,
    isNSFW: data.isNSFW ?? null,
    bangumiUrl: data.bangumiUrl ?? null,
    episodes: Array.isArray(data.episodeList)
      ? data.episodeList
      : Array.isArray(data.episodes)
      ? data.episodes
      : [],
  };
}

function formatSummary(text) {
  if (!text) return "暂无简介";
  const cleaned = String(text)
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/```/g, "")
    .trim();
  return cleaned || "暂无简介";
}

function resolveRatingValue(anime) {
  const details = anime?.ratingDetails ?? {};
  const bangumiValue = Number(details["Bangumi评分"]);
  if (Number.isFinite(bangumiValue) && bangumiValue > 0) {
    return bangumiValue;
  }
  const rating = Number(anime?.rating);
  if (Number.isFinite(rating) && rating > 0) {
    return rating;
  }
  return null;
}

function resolveProgress(episode) {
  if (Number.isFinite(episode?.progress)) {
    return Math.max(0, Math.min(1, episode.progress));
  }
  if (episode?.lastPosition && episode?.duration) {
    return Math.max(0, Math.min(1, episode.lastPosition / episode.duration));
  }
  return 0;
}

function renderStars(rating) {
  if (rating == null) return null;
  const fullStars = Math.floor(rating);
  const halfStar = rating - fullStars >= 0.5;
  const stars = [];
  for (let i = 0; i < 10; i += 1) {
    if (i < fullStars) {
      stars.push(<IoStar key={`star-full-${i}`} />);
    } else if (i === fullStars && halfStar) {
      stars.push(<IoStarHalf key={`star-half-${i}`} />);
    } else {
      stars.push(<IoStarOutline key={`star-empty-${i}`} />);
    }
  }
  return stars;
}

export default function EpisodeModal({ anime, host, onClose, onPlayEpisode }) {
  const [episodes, setEpisodes] = useState([]);
  const [sharedAnime, setSharedAnime] = useState(null);
  const [detailAnime, setDetailAnime] = useState(null);
  const [episodesError, setEpisodesError] = useState("");
  const [detailError, setDetailError] = useState("");
  const [loadingEpisodes, setLoadingEpisodes] = useState(false);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [activeTab, setActiveTab] = useState("summary");
  const [isReversed, setIsReversed] = useState(false);
  const [isDesktop, setIsDesktop] = useState(
    () => typeof window !== "undefined" && window.innerWidth >= 960
  );
  const isMountedRef = useRef(true);
  const [dragOffset, setDragOffset] = useState({ x: 0, y: 0 });
  const dragOffsetRef = useRef(dragOffset);
  const dragStateRef = useRef({
    active: false,
    startX: 0,
    startY: 0,
    originX: 0,
    originY: 0,
  });
  const [isDragging, setIsDragging] = useState(false);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  useEffect(() => {
    dragOffsetRef.current = dragOffset;
  }, [dragOffset]);

  useEffect(() => {
    if (typeof window === "undefined") return;
    const handleResize = () => setIsDesktop(window.innerWidth >= 960);
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  const handleDragMove = useCallback((event) => {
    if (!dragStateRef.current.active) return;
    const deltaX = event.clientX - dragStateRef.current.startX;
    const deltaY = event.clientY - dragStateRef.current.startY;
    setDragOffset({
      x: dragStateRef.current.originX + deltaX,
      y: dragStateRef.current.originY + deltaY,
    });
  }, []);

  const handleDragEnd = useCallback(() => {
    if (!dragStateRef.current.active) return;
    dragStateRef.current.active = false;
    setIsDragging(false);
    window.removeEventListener("pointermove", handleDragMove);
    window.removeEventListener("pointerup", handleDragEnd);
  }, [handleDragMove]);

  useEffect(() => {
    return () => {
      window.removeEventListener("pointermove", handleDragMove);
      window.removeEventListener("pointerup", handleDragEnd);
    };
  }, [handleDragMove, handleDragEnd]);

  const handleDragStart = useCallback(
    (event) => {
      if (event.button !== undefined && event.button !== 0) return;
      if (event.target?.closest?.("button")) return;
      event.currentTarget?.setPointerCapture?.(event.pointerId);
      event.preventDefault();
      dragStateRef.current = {
        active: true,
        startX: event.clientX,
        startY: event.clientY,
        originX: dragOffsetRef.current.x,
        originY: dragOffsetRef.current.y,
      };
      setIsDragging(true);
      window.addEventListener("pointermove", handleDragMove);
      window.addEventListener("pointerup", handleDragEnd);
    },
    [handleDragMove, handleDragEnd]
  );

  const loadData = useCallback(async () => {
    if (!anime || !host) return;
    setLoadingEpisodes(true);
    setLoadingDetail(true);
    setEpisodesError("");
    setDetailError("");
    setEpisodes([]);
    setSharedAnime(null);
    setDetailAnime(null);

    const [episodeResult, detailResult] = await Promise.allSettled([
      getSharedAnimeEpisodes(host.baseUrl, anime.id),
      getBangumiDetail(host.baseUrl, anime.id),
    ]);

    if (!isMountedRef.current) return;

    if (episodeResult.status === "fulfilled") {
      const payload = episodeResult.value;
      setEpisodes(normalizeEpisodes(payload));
      const animeData = payload?.data?.anime ?? payload?.anime;
      setSharedAnime(normalizeSharedAnime(animeData, host.baseUrl));
    } else {
      setEpisodesError(episodeResult.reason?.message || "加载剧集失败");
    }

    if (detailResult.status === "fulfilled") {
      setDetailAnime(normalizeBangumiDetail(detailResult.value, host.baseUrl));
    } else {
      setDetailError(detailResult.reason?.message || "加载番剧详情失败");
    }

    setLoadingEpisodes(false);
    setLoadingDetail(false);
  }, [anime, host]);

  useEffect(() => {
    if (!anime || !host) return;
    loadData();
  }, [anime, host, loadData]);

  const displayAnime = useMemo(() => {
    const fallbackName = anime?.title || "未知番剧";
    const fallbackSummary = anime?.summary || "";
    const imageUrl = detailAnime?.imageUrl || sharedAnime?.imageUrl || anime?.imageUrl || "";
    return {
      id: detailAnime?.id ?? sharedAnime?.id ?? anime?.id,
      nameCn:
        detailAnime?.nameCn ||
        sharedAnime?.nameCn ||
        sharedAnime?.name ||
        fallbackName,
      name:
        detailAnime?.name ||
        sharedAnime?.name ||
        sharedAnime?.nameCn ||
        fallbackName,
      summary: detailAnime?.summary || sharedAnime?.summary || fallbackSummary,
      imageUrl,
      rating: detailAnime?.rating ?? sharedAnime?.rating,
      ratingDetails: detailAnime?.ratingDetails ?? sharedAnime?.ratingDetails,
      tags:
        detailAnime?.tags?.length > 0
          ? detailAnime.tags
          : sharedAnime?.tags || [],
      metadata:
        detailAnime?.metadata?.length > 0
          ? detailAnime.metadata
          : sharedAnime?.metadata || [],
      titles:
        detailAnime?.titles?.length > 0
          ? detailAnime.titles
          : sharedAnime?.titles || [],
      airDate: detailAnime?.airDate || sharedAnime?.airDate || "",
      airWeekday: detailAnime?.airWeekday ?? sharedAnime?.airWeekday ?? null,
      totalEpisodes:
        detailAnime?.totalEpisodes ??
        sharedAnime?.totalEpisodes ??
        anime?.episodeCount ??
        null,
      typeDescription: detailAnime?.typeDescription || sharedAnime?.typeDescription,
      isOnAir: detailAnime?.isOnAir ?? sharedAnime?.isOnAir ?? null,
      isNSFW: detailAnime?.isNSFW ?? sharedAnime?.isNSFW ?? null,
      bangumiUrl: detailAnime?.bangumiUrl ?? sharedAnime?.bangumiUrl ?? null,
      episodes: detailAnime?.episodes || [],
    };
  }, [anime, detailAnime, sharedAnime]);

  const displayTitle = displayAnime.nameCn || displayAnime.name || "剧集";
  const displaySubtitle =
    displayAnime.name && displayAnime.name !== displayTitle
      ? displayAnime.name
      : "";
  const summaryText = formatSummary(displayAnime.summary);
  const ratingValue = resolveRatingValue(displayAnime);
  const ratingEvaluation =
    ratingValue != null ? RATING_EVALUATION[Math.round(ratingValue)] : "";
  const airDateText = displayAnime.airDate
    ? String(displayAnime.airDate).split("T")[0]
    : "未知";

  const otherRatings = useMemo(() => {
    const details = displayAnime?.ratingDetails ?? {};
    return Object.entries(details)
      .map(([key, value]) => ({
        key,
        value: Number(value),
      }))
      .filter(({ key, value }) => key !== "Bangumi评分" && Number.isFinite(value) && value > 0)
      .map(({ key, value }) => ({
        label: key.endsWith("评分") ? key.slice(0, -2) : key,
        value,
      }));
  }, [displayAnime?.ratingDetails]);

  const detailEpisodes = useMemo(() => {
    if (!Array.isArray(displayAnime.episodes) || displayAnime.episodes.length === 0) {
      return [];
    }
    return displayAnime.episodes
      .map((item, index) => ({
        episodeId: item.episodeId ?? item.id ?? null,
        title: item.episodeTitle || item.title || "未命名剧集",
        airDate: item.airDate || "",
        episodeNumber:
          extractEpisodeNumber(item.episodeTitle) ?? extractEpisodeNumber(item.title),
        _index: index,
      }))
      .sort(compareEpisodes);
  }, [displayAnime.episodes]);

  const sharedEpisodeMap = useMemo(() => {
    const map = new Map();
    episodes.forEach((episode) => {
      if (episode.episodeId != null) {
        map.set(String(episode.episodeId), episode);
      }
    });
    return map;
  }, [episodes]);

  const mergedEpisodes = useMemo(() => {
    if (detailEpisodes.length > 0) {
      return detailEpisodes.map((detail, index) => {
        const shared = detail.episodeId != null
          ? sharedEpisodeMap.get(String(detail.episodeId))
          : null;
        return {
          shareId: shared?.shareId,
          title: detail.title,
          fileName: shared?.fileName,
          streamPath: shared?.streamPath,
          fileExists: shared?.fileExists ?? false,
          animeId: shared?.animeId ?? displayAnime.id ?? anime?.id,
          episodeId: detail.episodeId,
          progress: shared?.progress,
          duration: shared?.duration,
          lastPosition: shared?.lastPosition,
          airDate: detail.airDate,
          episodeNumber: detail.episodeNumber,
          _index: index,
        };
      });
    }
    return episodes;
  }, [detailEpisodes, sharedEpisodeMap, episodes, displayAnime.id, anime]);

  const displayEpisodes = useMemo(() => {
    const list = [...mergedEpisodes];
    if (isReversed) list.reverse();
    return list;
  }, [mergedEpisodes, isReversed]);

  const sourceLabel = host?.displayName || "";
  const tags = displayAnime.tags || [];
  const metadata = displayAnime.metadata || [];
  const titles = displayAnime.titles || [];

  const summaryView = (
    <div className="anime-detail-summary">
      {displaySubtitle && (
        <div className="anime-detail-alt-title">{displaySubtitle}</div>
      )}
      {loadingDetail && (
        <div className="anime-detail-notice">正在加载番剧详情...</div>
      )}
      {!loadingDetail && detailError && (
        <div className="anime-detail-notice warning">
          番剧详情加载失败，已使用共享信息。
        </div>
      )}
      <div className="anime-detail-summary-row">
        {displayAnime.imageUrl ? (
          <div className="anime-detail-cover">
            <img src={displayAnime.imageUrl} alt={displayTitle} />
          </div>
        ) : null}
        <div className="anime-detail-summary-text-scroll">
          <div className="anime-detail-summary-text">{summaryText}</div>
        </div>
      </div>
      <div className="anime-detail-divider" />
      {ratingValue != null && (
        <div className="anime-detail-rating">
          <span className="anime-detail-key">Bangumi评分: </span>
          <span className="anime-detail-stars">{renderStars(ratingValue)}</span>
          <span className="anime-detail-rating-value">
            {ratingValue.toFixed(1)}
          </span>
          {ratingEvaluation && (
            <span className="anime-detail-rating-eval">({ratingEvaluation})</span>
          )}
        </div>
      )}
      {otherRatings.length > 0 && (
        <div className="anime-detail-rating-others">
          {otherRatings.map((item) => (
            <div key={item.label} className="anime-detail-rating-other">
              <span className="anime-detail-key secondary">{item.label}: </span>
              <span className="anime-detail-value">
                {item.value.toFixed(1)}
              </span>
            </div>
          ))}
        </div>
      )}
      <div className="anime-detail-info-list">
        <div className="anime-detail-info-line">
          <span className="anime-detail-key">开播: </span>
          <span className="anime-detail-value">{airDateText}</span>
        </div>
        {displayAnime.typeDescription && (
          <div className="anime-detail-info-line">
            <span className="anime-detail-key">类型: </span>
            <span className="anime-detail-value">
              {displayAnime.typeDescription}
            </span>
          </div>
        )}
        {displayAnime.totalEpisodes != null && (
          <div className="anime-detail-info-line">
            <span className="anime-detail-key">话数: </span>
            <span className="anime-detail-value">{displayAnime.totalEpisodes}</span>
          </div>
        )}
        {displayAnime.isOnAir != null && (
          <div className="anime-detail-info-line">
            <span className="anime-detail-key">状态: </span>
            <span className="anime-detail-value">
              {displayAnime.isOnAir ? "正连载" : "已完结"}
            </span>
          </div>
        )}
        {displayAnime.isNSFW && (
          <div className="anime-detail-info-line warning">
            <span className="anime-detail-key">限制内容: </span>
            <span className="anime-detail-value">是</span>
          </div>
        )}
      </div>
      {metadata.length > 0 && (
        <div className="anime-detail-section">
          <div className="anime-detail-section-title">制作信息:</div>
          <div className="anime-detail-meta-list">
            {metadata
              .filter((item) => !String(item).trim().startsWith("别名"))
              .map((item) => {
                const text = String(item);
                const parts = text.split(/[:：]/);
                if (parts.length === 2) {
                  return (
                    <div key={text} className="anime-detail-meta-row">
                      <span className="anime-detail-meta-key">
                        {parts[0].trim()}:
                      </span>
                      <span className="anime-detail-value">{parts[1].trim()}</span>
                    </div>
                  );
                }
                return (
                  <div key={text} className="anime-detail-meta-row">
                    <span className="anime-detail-value">{text}</span>
                  </div>
                );
              })}
          </div>
        </div>
      )}
      {titles.length > 0 && (
        <div className="anime-detail-section">
          <div className="anime-detail-section-title">其他标题:</div>
          <div className="anime-detail-title-list">
            {titles.map((item) => (
              <div
                key={`${item.title}-${item.language}`}
                className="anime-detail-title-item"
              >
                {item.title}
                {item.language ? ` (${item.language})` : ""}
              </div>
            ))}
          </div>
        </div>
      )}
      {tags.length > 0 && (
        <div className="anime-detail-section">
          <div className="anime-detail-section-title">标签:</div>
          <div className="anime-detail-tag-list">
            {tags.map((tag) => (
              <span key={tag} className="anime-detail-tag">
                {tag}
              </span>
            ))}
          </div>
        </div>
      )}
    </div>
  );

  const episodesView = (
    <div className="anime-detail-episodes">
      <div className="anime-detail-episode-header">
        <span>共{displayEpisodes.length}集</span>
        <button
          type="button"
          className="anime-detail-sort"
          onClick={() => setIsReversed((prev) => !prev)}
        >
          <IoSwapVerticalOutline />
          {isReversed ? "倒序" : "正序"}
        </button>
      </div>
      {loadingEpisodes && (
        <div className="anime-detail-loading">正在加载剧集...</div>
      )}
      {!loadingEpisodes && episodesError && (
        <div className="anime-detail-error">
          <div>{episodesError}</div>
          <button type="button" className="primary-button" onClick={loadData}>
            重新加载
          </button>
        </div>
      )}
      {!loadingEpisodes && !episodesError && displayEpisodes.length === 0 && (
        <div className="anime-detail-empty">暂无剧集信息</div>
      )}
      {!loadingEpisodes && !episodesError && displayEpisodes.length > 0 && (
        <div className="anime-detail-episode-list">
          {displayEpisodes.map((episode, index) => {
            const progress = resolveProgress(episode);
            const isCompleted = progress >= 0.95;
            const isInProgress = progress > 0.01 && !isCompleted;
            const canPlay = Boolean(episode.streamPath && episode.fileExists);
            let status = "missing";
            let progressText = "未找到";
            if (isCompleted) {
              status = "completed";
              progressText = "已看完";
            } else if (isInProgress) {
              status = "in-progress";
              progressText = `${Math.round(progress * 100)}%`;
            } else if (canPlay) {
              status = "shared";
              progressText = "共享媒体";
            }
            const rowClass = ["anime-detail-episode", status].join(" ");
            return (
              <div
                key={episode.shareId || episode.episodeId || `${episode.title}-${index}`}
                className={rowClass}
                role={canPlay ? "button" : "presentation"}
                onClick={() => {
                  if (!canPlay) return;
                  const url = buildStreamUrl(host.baseUrl, episode.streamPath);
                  onPlayEpisode({
                    url,
                    title: displayTitle,
                    episodeTitle: episode.title,
                    animeId: episode.animeId ?? displayAnime.id ?? anime.id,
                    episodeId: episode.episodeId,
                  });
                  onClose();
                }}
              >
                <div className="anime-detail-episode-leading">
                  {isCompleted ? <IoCheckmarkCircle /> : <IoPlayCircleOutline />}
                </div>
                <div className="anime-detail-episode-title">{episode.title}</div>
                <div className={`anime-detail-episode-progress ${status}`}>
                  {progressText}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );

  return (
    <div className="anime-detail-backdrop" onClick={onClose} role="presentation">
      <div
        className="anime-detail-window"
        role="dialog"
        aria-modal="true"
        onClick={(event) => event.stopPropagation()}
        style={{
          transform: `translate3d(${dragOffset.x}px, ${dragOffset.y}px, 0)`,
        }}
      >
        {displayAnime.imageUrl && (
          <div
            className="anime-detail-bg"
            style={{ backgroundImage: `url(${displayAnime.imageUrl})` }}
          />
        )}
        <div className="anime-detail-gradient" />
        <div
          className={`anime-detail-drag-bar ${isDragging ? "dragging" : ""}`}
          onPointerDown={handleDragStart}
        />
        <div className="anime-detail-top-actions">
          <button
            type="button"
            className="anime-detail-close"
            onClick={onClose}
            aria-label="关闭"
          >
            <IoClose />
          </button>
        </div>
        <div className="anime-detail-content">
          <div
            className={`anime-detail-header ${isDragging ? "dragging" : ""}`}
            onPointerDown={handleDragStart}
          >
            <div className="anime-detail-title">{displayTitle}</div>
            {displaySubtitle && (
              <div className="anime-detail-subtitle">{displaySubtitle}</div>
            )}
            {sourceLabel && (
              <div className="anime-detail-source">
                <IoCloudOutline />
                <span>{sourceLabel}</span>
              </div>
            )}
          </div>
          {!isDesktop && (
            <div className="anime-detail-tabs">
              <button
                type="button"
                className={`anime-detail-tab ${
                  activeTab === "summary" ? "active" : ""
                }`}
                onClick={() => setActiveTab("summary")}
              >
                <IoDocumentTextOutline />
                简介
              </button>
              <button
                type="button"
                className={`anime-detail-tab ${
                  activeTab === "episodes" ? "active" : ""
                }`}
                onClick={() => setActiveTab("episodes")}
              >
                <IoFilmOutline />
                剧集
              </button>
            </div>
          )}
          <div className={`anime-detail-body ${isDesktop ? "desktop" : ""}`}>
            {isDesktop ? (
              <>
                <div className="anime-detail-panel">{summaryView}</div>
                <div className="anime-detail-divider-vertical" />
                <div className="anime-detail-panel">{episodesView}</div>
              </>
            ) : activeTab === "summary" ? (
              summaryView
            ) : (
              episodesView
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
