import React, { useEffect, useState } from "react";
import Modal from "./Modal.jsx";
import { buildStreamUrl, getSharedAnimeEpisodes } from "../lib/api.js";

function normalizeEpisodes(payload) {
  const raw = (payload?.data?.episodes ?? payload?.episodes ?? []).map((item) => ({
    shareId: item.shareId,
    title: item.title || "未命名剧集",
    streamPath: item.streamPath,
    fileExists: item.fileExists !== false,
    animeId: item.animeId,
    episodeId: item.episodeId,
    progress: item.progress,
    duration: item.duration,
    lastPosition: item.lastPosition,
  }));
  return raw;
}

export default function EpisodeModal({ anime, host, onClose, onPlayEpisode }) {
  const [episodes, setEpisodes] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!anime || !host) return;
    let cancelled = false;
    const load = async () => {
      setLoading(true);
      setError("");
      try {
        const payload = await getSharedAnimeEpisodes(host.baseUrl, anime.id);
        if (cancelled) return;
        setEpisodes(normalizeEpisodes(payload));
      } catch (err) {
        if (cancelled) return;
        setError(err.message || "加载失败");
      } finally {
        if (!cancelled) setLoading(false);
      }
    };
    load();
    return () => {
      cancelled = true;
    };
  }, [anime, host]);

  return (
    <Modal title={anime?.title || "剧集"} onClose={onClose} className="episode-modal">
      <div className="episode-header">
        <div className="episode-cover">
          {anime?.imageUrl ? (
            <img src={anime.imageUrl} alt={anime.title} />
          ) : (
            <div className="cover-placeholder">暂无封面</div>
          )}
        </div>
        <div>
          <div className="episode-title">{anime?.title}</div>
          <div className="episode-sub">{anime?.episodeCount} 集</div>
          {anime?.summary && <div className="episode-summary">{anime.summary}</div>}
        </div>
      </div>
      {loading && <div className="modal-loading">正在加载剧集...</div>}
      {error && <div className="modal-error">{error}</div>}
      {!loading && !error && (
        <div className="episode-list">
          {episodes.map((episode) => {
            const progress = episode.progress
              ? `${Math.round(episode.progress * 100)}%`
              : episode.lastPosition && episode.duration
              ? `${Math.round((episode.lastPosition / episode.duration) * 100)}%`
              : null;
            return (
              <div
                key={episode.shareId || episode.title}
                className={`episode-row ${episode.fileExists ? "" : "missing"}`}
              >
                <div>
                  <div className="episode-row-title">{episode.title}</div>
                  {progress && <div className="episode-row-sub">观看进度 {progress}</div>}
                  {!episode.fileExists && (
                    <div className="episode-row-sub warning">文件缺失</div>
                  )}
                </div>
                <button
                  type="button"
                  className="primary-button"
                  disabled={!episode.fileExists}
                  onClick={() => {
                    const url = buildStreamUrl(host.baseUrl, episode.streamPath);
                    onPlayEpisode({
                      url,
                      title: anime.title,
                      episodeTitle: episode.title,
                      animeId: episode.animeId ?? anime.id,
                      episodeId: episode.episodeId ?? episode.shareId,
                    });
                    onClose();
                  }}
                >
                  播放
                </button>
              </div>
            );
          })}
        </div>
      )}
    </Modal>
  );
}
