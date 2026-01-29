import React from "react";
import { IoSearchOutline, IoCloseCircle } from "react-icons/io5";

export default function ControlBar({
  searchValue,
  onSearchChange,
  onClear,
  sortValue,
  onSortChange,
  showSort = true,
  actions = [],
}) {
  return (
    <div className="control-bar">
      <div className="search-box">
        <IoSearchOutline className="search-icon" />
        <input
          value={searchValue}
          onChange={(event) => onSearchChange(event.target.value)}
          placeholder="搜索..."
        />
        {searchValue && (
          <button type="button" className="clear-button" onClick={onClear}>
            <IoCloseCircle />
          </button>
        )}
      </div>
      <div className="control-actions">
        {actions.map((action) => (
          <div key={action.key} className="control-action">
            {action.node}
          </div>
        ))}
      </div>
      {showSort && (
        <select
          className="sort-select"
          value={sortValue}
          onChange={(event) => onSortChange(event.target.value)}
        >
          <option value="date">最近观看</option>
          <option value="name">名称排序</option>
        </select>
      )}
    </div>
  );
}
