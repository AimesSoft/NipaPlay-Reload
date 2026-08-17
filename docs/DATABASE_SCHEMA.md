# 数据库结构

本文档以当前 Dart 建表语句为准, 更新于 2026-08-17. 项目目前有两条**独立**的 SQLite 初始化路径, 不能将其视为同一数据库的不同版本.

| 数据库         | 初始化入口                               | 版本/位置                                         | 包含的表                                                                                                                                                                                               |
| -------------- | ---------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 媒体库数据库   | `DatabaseService.initialize(dbFilePath)` | 调用方指定路径; `version: 4`                      | `watch_history`, `dandanplay_anime`, `dandanplay_episode`, `file`, `source`, `address`, `bangumi_anime`, `bangumi_episode`, `relation_dandanplay_bangumi_anime`, `relation_dandanplay_bangumi_episode` |
| 观看历史数据库 | `WatchHistoryDatabase.instance.database` | 应用存储目录中的 `watch_history.db`; `version: 1` | `watch_history`, 以及按需创建的 Emby/Jellyfin 映射表                                                                                                                                                   |

> `DatabaseService` 会启用 `PRAGMA foreign_keys = ON`. `WatchHistoryDatabase` 未显式启用该 pragma, 因此其映射表的外键声明不保证被 SQLite 强制执行.

## 媒体库数据库

### `watch_history`

| 字段              | 类型    | 约束                       | 说明           |
| ----------------- | ------- | -------------------------- | -------------- |
| `id`              | INTEGER | PRIMARY KEY, AUTOINCREMENT | 观看记录 ID    |
| `file_path`       | TEXT    | UNIQUE, NOT NULL           | 文件路径       |
| `anime_name`      | TEXT    | NOT NULL                   | 动画名称       |
| `episode_title`   | TEXT    | -                          | 剧集标题       |
| `episode_id`      | INTEGER | -                          | 剧集 ID        |
| `anime_id`        | INTEGER | -                          | 动画 ID        |
| `watch_progress`  | REAL    | NOT NULL                   | 观看进度       |
| `last_position`   | INTEGER | NOT NULL                   | 上次播放位置   |
| `duration`        | INTEGER | NOT NULL                   | 时长           |
| `last_watch_time` | TEXT    | NOT NULL                   | 最后观看时间   |
| `thumbnail_path`  | TEXT    | -                          | 缩略图路径     |
| `is_from_scan`    | INTEGER | NOT NULL                   | 是否由扫描产生 |
| `video_hash`      | TEXT    | -                          | 视频哈希       |

索引: `idx_file_path(file_path)`, `idx_anime_id(anime_id)`, `idx_last_watch_time(last_watch_time)`.

### `dandanplay_anime`

| 字段                  | 类型    | 约束        | 说明             |
| --------------------- | ------- | ----------- | ---------------- |
| `dandanplay_anime_id` | INTEGER | PRIMARY KEY | 弹弹play 动画 ID |
| `cover_image_url`     | TEXT    | -           | 封面 URL         |
| `title`               | TEXT    | -           | 标题             |
| `description`         | TEXT    | -           | 简介             |
| `updated_at`          | TEXT    | NOT NULL    | 最后更新时间     |

### `dandanplay_episode`

| 字段                    | 类型    | 约束                  | 说明                                        |
| ----------------------- | ------- | --------------------- | ------------------------------------------- |
| `dandanplay_episode_id` | INTEGER | PRIMARY KEY           | 弹弹play 剧集 ID                            |
| `dandanplay_anime_id`   | INTEGER | NOT NULL, FOREIGN KEY | 关联 `dandanplay_anime.dandanplay_anime_id` |
| `title`                 | TEXT    | -                     | 标题                                        |
| `sort_order`            | REAL    | -                     | 剧集排序值                                  |
| `updated_at`            | TEXT    | NOT NULL              | 最后更新时间                                |

外键: `dandanplay_anime_id -> dandanplay_anime.dandanplay_anime_id ON DELETE CASCADE`.

### `bangumi_anime`

保存直接从 Bangumi.tv 获取的动画元数据, 以 Bangumi TV 条目 ID 为主键, 不依赖弹弹play ID.

| 字段                | 类型    | 约束        | 说明               |
| ------------------- | ------- | ----------- | ------------------ |
| `bangumi_anime_id`  | INTEGER | PRIMARY KEY | Bangumi TV 动画 ID |
| `air_date`          | TEXT    | -           | 开播日期           |
| `title`             | TEXT    | -           | 原始标题           |
| `title_cn`          | TEXT    | -           | 中文标题           |
| `aliases`           | TEXT    | -           | 别名               |
| `description`       | TEXT    | -           | 简介               |
| `episode_count`     | INTEGER | -           | 剧集数量           |
| `url_official_site` | TEXT    | -           | 官方网站           |
| `url_cover`         | TEXT    | -           | 封面 URL           |
| `updated_at`        | TEXT    | NOT NULL    | 最后更新时间       |

### `bangumi_episode`

| 字段                 | 类型    | 约束                  | 说明                                  |
| -------------------- | ------- | --------------------- | ------------------------------------- |
| `bangumi_episode_id` | INTEGER | PRIMARY KEY           | Bangumi TV 剧集 ID                    |
| `bangumi_anime_id`   | INTEGER | NOT NULL, FOREIGN KEY | 关联 `bangumi_anime.bangumi_anime_id` |
| `episode_number`     | INTEGER | -                     | 剧集编号 (`ep`)                       |
| `sort_order`         | REAL    | -                     | 剧集排序值 (`sort`)                   |
| `air_date`           | TEXT    | -                     | 播出日期                              |
| `duration_seconds`   | INTEGER | -                     | 时长 (秒)                             |
| `title`              | TEXT    | -                     | 原始标题                              |
| `title_cn`           | TEXT    | -                     | 中文标题                              |
| `description`        | TEXT    | -                     | 简介                                  |
| `updated_at`         | TEXT    | NOT NULL              | 最后更新时间                          |

外键: `bangumi_anime_id -> bangumi_anime.bangumi_anime_id ON DELETE CASCADE`. 索引: `idx_bangumi_episode_anime_id(bangumi_anime_id)`.

### `relation_dandanplay_bangumi_anime`

| 字段                  | 类型    | 约束                                             | 说明 |
| --------------------- | ------- | ------------------------------------------------ | ---- |
| `dandanplay_anime_id` | INTEGER | NOT NULL, UNIQUE, PRIMARY KEY(复合), FOREIGN KEY |
| `bangumi_anime_id`    | INTEGER | NOT NULL, UNIQUE, PRIMARY KEY(复合), FOREIGN KEY |

### `relation_dandanplay_bangumi_episode`

| 字段                    | 类型    | 约束                                             | 说明 |
| ----------------------- | ------- | ------------------------------------------------ | ---- |
| `dandanplay_episode_id` | INTEGER | NOT NULL, UNIQUE, PRIMARY KEY(复合), FOREIGN KEY |
| `bangumi_episode_id`    | INTEGER | NOT NULL, UNIQUE, PRIMARY KEY(复合), FOREIGN KEY |

### `file`

| 字段                  | 类型    | 约束        | 说明     |
| --------------------- | ------- | ----------- | -------- |
| `file_hash`           | TEXT    | PRIMARY KEY | 文件哈希 |
| `dandanplay_anime_id` | INTEGER | FOREIGN KEY | 关联动画 |
| `episode_id`          | INTEGER | FOREIGN KEY | 关联剧集 |
| `file_name`           | TEXT    | -           | 文件名   |
| `file_size`           | INTEGER | -           | 文件大小 |
| `duration`            | INTEGER | -           | 媒体时长 |
| `created_at`          | TEXT    | NOT NULL    | 创建时间 |
| `updated_at`          | TEXT    | NOT NULL    | 更新时间 |

外键: `dandanplay_anime_id -> dandanplay_anime.dandanplay_anime_id ON DELETE SET NULL`; `episode_id -> dandanplay_episode.dandanplay_episode_id ON DELETE SET NULL`. 索引: `idx_media_file_anime_id(dandanplay_anime_id)`, `idx_media_file_episode_id(episode_id)`.

### `source`

| 字段            | 类型 | 约束        | 说明            |
| --------------- | ---- | ----------- | --------------- |
| `id`            | TEXT | PRIMARY KEY | 媒体源 ID       |
| `source_type`   | TEXT | NOT NULL    | 媒体源类型      |
| `url`           | TEXT | NOT NULL    | 根地址          |
| `username`      | TEXT | -           | 用户名          |
| `password`      | TEXT | -           | 密码            |
| `metadata_json` | TEXT | -           | 扩展元数据 JSON |
| `created_at`    | TEXT | NOT NULL    | 创建时间        |
| `updated_at`    | TEXT | NOT NULL    | 更新时间        |

### `address`

| 字段             | 类型 | 约束                                     | 说明                   |
| ---------------- | ---- | ---------------------------------------- | ---------------------- |
| `source_id`      | TEXT | NOT NULL, PRIMARY KEY(复合), FOREIGN KEY | 关联媒体源             |
| `relative_path`  | TEXT | NOT NULL, PRIMARY KEY(复合)              | 相对媒体源根地址的路径 |
| `file_hash`      | TEXT | FOREIGN KEY                              | 关联文件               |
| `last_synced_at` | TEXT | NOT NULL                                 | 最后同步时间           |

复合主键为 `(source_id, relative_path)`. 外键: `source_id -> source.id ON DELETE CASCADE`; `file_hash -> file.file_hash ON DELETE SET NULL`. 索引: `idx_media_address_file_hash(file_hash)`.

### 表关系

```text
dandanplay_anime 1 --- N dandanplay_episode
dandanplay_anime 1 --- N file
dandanplay_episode 1 --- N file
source 1 --- N address
file 1 --- N address
bangumi_anime 1 --- N bangumi_episode
dandanplay_anime 1 --- 1 bangumi_anime (by relation_dandanplay_bangumi_anime)
dandanplay_episode 1 --- 1 bangumi_episode (by relation_dandanplay_bangumi_episode)
```

删除动画会级联删除其剧集; 直接关联到该动画或其剧集的 `file` 外键会被置空. 删除媒体源会级联删除其 `address`; 删除文件会将关联 `address.file_hash` 置空.

## 观看历史数据库

### `watch_history`

| 字段              | 类型    | 约束                       | 说明           |
| ----------------- | ------- | -------------------------- | -------------- |
| `id`              | INTEGER | PRIMARY KEY, AUTOINCREMENT | 观看记录 ID    |
| `file_path`       | TEXT    | UNIQUE, NOT NULL           | 文件路径       |
| `anime_name`      | TEXT    | NOT NULL                   | 动画名称       |
| `episode_title`   | TEXT    | -                          | 剧集标题       |
| `episode_id`      | INTEGER | -                          | 剧集 ID        |
| `anime_id`        | INTEGER | -                          | 动画 ID        |
| `watch_progress`  | REAL    | NOT NULL                   | 观看进度       |
| `last_position`   | INTEGER | NOT NULL                   | 上次播放位置   |
| `duration`        | INTEGER | NOT NULL                   | 时长           |
| `last_watch_time` | TEXT    | NOT NULL                   | 最后观看时间   |
| `thumbnail_path`  | TEXT    | -                          | 缩略图路径     |
| `is_from_scan`    | INTEGER | NOT NULL                   | 是否由扫描产生 |

索引: `idx_file_path(file_path)`, `idx_anime_id(anime_id)`, `idx_last_watch_time(last_watch_time)`. 该表没有外键, 也没有 `video_hash` 字段.

### Jellyfin 映射表

| 表                            | 字段                                         | 类型与约束                         |
| ----------------------------- | -------------------------------------------- | ---------------------------------- |
| `jellyfin_dandanplay_mapping` | `id`                                         | INTEGER PRIMARY KEY AUTOINCREMENT  |
|                               | `jellyfin_series_id`                         | TEXT NOT NULL                      |
|                               | `jellyfin_series_name`, `jellyfin_season_id` | TEXT, 可空                         |
|                               | `dandanplay_anime_id`                        | INTEGER NOT NULL                   |
|                               | `dandanplay_anime_title`                     | TEXT, 可空                         |
|                               | `created_at`, `updated_at`                   | DATETIME DEFAULT CURRENT_TIMESTAMP |
| `jellyfin_episode_mapping`    | `id`                                         | INTEGER PRIMARY KEY AUTOINCREMENT  |
|                               | `jellyfin_episode_id`                        | TEXT NOT NULL UNIQUE               |
|                               | `jellyfin_index_number`                      | INTEGER, 可空                      |
|                               | `dandanplay_episode_id`                      | INTEGER NOT NULL                   |
|                               | `mapping_id`                                 | INTEGER NOT NULL, FOREIGN KEY      |
|                               | `confirmed`                                  | BOOLEAN DEFAULT FALSE              |
|                               | `created_at`                                 | DATETIME DEFAULT CURRENT_TIMESTAMP |

`jellyfin_dandanplay_mapping` 具有唯一约束 `(jellyfin_series_id, jellyfin_season_id, dandanplay_anime_id)`; `jellyfin_episode_mapping.mapping_id` 引用前者的 `id`, 未声明删除动作和额外索引.

### Emby 映射表

| 表                        | 字段                                 | 类型与约束                         |
| ------------------------- | ------------------------------------ | ---------------------------------- |
| `emby_dandanplay_mapping` | `id`                                 | INTEGER PRIMARY KEY AUTOINCREMENT  |
|                           | `emby_series_id`                     | TEXT NOT NULL                      |
|                           | `emby_series_name`, `emby_season_id` | TEXT, 可空                         |
|                           | `dandanplay_anime_id`                | INTEGER NOT NULL                   |
|                           | `dandanplay_anime_title`             | TEXT, 可空                         |
|                           | `created_at`, `updated_at`           | DATETIME DEFAULT CURRENT_TIMESTAMP |
| `emby_episode_mapping`    | `id`                                 | INTEGER PRIMARY KEY AUTOINCREMENT  |
|                           | `emby_episode_id`                    | TEXT NOT NULL UNIQUE               |
|                           | `emby_index_number`                  | INTEGER, 可空                      |
|                           | `dandanplay_episode_id`              | INTEGER NOT NULL                   |
|                           | `mapping_id`                         | INTEGER NOT NULL, FOREIGN KEY      |
|                           | `confirmed`                          | BOOLEAN DEFAULT FALSE              |
|                           | `created_at`                         | DATETIME DEFAULT CURRENT_TIMESTAMP |

`emby_dandanplay_mapping` 具有唯一约束 `(emby_series_id, emby_season_id, dandanplay_anime_id)`; `emby_episode_mapping.mapping_id` 引用前者的 `id`, 未声明删除动作和额外索引.

```text
jellyfin_dandanplay_mapping 1 --- N jellyfin_episode_mapping
emby_dandanplay_mapping 1 --- N emby_episode_mapping
```

## 当前实现注意事项

- `DatabaseService` 的 `watch_history` 比 `WatchHistoryDatabase` 的同名表多出 `video_hash`. 两者位于不同数据库, 不能互换使用.
- 媒体库数据库会从旧版本升级到 v4, 以创建 `bangumi_anime`, `bangumi_episode`, 两张 relation 表及索引; 它还会逐字比对各表建表 SQL, 现有数据库结构与预期不一致时会抛出 `StateError`.
- 媒体库记录模型会在未传入时间时写入 ISO 8601 字符串; 媒体库表本身没有时间字段的数据库默认值.
