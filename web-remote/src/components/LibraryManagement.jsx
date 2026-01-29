import React, { useEffect, useMemo, useState } from "react";
import {
  addRemoteFolder,
  browseRemoteDirectory,
  getManagementFolders,
  getScanStatus,
  removeRemoteFolder,
  rescanRemote,
  buildManageStreamUrl,
} from "../lib/api.js";
import ControlBar from "./ControlBar.jsx";
import IconButton from "./IconButton.jsx";
import Modal from "./Modal.jsx";
import {
  IoRefreshOutline,
  IoAddCircleOutline,
  IoFlashOutline,
  IoLinkOutline,
  IoFolderOpenOutline,
  IoTrashOutline,
} from "react-icons/io5";

function AddFolderModal({ onClose, onSubmit }) {
  const [path, setPath] = useState("");

  const handleSubmit = (event) => {
    event.preventDefault();
    if (!path.trim()) return;
    onSubmit(path.trim());
    setPath("");
  };

  return (
    <Modal title="添加媒体文件夹" onClose={onClose} className="add-folder-modal">
      <form className="host-form" onSubmit={handleSubmit}>
        <div className="form-row">
          <label>路径</label>
          <input
            value={path}
            onChange={(event) => setPath(event.target.value)}
            placeholder="例如：/Volumes/Media 或 D:\\Anime"
            required
          />
        </div>
        <button type="submit" className="primary-button">
          添加并扫描
        </button>
      </form>
    </Modal>
  );
}

function FolderEntries({ entries, expanded, entriesMap, onOpen, onPlay, depth = 0 }) {
  return (
    <div className="folder-entries">
      {entries.map((entry) => (
        <div key={`${entry.path}-${entry.name}`}>
          {entry.isDirectory ? (
            <>
              <button
                type="button"
                className="folder-row"
                style={{ paddingLeft: 16 + depth * 14 }}
                onClick={() => onOpen(entry.path)}
              >
                <IoFolderOpenOutline />
                <span>{entry.name || entry.path}</span>
              </button>
              {expanded[entry.path] && entriesMap[entry.path] && (
                <FolderEntries
                  entries={entriesMap[entry.path]}
                  expanded={expanded}
                  entriesMap={entriesMap}
                  onOpen={onOpen}
                  onPlay={onPlay}
                  depth={depth + 1}
                />
              )}
            </>
          ) : (
            <button
              type="button"
              className="file-row"
              style={{ paddingLeft: 16 + depth * 14 }}
              onClick={() => onPlay(entry)}
            >
              <span>{entry.name || entry.path}</span>
            </button>
          )}
        </div>
      ))}
    </div>
  );
}

export default function LibraryManagement({ host, onPlay, onOpenHostModal }) {
  const [folders, setFolders] = useState([]);
  const [scanStatus, setScanStatus] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [search, setSearch] = useState("");
  const [sort, setSort] = useState("date");
  const [expanded, setExpanded] = useState({});
  const [entriesMap, setEntriesMap] = useState({});
  const [loadingPaths, setLoadingPaths] = useState({});
  const [showAddModal, setShowAddModal] = useState(false);

  const refresh = async () => {
    if (!host) return;
    setLoading(true);
    setError("");
    try {
      const payload = await getManagementFolders(host.baseUrl);
      const folderList = payload?.data?.folders ?? payload?.folders ?? [];
      setFolders(folderList);
      const status = await getScanStatus(host.baseUrl);
      setScanStatus(status?.data ?? status);
    } catch (err) {
      setError(err.message || "加载失败");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    refresh();
  }, [host]);

  useEffect(() => {
    if (!scanStatus?.isScanning) return undefined;
    const timer = setInterval(async () => {
      try {
        const status = await getScanStatus(host.baseUrl);
        setScanStatus(status?.data ?? status);
      } catch {
        // ignore polling errors
      }
    }, 1000);
    return () => clearInterval(timer);
  }, [scanStatus?.isScanning, host]);

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    const result = folders.filter((folder) => {
      if (!query) return true;
      return (
        folder.name.toLowerCase().includes(query) ||
        folder.path.toLowerCase().includes(query)
      );
    });
    if (sort === "name") {
      result.sort((a, b) => a.name.localeCompare(b.name));
    } else {
      result.sort((a, b) => a.path.localeCompare(b.path));
    }
    return result;
  }, [folders, search, sort]);

  const openFolder = async (path) => {
    if (entriesMap[path]) {
      setExpanded((prev) => ({ ...prev, [path]: !prev[path] }));
      return;
    }
    setLoadingPaths((prev) => ({ ...prev, [path]: true }));
    try {
      const payload = await browseRemoteDirectory(host.baseUrl, path);
      const entries = payload?.data?.entries ?? payload?.entries ?? [];
      setEntriesMap((prev) => ({ ...prev, [path]: entries }));
      setExpanded((prev) => ({ ...prev, [path]: true }));
    } catch (err) {
      setError(err.message || "加载目录失败");
    } finally {
      setLoadingPaths((prev) => ({ ...prev, [path]: false }));
    }
  };

  const handleAddFolder = async (path) => {
    if (!host) return;
    try {
      await addRemoteFolder(host.baseUrl, {
        path,
        scan: true,
        skipPreviouslyMatchedUnwatched: false,
      });
      setShowAddModal(false);
      refresh();
    } catch (err) {
      setError(err.message || "添加失败");
    }
  };

  const handleRemoveFolder = async (path) => {
    if (!host) return;
    try {
      await removeRemoteFolder(host.baseUrl, path);
      refresh();
    } catch (err) {
      setError(err.message || "移除失败");
    }
  };

  const handleRescan = async () => {
    if (!host) return;
    try {
      await rescanRemote(host.baseUrl, {
        skipPreviouslyMatchedUnwatched: true,
      });
      refresh();
    } catch (err) {
      setError(err.message || "刷新失败");
    }
  };

  const actions = [
    {
      key: "refresh",
      node: (
        <IconButton
          icon={IoRefreshOutline}
          title="刷新库管理"
          onClick={refresh}
          disabled={!host}
        />
      ),
    },
    {
      key: "add",
      node: (
        <IconButton
          icon={IoAddCircleOutline}
          title="添加文件夹"
          onClick={() => setShowAddModal(true)}
          disabled={!host}
        />
      ),
    },
    {
      key: "rescan",
      node: (
        <IconButton
          icon={IoFlashOutline}
          title="智能刷新"
          onClick={handleRescan}
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
      {scanStatus?.isScanning && (
        <div className="scan-status">
          <div>{scanStatus.message || "正在扫描..."}</div>
          <div className="scan-bar">
            <div
              className="scan-progress"
              style={{ width: `${Math.round((scanStatus.progress || 0) * 100)}%` }}
            />
          </div>
        </div>
      )}
      {error && <div className="error-banner">{error}</div>}
      {loading && <div className="loading">正在加载库管理...</div>}
      {!loading && filtered.length === 0 && (
        <div className="empty-state">远程端未添加媒体文件夹</div>
      )}
      <div className="management-grid">
        {filtered.map((folder) => (
          <div key={folder.path} className="management-card">
            <div className="management-header">
              <div>
                <div className="folder-title">{folder.name || folder.path}</div>
                <div className="folder-path">{folder.path}</div>
              </div>
              <div className="folder-actions">
                <button
                  type="button"
                  className="ghost-button danger"
                  onClick={() => handleRemoveFolder(folder.path)}
                >
                  <IoTrashOutline />
                </button>
                <button
                  type="button"
                  className="ghost-button"
                  onClick={() => openFolder(folder.path)}
                >
                  {expanded[folder.path] ? "收起" : "展开"}
                </button>
              </div>
            </div>
            {loadingPaths[folder.path] && (
              <div className="loading">正在加载目录...</div>
            )}
            {expanded[folder.path] && entriesMap[folder.path] && (
              <FolderEntries
                entries={entriesMap[folder.path]}
                expanded={expanded}
                entriesMap={entriesMap}
                onOpen={openFolder}
                onPlay={(entry) => {
                  const url = buildManageStreamUrl(host.baseUrl, entry.path);
                  onPlay({
                    url,
                    title: entry.animeName || entry.name || "远程文件",
                    episodeTitle: entry.episodeTitle || entry.name,
                    animeId: entry.animeId,
                    episodeId: entry.episodeId,
                  });
                }}
              />
            )}
          </div>
        ))}
      </div>
      {showAddModal && (
        <AddFolderModal
          onClose={() => setShowAddModal(false)}
          onSubmit={handleAddFolder}
        />
      )}
    </div>
  );
}
