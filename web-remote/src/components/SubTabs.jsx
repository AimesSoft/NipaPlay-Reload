import React from "react";

const tabs = [
  { id: "media", label: "共享媒体库" },
  { id: "management", label: "共享库管理" },
];

export default function SubTabs({ activeTab, onChange }) {
  return (
    <div className="sub-tabs">
      {tabs.map((tab) => (
        <button
          key={tab.id}
          type="button"
          className={`sub-tab ${activeTab === tab.id ? "active" : ""}`}
          onClick={() => onChange(tab.id)}
        >
          {tab.label}
          {activeTab === tab.id && <span className="tab-indicator" />}
        </button>
      ))}
    </div>
  );
}
