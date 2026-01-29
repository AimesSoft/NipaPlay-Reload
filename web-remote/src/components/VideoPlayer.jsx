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
} from "react-icons/io5";
import { getDanmaku } from "../lib/api.js";
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
    const video = videoRef.current;
    const container = danmakuRef.current;
    if (!video || !container || !window.Danmaku) return;

    let cancelled = false;
    const load = async () => {
      if (!playback.episodeId || !playback.animeId) return;
      try {
        const payload = await getDanmaku(host.baseUrl, playback.episodeId, playback.animeId);
        if (cancelled) return;
        const comments = (payload?.comments || []).map((comment) => {
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
      } catch {
        // ignore danmaku errors
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

  const togglePlay = () => {
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) {
      video.play();
    } else {
      video.pause();
    }
  };

  const handleSeek = (event) => {
    const video = videoRef.current;
    if (!video) return;
    const nextTime = Number(event.target.value);
    video.currentTime = nextTime;
    setCurrentTime(nextTime);
  };

  const handleVolume = (event) => {
    const video = videoRef.current;
    if (!video) return;
    const nextVolume = Number(event.target.value);
    video.volume = nextVolume;
    setVolume(nextVolume);
  };

  const handleFullscreen = () => {
    const container = videoRef.current?.parentElement;
    if (!container) return;
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

  return (
    <div className="player-view">
      <div className="player-header">
        <button type="button" className="ghost-button" onClick={onBack}>
          <IoChevronBackOutline />
          返回媒体库
        </button>
        <div className="player-title">
          <div>{playback?.title || "未选择视频"}</div>
          {playback?.episodeTitle && <div className="player-sub">{playback.episodeTitle}</div>}
        </div>
      </div>
      <div className="player-container">
        <video
          ref={videoRef}
          src={playback?.url || ""}
          className="video-element"
          controls={false}
        />
        {!playback && <div className="player-empty">请选择要播放的内容</div>}
        <div className="danmaku-layer" ref={danmakuRef} />
        <canvas className="subtitle-layer" ref={subtitleRef} />
      </div>
      <div className="player-controls">
        <button type="button" className="control-button" onClick={togglePlay}>
          {isPlaying ? <IoPause /> : <IoPlay />}
        </button>
        <div className="time-display">
          {formatTime(currentTime)} / {formatTime(duration)}
        </div>
        <input
          className="progress"
          type="range"
          min="0"
          max={duration || 0}
          step="0.1"
          value={currentTime}
          onChange={handleSeek}
        />
        <button type="button" className="control-button" onClick={handleFullscreen}>
          {isFullscreen ? <IoContract /> : <IoExpand />}
        </button>
        <button
          type="button"
          className={`control-button ${danmakuEnabled ? "active" : ""}`}
          onClick={() => setDanmakuEnabled((prev) => !prev)}
        >
          <IoChatbubblesOutline />
        </button>
        <button
          type="button"
          className="control-button"
          onClick={() => setShowSubtitleModal(true)}
        >
          <IoLogoClosedCaptioning />
        </button>
        <div className="volume-control">
          <span className="control-button">
            <VolumeIcon />
          </span>
          <input
            type="range"
            min="0"
            max="1"
            step="0.01"
            value={volume}
            onChange={handleVolume}
          />
        </div>
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
