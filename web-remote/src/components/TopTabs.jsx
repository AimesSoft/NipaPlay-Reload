import React from "react";

const tabs = [
  { id: "player", label: "视频播放" },
  { id: "library", label: "媒体库" },
];

export default function TopTabs({ activeTab, onChange }) {
  return (
    <div className="top-tabs">
      <div className="logo">NipaPlay</div>
      <div className="tab-list">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            type="button"
            className={`tab-item ${activeTab === tab.id ? "active" : ""}`}
            onClick={() => onChange(tab.id)}
          >
            {tab.label}
            {activeTab === tab.id && <span className="tab-indicator" />}
          </button>
        ))}
      </div>
    </div>
  );
}
