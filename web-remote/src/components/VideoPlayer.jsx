import React, { useEffect, useRef, useState } from "react";
import {
  IoPlay,
  IoPause,
  IoVolumeHigh,
  IoVolumeMedium,
  IoVolumeMute,
  IoExpand,
  IoContract,
  IoChevronBackOutline,
  IoChatbubblesOutline,
  IoLogoClosedCaptioning,
  IoPlayBack,
  IoPlayForward,
} from "react-icons/io5";
import { getDanmaku, getVideoInfo } from "../lib/api.js";
import Modal from "./Modal.jsx";

function formatTime(value) {
  if (!Number.isFinite(value)) return "00:00";
  const total = Math.floor(value);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = total % 60;
  if (hours > 0) {
    return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
  }
  return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

function SubtitleModal({ onClose, onSubmit }) {
  const [value, setValue] = useState("");

  return (
    <Modal title="加载字幕" onClose={onClose} className="subtitle-modal">
      <div className="form-row">
        <label>字幕地址</label>
        <input
          value={value}
          onChange={(event) => setValue(event.target.value)}
          placeholder="http://.../subtitle.ass"
        />
      </div>
      <button
        type="button"
        className="primary-button"
        onClick={() => onSubmit(value)}
      >
        加载字幕
      </button>
    </Modal>
  );
}

function resolveUrl(input, baseUrl) {
  if (!input) return "";
  try {
    return new URL(input).toString();
  } catch {
    try {
      return new URL(input, `${baseUrl}/`).toString();
    } catch {
      return input;
    }
  }
}

export default function VideoPlayer({ playback, host, onBack }) {
  const videoRef = useRef(null);
  const danmakuRef = useRef(null);
  const subtitleRef = useRef(null);
  const danmakuInstance = useRef(null);
  const subtitleInstance = useRef(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(1);
  const [showSubtitleModal, setShowSubtitleModal] = useState(false);
  const [danmakuEnabled, setDanmakuEnabled] = useState(true);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [mascotActive, setMascotActive] = useState(false);
  const [controlsVisible, setControlsVisible] = useState(true);
  const [controlsHovered, setControlsHovered] = useState(false);
  const hideControlsTimer = useRef(null);
  const isEmpty = !playback;

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    const handlePlay = () => setIsPlaying(true);
    const handlePause = () => setIsPlaying(false);
    const handleTime = () => setCurrentTime(video.currentTime || 0);
    const handleDuration = () => setDuration(video.duration || 0);

    video.addEventListener("play", handlePlay);
    video.addEventListener("pause", handlePause);
    video.addEventListener("timeupdate", handleTime);
    video.addEventListener("loadedmetadata", handleDuration);
    video.addEventListener("volumechange", () => setVolume(video.volume));

    const handleFullscreen = () => setIsFullscreen(Boolean(document.fullscreenElement));
    document.addEventListener("fullscreenchange", handleFullscreen);

    return () => {
      video.removeEventListener("play", handlePlay);
      video.removeEventListener("pause", handlePause);
      video.removeEventListener("timeupdate", handleTime);
      video.removeEventListener("loadedmetadata", handleDuration);
      document.removeEventListener("fullscreenchange", handleFullscreen);
    };
  }, [playback]);

  useEffect(() => {
    if (!danmakuEnabled || !playback || !host) {
      window.DanmakuOff = 0;
      if (danmakuInstance.current) {
        danmakuInstance.current.destroy();
        danmakuInstance.current = null;
      }
      return;
    }
    window.DanmakuOff = 1;
    window.danmakufsBase = window.danmakufsBase || 3;
    window.lineWidth = window.lineWidth || 3;
    window.BottomAlpha = window.BottomAlpha ?? 1;
    window.TopAlpha = window.TopAlpha ?? 1;
    window.RtlAlpha = window.RtlAlpha ?? 1;
    window.RenderRegion = window.RenderRegion ?? 1;
    const video = videoRef.current;
    const container = danmakuRef.current;
    if (!video || !container || !window.Danmaku) {
      console.warn("[danmaku] init skipped", {
        hasVideo: Boolean(video),
        hasContainer: Boolean(container),
        hasEngine: Boolean(window.Danmaku),
      });
      return;
    }

    let cancelled = false;
    const load = async () => {
      try {
        let payload = null;
        const episodeId = playback?.episodeId;
        const animeId = playback?.animeId;
        console.info("[danmaku] load start", {
          episodeId,
          animeId,
          url: playback?.url,
        });
        const parsedEpisodeId = Number(episodeId);
        const parsedAnimeId = Number(animeId);
        const hasNumericIds =
          Number.isFinite(parsedEpisodeId) &&
          parsedEpisodeId > 0 &&
          Number.isFinite(parsedAnimeId) &&
          parsedAnimeId > 0;
        if (hasNumericIds) {
          console.info("[danmaku] request by ids", {
            episodeId: parsedEpisodeId,
            animeId: parsedAnimeId,
          });
          payload = await getDanmaku(host.baseUrl, parsedEpisodeId, parsedAnimeId);
        } else if (playback?.url) {
          console.info("[danmaku] fallback to video_info", { url: playback.url });
          payload = await getVideoInfo(host.baseUrl, playback.url);
          const matches = Array.isArray(payload?.matches) ? payload.matches : [];
          console.info("[danmaku] video_info response", {
            isMatched: payload?.isMatched,
            matchCount: matches.length,
            commentCount: Array.isArray(payload?.comments) ? payload.comments.length : 0,
          });
          if ((!payload?.comments || payload.comments.length === 0) && matches.length > 0) {
            const match = matches[0] || {};
            if (match.episodeId != null && match.animeId != null) {
              console.info("[danmaku] matched ids", {
                episodeId: match.episodeId,
                animeId: match.animeId,
              });
              payload = await getDanmaku(host.baseUrl, match.episodeId, match.animeId);
            }
          }
        }
        if (cancelled || !payload) return;
        const rawComments = payload?.comments ?? payload?.data?.comments ?? [];
        if (!Array.isArray(rawComments) || rawComments.length === 0) {
          console.warn("[danmaku] empty comments", {
            hasComments: Array.isArray(rawComments),
            count: Array.isArray(rawComments) ? rawComments.length : 0,
          });
          return;
        }
        console.info("[danmaku] comments ready", { count: rawComments.length });
        const comments = rawComments.map((comment) => {
          const type = comment.type === "top" ? "top" : comment.type === "bottom" ? "bottom" : "rtl";
          return {
            time: comment.time,
            text: comment.content,
            mode: type,
            style: {
              fillStyle: comment.color || "#ffffff",
              strokeStyle: "#000000",
              font: "28px sans-serif",
            },
          };
        });
        if (danmakuInstance.current) {
          danmakuInstance.current.destroy();
        }
        danmakuInstance.current = new window.Danmaku({
          container,
          media: video,
          comments,
          engine: "canvas",
        });
      } catch (error) {
        console.error("[danmaku] load failed", error);
      }
    };
    load();

    const handleResize = () => {
      if (danmakuInstance.current) {
        danmakuInstance.current.resize();
      }
    };
    window.addEventListener("resize", handleResize);

    return () => {
      cancelled = true;
      window.removeEventListener("resize", handleResize);
      if (danmakuInstance.current) {
        danmakuInstance.current.destroy();
        danmakuInstance.current = null;
      }
    };
  }, [danmakuEnabled, playback, host]);

  useEffect(() => {
    return () => {
      if (subtitleInstance.current) {
        subtitleInstance.current.dispose();
        subtitleInstance.current = null;
      }
    };
  }, []);

  useEffect(() => {
    if (!mascotActive) return;
    const timer = window.setTimeout(() => setMascotActive(false), 320);
    return () => window.clearTimeout(timer);
  }, [mascotActive]);

  useEffect(() => {
    if (isEmpty) {
      setControlsVisible(false);
      if (hideControlsTimer.current) {
        window.clearTimeout(hideControlsTimer.current);
        hideControlsTimer.current = null;
      }
      return;
    }
    if (!isPlaying) {
      setControlsVisible(true);
      if (hideControlsTimer.current) {
        window.clearTimeout(hideControlsTimer.current);
        hideControlsTimer.current = null;
      }
      return;
    }
    if (controlsHovered) return;
    if (hideControlsTimer.current) {
      window.clearTimeout(hideControlsTimer.current);
    }
    hideControlsTimer.current = window.setTimeout(() => {
      setControlsVisible(false);
    }, 2800);
    return () => {
      if (hideControlsTimer.current) {
        window.clearTimeout(hideControlsTimer.current);
        hideControlsTimer.current = null;
      }
    };
  }, [controlsHovered, isEmpty, isPlaying]);

  const triggerMascot = () => {
    setMascotActive(false);
    window.requestAnimationFrame(() => setMascotActive(true));
  };

  const showControls = () => {
    if (isEmpty) return;
    setControlsVisible(true);
    if (hideControlsTimer.current) {
      window.clearTimeout(hideControlsTimer.current);
      hideControlsTimer.current = null;
    }
    if (isPlaying && !controlsHovered) {
      hideControlsTimer.current = window.setTimeout(() => {
        setControlsVisible(false);
      }, 2800);
    }
  };

  const handleControlsEnter = () => {
    setControlsHovered(true);
    setControlsVisible(true);
    if (hideControlsTimer.current) {
      window.clearTimeout(hideControlsTimer.current);
      hideControlsTimer.current = null;
    }
  };

  const handleControlsLeave = () => {
    setControlsHovered(false);
    if (isPlaying) {
      showControls();
    }
  };

  const handleContainerMouseMove = () => {
    showControls();
  };

  const handleContainerMouseLeave = () => {
    if (!isPlaying || controlsHovered) return;
    setControlsVisible(false);
  };

  const togglePlay = () => {
    const video = videoRef.current;
    if (!video) return;
    showControls();
    if (video.paused) {
      video.play();
    } else {
      video.pause();
    }
  };

  const handleSeekBy = (deltaSeconds) => {
    const video = videoRef.current;
    if (!video) return;
    const nextTime = Math.max(0, Math.min(video.currentTime + deltaSeconds, duration || 0));
    video.currentTime = nextTime;
    setCurrentTime(nextTime);
    showControls();
  };

  const handleSeek = (event) => {
    const video = videoRef.current;
    if (!video) return;
    const nextTime = Number(event.target.value);
    video.currentTime = nextTime;
    setCurrentTime(nextTime);
    showControls();
  };

  const handleVolume = (event) => {
    const video = videoRef.current;
    if (!video) return;
    const nextVolume = Number(event.target.value);
    video.volume = nextVolume;
    setVolume(nextVolume);
    showControls();
  };

  const handleFullscreen = () => {
    const container = videoRef.current?.parentElement;
    if (!container) return;
    showControls();
    if (document.fullscreenElement) {
      document.exitFullscreen();
    } else {
      container.requestFullscreen();
    }
  };

  const handleLoadSubtitle = async (input) => {
    if (!input || !host) return;
    const video = videoRef.current;
    const canvas = subtitleRef.current;
    if (!video || !canvas || !window.SubtitlesOctopus) return;

    try {
      const url = resolveUrl(input, host.baseUrl);
      const response = await fetch(url);
      const text = await response.text();
      if (subtitleInstance.current) {
        subtitleInstance.current.dispose();
      }
      subtitleInstance.current = new window.SubtitlesOctopus({
        video,
        subContent: text,
        canvas,
        workerUrl: "/libass/subtitles-octopus-worker.js",
        legacyWorkerUrl: "/libass/subtitles-octopus-worker-legacy.js",
        fonts: ["/libass/ChillRoundM.otf"],
      });
    } catch {
      // ignore subtitle errors
    } finally {
      setShowSubtitleModal(false);
    }
  };

  const VolumeIcon = volume === 0 ? IoVolumeMute : volume < 0.5 ? IoVolumeMedium : IoVolumeHigh;
  const progressPercent = duration > 0 ? Math.min((currentTime / duration) * 100, 100) : 0;
  const volumePercent = Math.min(volume * 100, 100);
  const mascotUrl = `${import.meta.env.BASE_URL}assets/girl.png`;

  return (
    <div className="player-view">
      <div
        className={`player-container ${isEmpty ? "is-empty" : "has-video"}`}
        onMouseMove={handleContainerMouseMove}
        onMouseLeave={handleContainerMouseLeave}
      >
        {playback && (
          <>
            <video
              ref={videoRef}
              src={playback.url || ""}
              className="video-element"
              controls={false}
            />
            <div className="danmaku-layer" ref={danmakuRef} />
            <canvas className="subtitle-layer" ref={subtitleRef} />
            <div className="player-minimal-progress" aria-hidden="true">
              <div
                className="player-minimal-progress-fill"
                style={{ width: `${progressPercent}%` }}
              />
            </div>
            <div className={`player-overlay ${controlsVisible ? "is-visible" : ""}`}>
              <div
                className="player-overlay-top"
                onMouseEnter={handleControlsEnter}
                onMouseLeave={handleControlsLeave}
              >
                <button
                  type="button"
                  className="player-overlay-button"
                  onClick={onBack}
                  aria-label="返回媒体库"
                >
                  <IoChevronBackOutline />
                </button>
                <div className="player-overlay-title">
                  <div className="player-overlay-main">
                    {playback?.title || "未选择视频"}
                  </div>
                  {playback?.episodeTitle && (
                    <div className="player-overlay-sub">{playback.episodeTitle}</div>
                  )}
                </div>
              </div>
            </div>
            <div
              className={`player-controls ${controlsVisible ? "is-visible" : ""}`}
              onMouseEnter={handleControlsEnter}
              onMouseLeave={handleControlsLeave}
            >
              <div className="player-progress">
                <input
                  className="progress player-range"
                  type="range"
                  min="0"
                  max={duration || 0}
                  step="0.1"
                  value={currentTime}
                  onChange={handleSeek}
                  style={{ "--progress": `${progressPercent}%` }}
                />
              </div>
              <div className="player-controls-row">
                <div className="player-control-group">
                  <button
                    type="button"
                    className="control-button"
                    onClick={() => handleSeekBy(-10)}
                    aria-label="快退 10 秒"
                  >
                    <IoPlayBack />
                  </button>
                  <button
                    type="button"
                    className="control-button play-toggle"
                    onClick={togglePlay}
                    aria-label={isPlaying ? "暂停" : "播放"}
                  >
                    {isPlaying ? <IoPause /> : <IoPlay />}
                  </button>
                  <button
                    type="button"
                    className="control-button"
                    onClick={() => handleSeekBy(10)}
                    aria-label="快进 10 秒"
                  >
                    <IoPlayForward />
                  </button>
                </div>
                <div className="player-spacer" />
                <div className="time-display">
                  {formatTime(currentTime)} / {formatTime(duration)}
                </div>
                <button
                  type="button"
                  className={`control-button ${danmakuEnabled ? "active" : ""}`}
                  onClick={() => setDanmakuEnabled((prev) => !prev)}
                  aria-label="弹幕开关"
                >
                  <IoChatbubblesOutline />
                </button>
                <button
                  type="button"
                  className="control-button"
                  onClick={() => setShowSubtitleModal(true)}
                  aria-label="加载字幕"
                >
                  <IoLogoClosedCaptioning />
                </button>
                <button
                  type="button"
                  className="control-button"
                  onClick={handleFullscreen}
                  aria-label={isFullscreen ? "退出全屏" : "进入全屏"}
                >
                  {isFullscreen ? <IoContract /> : <IoExpand />}
                </button>
                <div className="volume-control">
                  <span className="control-button">
                    <VolumeIcon />
                  </span>
                  <input
                    className="player-range"
                    type="range"
                    min="0"
                    max="1"
                    step="0.01"
                    value={volume}
                    onChange={handleVolume}
                    style={{ "--progress": `${volumePercent}%` }}
                  />
                </div>
              </div>
            </div>
          </>
        )}
        {isEmpty && (
          <div className="player-empty">
            <div className="player-empty-content">
              <button
                type="button"
                className={`player-empty-mascot ${mascotActive ? "is-animating" : ""}`}
                onClick={triggerMascot}
                aria-label="点击看板娘"
              >
                <img src={mascotUrl} alt="NipaPlay 看板娘" />
              </button>
              <div className="player-empty-text">
                <span className="player-empty-main">诶？还没有在播放的视频！</span>
                <button
                  type="button"
                  className="player-empty-action"
                  onClick={onBack}
                >
                  选择文件
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
      {showSubtitleModal && (
        <SubtitleModal
          onClose={() => setShowSubtitleModal(false)}
          onSubmit={handleLoadSubtitle}
        />
      )}
    </div>
  );
}
