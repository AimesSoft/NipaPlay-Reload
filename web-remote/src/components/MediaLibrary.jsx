import React, { useEffect, useMemo, useState } from "react";
import { IoRefreshOutline, IoLinkOutline } from "react-icons/io5";
import { buildImageProxyUrl, getSharedAnimes } from "../lib/api.js";
import ControlBar from "./ControlBar.jsx";
import IconButton from "./IconButton.jsx";
import SubTabs from "./SubTabs.jsx";
import AnimeCard from "./AnimeCard.jsx";
import EpisodeModal from "./EpisodeModal.jsx";
import LibraryManagement from "./LibraryManagement.jsx";

function normalizeAnimeList(payload, baseUrl) {
  const items = payload?.items ?? payload?.data ?? payload ?? [];
  return items.map((item) => ({
    id: item.animeId,
    title: item.nameCn || item.name || "未知番剧",
    summary: item.summary || "",
    imageUrl: buildImageProxyUrl(baseUrl, item.imageUrl),
    lastWatchTime: item.lastWatchTime,
    episodeCount: item.episodeCount ?? 0,
    hasMissingFiles: item.hasMissingFiles ?? false,
  }));
}

export default function MediaLibrary({ host, onOpenHostModal, onPlay }) {
  const [activeTab, setActiveTab] = useState("media");
  const [search, setSearch] = useState("");
  const [sort, setSort] = useState("date");
  const [animes, setAnimes] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [selectedAnime, setSelectedAnime] = useState(null);

  const fetchLibrary = async () => {
    if (!host) return;
    setLoading(true);
    setError("");
    try {
      const payload = await getSharedAnimes(host.baseUrl);
      setAnimes(normalizeAnimeList(payload, host.baseUrl));
    } catch (err) {
      setError(err.message || "加载失败");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (activeTab !== "media") return;
    fetchLibrary();
  }, [host, activeTab]);

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    const result = animes.filter((anime) => {
      if (!query) return true;
      return anime.title.toLowerCase().includes(query);
    });
    if (sort === "name") {
      result.sort((a, b) => a.title.localeCompare(b.title));
    } else {
      result.sort((a, b) =>
        new Date(b.lastWatchTime || 0) - new Date(a.lastWatchTime || 0)
      );
    }
    return result;
  }, [animes, search, sort]);

  const actions = [
    {
      key: "refresh",
      node: (
        <IconButton
          icon={IoRefreshOutline}
          title="刷新共享媒体"
          onClick={fetchLibrary}
          disabled={!host}
        />
      ),
    },
    {
      key: "host",
      node: (
        <IconButton
          icon={IoLinkOutline}
          title="切换共享客户端"
          onClick={onOpenHostModal}
        />
      ),
    },
  ];

  return (
    <div className="media-library">
      <SubTabs activeTab={activeTab} onChange={setActiveTab} />
      {!host && <div className="empty-state">请先添加并选择共享客户端</div>}
      {host && activeTab === "media" ? (
        <div className="library-section">
          <ControlBar
            searchValue={search}
            onSearchChange={setSearch}
            onClear={() => setSearch("")}
            sortValue={sort}
            onSortChange={setSort}
            showSort
            actions={actions}
          />
          {error && <div className="error-banner">{error}</div>}
          {loading && <div className="loading">正在加载共享媒体库...</div>}
          {!loading && filtered.length === 0 && (
            <div className="empty-state">共享媒体库为空</div>
          )}
          <div className="anime-grid">
            {filtered.map((anime) => (
              <AnimeCard
                key={anime.id}
                anime={anime}
                hostName={host?.displayName}
                onClick={() => setSelectedAnime(anime)}
              />
            ))}
          </div>
        </div>
      ) : host ? (
        <LibraryManagement
          host={host}
          onPlay={onPlay}
          onOpenHostModal={onOpenHostModal}
        />
      ) : null}
      {selectedAnime && host && (
        <EpisodeModal
          anime={selectedAnime}
          host={host}
          onClose={() => setSelectedAnime(null)}
          onPlayEpisode={onPlay}
        />
      )}
    </div>
  );
}
