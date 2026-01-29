import React, { useEffect, useMemo, useState } from "react";
import TopTabs from "./components/TopTabs.jsx";
import MediaLibrary from "./components/MediaLibrary.jsx";
import VideoPlayer from "./components/VideoPlayer.jsx";
import HostModal from "./components/HostModal.jsx";
import {
  createHost,
  ensureActiveHost,
  loadActiveHostId,
  loadHosts,
  normalizeBaseUrl,
  persistHosts,
} from "./lib/hosts.js";

function resolveDisplayName(url) {
  try {
    const parsed = new URL(url);
    return parsed.hostname;
  } catch {
    return url;
  }
}

export default function App() {
  const [hosts, setHosts] = useState(() => loadHosts());
  const [activeHostId, setActiveHostId] = useState(() =>
    ensureActiveHost(loadHosts(), loadActiveHostId())
  );
  const [activeTab, setActiveTab] = useState("library");
  const [showHostModal, setShowHostModal] = useState(false);
  const [playback, setPlayback] = useState(null);

  useEffect(() => {
    const nextActive = ensureActiveHost(hosts, activeHostId);
    if (nextActive !== activeHostId) {
      setActiveHostId(nextActive);
    }
  }, [hosts, activeHostId]);

  useEffect(() => {
    persistHosts(hosts, activeHostId);
  }, [hosts, activeHostId]);

  useEffect(() => {
    if (!activeHostId) {
      setShowHostModal(true);
    }
  }, [activeHostId]);

  const activeHost = useMemo(
    () => hosts.find((host) => host.id === activeHostId) || null,
    [hosts, activeHostId]
  );

  const handleAddHost = ({ displayName, baseUrl }) => {
    const normalized = normalizeBaseUrl(baseUrl);
    if (!normalized) return;
    const name = displayName || resolveDisplayName(normalized);
    const host = createHost({ displayName: name, baseUrl: normalized });
    setHosts((prev) => [...prev, host]);
    setActiveHostId(host.id);
    setShowHostModal(false);
  };

  const handleUpdateHost = (hostId, updates) => {
    setHosts((prev) =>
      prev.map((host) => {
        if (host.id !== hostId) return host;
        const normalized = normalizeBaseUrl(updates.baseUrl || host.baseUrl);
        return {
          ...host,
          displayName: updates.displayName || host.displayName,
          baseUrl: normalized,
        };
      })
    );
  };

  const handleRemoveHost = (hostId) => {
    setHosts((prev) => prev.filter((host) => host.id !== hostId));
    if (activeHostId === hostId) {
      setActiveHostId("");
    }
  };

  const handlePlay = (payload) => {
    setPlayback(payload);
    setActiveTab("player");
  };

  return (
    <div className="app">
      <TopTabs activeTab={activeTab} onChange={setActiveTab} />
      <div className="app-content">
        {activeTab === "library" ? (
          <MediaLibrary
            host={activeHost}
            onOpenHostModal={() => setShowHostModal(true)}
            onPlay={handlePlay}
          />
        ) : (
          <VideoPlayer
            playback={playback}
            host={activeHost}
            onBack={() => setActiveTab("library")}
          />
        )}
      </div>
      {showHostModal && (
        <HostModal
          hosts={hosts}
          activeHostId={activeHostId}
          onClose={() => setShowHostModal(false)}
          onAddHost={handleAddHost}
          onUpdateHost={handleUpdateHost}
          onRemoveHost={handleRemoveHost}
          onSetActive={(id) => {
            setActiveHostId(id);
            setShowHostModal(false);
          }}
        />
      )}
    </div>
  );
}
