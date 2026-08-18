# 数据库结构

项目目前有两条**独立**的 SQLite 初始化路径, 不能将其视为同一数据库的不同版本.

旧的不动, 迁移向新的.

| 数据库              | 初始化入口                               | 版本/位置                                         |
| ------------------- | ---------------------------------------- | ------------------------------------------------- |
| 媒体库数据库 (新)   | `DatabaseService.initialize(dbFilePath)` | 调用方指定路径; `version: 2`                      |
| 观看历史数据库 (旧) | `WatchHistoryDatabase.instance.database` | 应用存储目录中的 `watch_history.db`; `version: 1` |

## 媒体库数据库 (新)

### `anime`

| 字段       | 类型    | 约束        |
| ---------- | ------- | ----------- | ------ |
| `anime_id` | INTEGER | PRIMARY KEY | 人工键 |

### `episode`

| 字段         | 类型    | 约束        |
| ------------ | ------- | ----------- | ------ |
| `episode_id` | INTEGER | PRIMARY KEY | 人工键 |

> 把所有 anime_id 和 episode_id 的外键引用设置为非空键, 每次往 dandanplay_anime/dandanplay_episode/bangumi_anime/bangumi_episode 插入新数据时, 必须先在 anime/episode 表中创建对应的记录.

### `dandanplay_anime`

| 字段                  | 类型    | 约束                  | 说明                      |
| --------------------- | ------- | --------------------- | ------------------------- |
| `dandanplay_anime_id` | INTEGER | PRIMARY KEY           | 弹弹play 动画 ID          |
| `anime_id`            | INTEGER | NOT NULL, FOREIGN KEY | 关联 `anime.anime_id`     |
| `bangumi_anime_id`    | INTEGER | -                     | 关联的 Bangumi TV 动画 ID |
| `cover_image_url`     | TEXT    | -                     | 封面 URL                  |
| `title`               | TEXT    | -                     | 标题                      |
| `description`         | TEXT    | -                     | 简介                      |
| `updated_at`          | TEXT    | NOT NULL              | 最后更新时间              |

### `dandanplay_episode`

| 字段                    | 类型    | 约束                  | 说明                                         |
| ----------------------- | ------- | --------------------- | -------------------------------------------- |
| `dandanplay_episode_id` | INTEGER | PRIMARY KEY           | 弹弹play 剧集 ID                             |
| `episode_id`            | INTEGER | NOT NULL, FOREIGN KEY | 关联 `episode.episode_id`                    |
| `dandanplay_anime_id`   | INTEGER | NOT NULL, FOREIGN KEY | 关联 `dandanplay_anime.dandanplay_anime_id`  |
| `title`                 | TEXT    | -                     | 标题                                         |
| `sort_order`            | REAL    | -                     | 剧集排序值                                   |
| `danmaku_json`          | TEXT    | -                     | 访问 Dandanplay API 返回的弹幕原始 JSON 文本 |
| `updated_at`            | TEXT    | NOT NULL              | 最后更新时间                                 |

外键: `dandanplay_anime_id -> dandanplay_anime.dandanplay_anime_id ON DELETE CASCADE`.

### `bangumi_anime`

保存直接从 Bangumi.tv 获取的动画元数据, 以 Bangumi TV 条目 ID 为主键, 不依赖弹弹play ID.

| 字段                | 类型    | 约束                  | 说明                  |
| ------------------- | ------- | --------------------- | --------------------- |
| `bangumi_anime_id`  | INTEGER | PRIMARY KEY           | Bangumi TV 动画 ID    |
| `anime_id`          | INTEGER | NOT NULL, FOREIGN KEY | 关联 `anime.anime_id` |
| `air_date`          | TEXT    | -                     | 开播日期              |
| `title`             | TEXT    | -                     | 原始标题              |
| `title_cn`          | TEXT    | -                     | 中文标题              |
| `aliases`           | TEXT    | -                     | 别名                  |
| `description`       | TEXT    | -                     | 简介                  |
| `episode_count`     | INTEGER | -                     | 剧集数量              |
| `url_official_site` | TEXT    | -                     | 官方网站              |
| `url_cover`         | TEXT    | -                     | 封面 URL              |
| `updated_at`        | TEXT    | NOT NULL              | 最后更新时间          |

### `bangumi_episode`

| 字段                 | 类型    | 约束                  | 说明                                  |
| -------------------- | ------- | --------------------- | ------------------------------------- |
| `bangumi_episode_id` | INTEGER | PRIMARY KEY           | Bangumi TV 剧集 ID                    |
| `episode_id`         | INTEGER | NOT NULL, FOREIGN KEY | 关联 `episode.episode_id`             |
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

### `file`

| 字段         | 类型    | 约束                  | 说明                      |
| ------------ | ------- | --------------------- | ------------------------- |
| `file_hash`  | TEXT    | PRIMARY KEY           | 文件哈希                  |
| `episode_id` | INTEGER | NOT NULL, FOREIGN KEY | 关联 `episode.episode_id` |
| `file_name`  | TEXT    | -                     | 文件名                    |
| `file_size`  | INTEGER | -                     | 文件大小                  |
| `duration`   | INTEGER | -                     | 媒体时长                  |
| `created_at` | TEXT    | NOT NULL              | 创建时间                  |
| `updated_at` | TEXT    | NOT NULL              | 更新时间                  |

外键: `episode_id -> episode.episode_id ON DELETE SET NULL`. 索引: `idx_media_file_episode_id(episode_id)`.

### `file_danmaku`

| 字段                        | 类型    | 约束        | 说明                                            |
| --------------------------- | ------- | ----------- | ----------------------------------------------- |
| `file_hash`                 | TEXT    | PRIMARY KEY | 文件哈希                                        |
| `dandanplay_episode_id`     | INTEGER | FOREIGN KEY | 关联 `dandanplay_episode.dandanplay_episode_id` |
| `danmaku_offset_dandanplay` | REAL    | -           | Dandanplay 返回的初始弹幕偏移量 (秒)            |
| `danmaku_offset_user`       | REAL    | -           | 用户设置的弹幕偏移量 (秒)                       |

### `watch_history`

| 字段              | 类型    | 约束                     | 说明                      |
| ----------------- | ------- | ------------------------ | ------------------------- |
| `episode_id`      | INTEGER | PRIMARY KEY, FOREIGN KEY | 关联 `episode.episode_id` |
| `file_hash`       | TEXT    | NOT NULL, FOREIGN KEY    | 关联 `file.file_hash`     |
| `watch_progress`  | REAL    | NOT NULL                 | 观看进度                  |
| `last_position`   | INTEGER | NOT NULL                 | 上次播放位置              |
| `duration`        | INTEGER | NOT NULL                 | 时长                      |
| `last_watch_time` | TEXT    | NOT NULL                 | 最后观看时间              |
| `thumbnail_path`  | TEXT    | -                        | 缩略图路径                |

索引: `idx_file_hash(file_hash)`, `idx_episode_id(episode_id)`, `idx_last_watch_time(last_watch_time)`.

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
anime 1 --- N dandanplay_anime
anime 1 --- N bangumi_anime
episode 1 --- N dandanplay_episode
episode 1 --- N bangumi_episode
episode 1 --- N file
dandanplay_episode 1 --- N file_danmaku
file 1 --- 1 file_danmaku
file 1 --- N address
file 1 --- N watch_history
source 1 --- N address
bangumi_anime 1 --- N bangumi_episode
```

`anime` 与 `episode` 是跨数据源的人工主键. DanDanPlay 和 Bangumi 记录通过这些
键表达同一动画或剧集, 不再使用 relation 表. 删除媒体源会级联删除其 `address`;
删除文件会级联删除 `file_danmaku` 和新的媒体库 `watch_history`, 并将
`address.file_hash` 置空.

---

## 观看历史数据库 (旧)

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

- 两个 `watch_history` 表位于不同数据库, 结构和用途不同, 不能互换使用.
- 新媒体库数据库为 `version: 2`; 它不迁移旧媒体库数据库的 relation 表结构.
- `DatabaseService` 在每次 upsert 前写入 `updated_at` 的 ISO 8601 时间；
  业务记录模型不持有或写入最后更新时间。表本身没有时间字段的数据库默认值.
