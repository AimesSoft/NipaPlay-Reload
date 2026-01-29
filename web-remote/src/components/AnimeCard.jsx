import React from "react";

export default function AnimeCard({ anime, onClick, hostName }) {
  return (
    <button type="button" className="anime-card" onClick={onClick}>
      <div className="anime-cover">
        {anime.imageUrl ? (
          <img src={anime.imageUrl} alt={anime.title} loading="lazy" />
        ) : (
          <div className="cover-placeholder">暂无封面</div>
        )}
      </div>
      <div className="anime-info">
        <div className="anime-title">{anime.title}</div>
        <div className="anime-sub">{anime.episodeCount} 集</div>
        {hostName && <div className="anime-source">{hostName}</div>}
        {anime.summary && <div className="anime-summary">{anime.summary}</div>}
      </div>
    </button>
  );
}
