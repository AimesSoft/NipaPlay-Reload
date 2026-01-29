import React, { useState } from "react";
import Modal from "./Modal.jsx";

export default function HostModal({
  hosts,
  activeHostId,
  onClose,
  onAddHost,
  onUpdateHost,
  onRemoveHost,
  onSetActive,
}) {
  const [newName, setNewName] = useState("");
  const [newUrl, setNewUrl] = useState("");
  const [editingId, setEditingId] = useState("");
  const [editName, setEditName] = useState("");
  const [editUrl, setEditUrl] = useState("");

  const handleAdd = (event) => {
    event.preventDefault();
    if (!newUrl.trim()) return;
    onAddHost({ displayName: newName.trim(), baseUrl: newUrl.trim() });
    setNewName("");
    setNewUrl("");
  };

  const startEdit = (host) => {
    setEditingId(host.id);
    setEditName(host.displayName || "");
    setEditUrl(host.baseUrl || "");
  };

  const cancelEdit = () => {
    setEditingId("");
    setEditName("");
    setEditUrl("");
  };

  const submitEdit = (event) => {
    event.preventDefault();
    if (!editingId) return;
    onUpdateHost(editingId, {
      displayName: editName.trim(),
      baseUrl: editUrl.trim(),
    });
    cancelEdit();
  };

  return (
    <Modal title="远程访问地址" onClose={onClose} className="host-modal">
      <form className="host-form" onSubmit={handleAdd}>
        <div className="form-row">
          <label>名称</label>
          <input
            value={newName}
            onChange={(event) => setNewName(event.target.value)}
            placeholder="例如：家里电脑"
          />
        </div>
        <div className="form-row">
          <label>URL</label>
          <input
            value={newUrl}
            onChange={(event) => setNewUrl(event.target.value)}
            placeholder="http://192.168.1.3:1180"
            required
          />
        </div>
        <button type="submit" className="primary-button">
          添加并连接
        </button>
      </form>

      <div className="host-list">
        {hosts.length === 0 && <p className="muted">尚未添加任何远程主机</p>}
        {hosts.map((host) => (
          <div
            key={host.id}
            className={`host-row ${host.id === activeHostId ? "active" : ""}`}
          >
            {editingId === host.id ? (
              <form className="host-edit" onSubmit={submitEdit}>
                <input
                  value={editName}
                  onChange={(event) => setEditName(event.target.value)}
                  placeholder="名称"
                />
                <input
                  value={editUrl}
                  onChange={(event) => setEditUrl(event.target.value)}
                  placeholder="URL"
                  required
                />
                <div className="host-actions">
                  <button type="submit" className="ghost-button">
                    保存
                  </button>
                  <button type="button" className="ghost-button" onClick={cancelEdit}>
                    取消
                  </button>
                </div>
              </form>
            ) : (
              <>
                <div>
                  <div className="host-name">{host.displayName || "未命名主机"}</div>
                  <div className="host-url">{host.baseUrl}</div>
                </div>
                <div className="host-actions">
                  <button
                    type="button"
                    className="ghost-button"
                    onClick={() => onSetActive(host.id)}
                  >
                    设为当前
                  </button>
                  <button
                    type="button"
                    className="ghost-button"
                    onClick={() => startEdit(host)}
                  >
                    编辑
                  </button>
                  <button
                    type="button"
                    className="ghost-button danger"
                    onClick={() => onRemoveHost(host.id)}
                  >
                    删除
                  </button>
                </div>
              </>
            )}
          </div>
        ))}
      </div>
    </Modal>
  );
}
