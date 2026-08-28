# 数据库结构

> [!IMPORTANT]
> 项目目前有两条**独立**的数据库交互路径, 本文档仅描述**新版数据库结构**.
> 旧的不动, 迁移向新的.

新数据库系统版本: v2

## 主数据库

`nipaplay.db` 是新的主数据库.

### 各表一览

| No. | 表名                 | 中文名         | 说明                                         |
| --: | -------------------- | -------------- | -------------------------------------------- |
|   1 | `anime`              | 番剧表         | 关联不同信息系统的**番剧实体**               |
|   2 | `episode`            | 剧集表         | 关联不同信息系统的**剧集实体**               |
|   3 | `dandanplay_anime`   | 弹弹play番剧表 | 弹弹play番剧实体                             |
|   4 | `dandanplay_episode` | 弹弹play剧集表 | 弹弹play剧集实体                             |
|   5 | `bangumi_anime`      | Bangumi番剧表  | Bangumi番剧实体                              |
|   6 | `bangumi_episode`    | Bangumi剧集表  | Bangumi剧集实体                              |
|   7 | `asset`              | 文件表         | 大小, 时长, 编码等**资产文件本身具有的信息** |
|   8 | `path_asset`         | 文件路径表     | 保存文件在媒体源中的相对路径                 |
|   9 | `asset_episode`      | 文件剧集关联表 | 关联文件与剧集                               |
|  10 | `net_asset`          | 网络资源表     | 保存网络资源的 URL 与对应的文件              |

> [!IMPORTANT]
>
> 1. 所有表在创建时都使用 `STRICT` 模式.
> 2. 连接数据库必须使用 `PRAGMA foreign_keys = ON;` 来启用外键约束.
> 3. 除非特殊说明, 所有表示时间的字段都严格采用 `ISO 8601 / RFC 3339 格式.`

> [!NOTE]
> 关于 [ISO 8601 / RFC 3339](https://www.rfc-editor.org/rfc/rfc3339.html) 格式.
>
> 格式: `YYYY-MM-DDTHH:mm:ss±HH:mm` 或 `YYYY-MM-DDTHH:mm:ssZ`, 其中 `Z` 表示 UTC 时间, `±HH:mm` 表示时区偏移.
> 例如: `2024-06-01T12:34:56Z` 表示 UTC 时间, `2024-06-01T12:34:56+08:00` 表示北京时间.

### `anime`

| 字段       | 类型    | 约束                      |
| ---------- | ------- | ------------------------- | ------ |
| `anime_id` | INTEGER | PRIMARY KEY, CHECK( >= 0) | 人工键 |

### `episode`

| 字段         | 类型    | 约束                                     |
| ------------ | ------- | ---------------------------------------- | --------------------- |
| `episode_id` | INTEGER | PRIMARY KEY, CHECK( >= 0)                | 人工键                |
| `anime_id`   | INTEGER | FOREIGN KEY, NOT NULL, ON DELETE CASCADE | 关联 `anime.anime_id` |

索引: `idx_episode_anime_id(anime_id)`.

> [!NOTE]
> `anime` 与 `episode` 是跨数据源的人工主键. DanDanPlay 和 Bangumi 记录通过这些键表达同一动画或剧集.
>
> 把所有 anime_id 和 episode_id 的外键引用设置为非空键,
> 每次往 dandanplay_anime/dandanplay_episode/bangumi_anime/bangumi_episode/asset_episode 插入新数据时,
> 必须先在 anime/episode 表中创建对应的记录.

### `dandanplay_anime`

| 字段                  | 类型    | 约束                                             | 说明                  |
| --------------------- | ------- | ------------------------------------------------ | --------------------- |
| `dandanplay_anime_id` | INTEGER | PRIMARY KEY, CHECK( >= 0)                        | 弹弹play 动画 ID      |
| `anime_id`            | INTEGER | FOREIGN KEY, NOT NULL, UNIQUE, ON DELETE CASCADE | 关联 `anime.anime_id` |

`anime_id` 唯一, 同一个共通 Anime 在 Dandanplay 表中最多对应一条记录.

### `dandanplay_episode`

| 字段                    | 类型    | 约束                                             | 说明                                        |
| ----------------------- | ------- | ------------------------------------------------ | ------------------------------------------- |
| `dandanplay_episode_id` | INTEGER | PRIMARY KEY, CHECK( >= 0)                        | 弹弹play 剧集 ID                            |
| `dandanplay_anime_id`   | INTEGER | FOREIGN KEY, NOT NULL, ON DELETE CASCADE         | 关联 `dandanplay_anime.dandanplay_anime_id` |
| `episode_id`            | INTEGER | FOREIGN KEY, NOT NULL, UNIQUE, ON DELETE CASCADE | 关联 `episode.episode_id`                   |

外键: `dandanplay_anime_id -> dandanplay_anime.dandanplay_anime_id ON DELETE CASCADE`.

索引: `idx_dandanplay_episode_anime_id(dandanplay_anime_id)`.

`episode_id` 唯一, 同一个共通 Episode 在 Dandanplay 表中最多对应一条记录.

### `bangumi_anime`

保存直接从 Bangumi.tv 获取的动画元数据, 以 Bangumi TV 条目 ID 为主键, 不依赖弹弹play ID.

| 字段               | 类型    | 约束                                             | 说明                  |
| ------------------ | ------- | ------------------------------------------------ | --------------------- |
| `bangumi_anime_id` | INTEGER | PRIMARY KEY, CHECK( >= 0)                        | Bangumi TV 动画 ID    |
| `anime_id`         | INTEGER | FOREIGN KEY, NOT NULL, UNIQUE, ON DELETE CASCADE | 关联 `anime.anime_id` |

`anime_id` 唯一, 同一个共通 Anime 在 Bangumi 表中最多对应一条记录.

### `bangumi_episode`

| 字段                 | 类型    | 约束                                             | 说明                                  |
| -------------------- | ------- | ------------------------------------------------ | ------------------------------------- |
| `bangumi_episode_id` | INTEGER | PRIMARY KEY, CHECK( >= 0)                        | Bangumi TV 剧集 ID                    |
| `bangumi_anime_id`   | INTEGER | FOREIGN KEY, NOT NULL, ON DELETE CASCADE         | 关联 `bangumi_anime.bangumi_anime_id` |
| `episode_id`         | INTEGER | FOREIGN KEY, NOT NULL, UNIQUE, ON DELETE CASCADE | 关联 `episode.episode_id`             |

外键: `bangumi_anime_id -> bangumi_anime.bangumi_anime_id ON DELETE CASCADE`.

索引: `idx_bangumi_episode_anime_id(bangumi_anime_id)`.

`episode_id` 唯一, 同一个共通 Episode 在 Bangumi 表中最多对应一条记录.

> [!NOTE]
> Dandanplay 与 Bangumi 使用不同的关系表, 因此同一个共通 Anime 或 Episode
> 可以同时关联一条 Dandanplay 记录和一条 Bangumi 记录.

### `asset`

唯一标识资产文件内容

| 字段                 | 类型     | 约束         | 说明                                                |
| -------------------- | -------- | ------------ | --------------------------------------------------- |
| `asset_pre16mib_md5` | BLOB(16) | PRIMARY KEY  | **通过文件前 16 Mib 计算得到的 128 bit MD5 哈希值** |
| `asset_size`         | INTEGER  | CHECK( >= 0) | 文件大小                                            |
| `asset_codec`        | TEXT     | -            | 文件编码格式 (mp4, mkv, etc.)                       |
| `asset_sha256`       | BLOB(32) | -            | SHA-256 哈希值, 比 MD5 更安全, 将来或许会用到?      |

### `net_asset`

| 字段                 | 类型     | 约束                            | 说明                            |
| -------------------- | -------- | ------------------------------- | ------------------------------- |
| `net_url`            | TEXT     | PRIMARY KEY                     | 网络资源地址                    |
| `asset_pre16mib_md5` | BLOB(16) | FOREIGN KEY, ON DELETE SET NULL | 关联 `asset.asset_pre16mib_md5` |

索引: `idx_net_asset_asset_pre16mib_md5(asset_pre16mib_md5)`.

### `path_asset`

资产文件保存的位置信息

| 字段                 | 类型     | 约束                                                 | 说明                           |
| -------------------- | -------- | ---------------------------------------------------- | ------------------------------ |
| `source_id`          | INTEGER  | NOT NULL, PRIMARY KEY(复合), DEFAULT 0, CHECK( >= 0) | 根据本字段读取配置文件         |
| `asset_address`      | TEXT     | NOT NULL, PRIMARY KEY(复合), DEFAULT ''              | 相对媒体源根地址的所在目录路径 |
| `asset_name_no_ext`  | TEXT     | NOT NULL, PRIMARY KEY(复合), DEFAULT ''              | 不带扩展名的文件名             |
| `asset_extension`    | TEXT     | NOT NULL, PRIMARY KEY(复合), DEFAULT ''              | 文件后缀                       |
| `updated_at`         | TEXT     | NOT NULL                                             | 更新时间                       |
| `asset_pre16mib_md5` | BLOB(16) | FOREIGN KEY, ON DELETE SET NULL                      | 关联资产                       |
| `asset_created_at`   | TEXT     | -                                                    | 资产创建时间                   |
| `asset_updated_at`   | TEXT     | -                                                    | 资产更新时间                   |

复合主键为 `(source_id, asset_address, asset_name_no_ext, asset_extension)`. 外键: `asset_pre16mib_md5 -> asset.asset_pre16mib_md5 ON DELETE SET NULL`. 索引: `idx_path_asset_asset_pre16mib_md5(asset_pre16mib_md5)`.

- `asset_address`: media/ani/2026-07/
- `asset_name_no_ext`: AnimeName.S01E01
- `asset_extension`: mp4

特殊的, source_id 为 `0` 的媒体源,
根路径固定类似于 `~/.local/share/NipaPlay/assets/` 这样的本地路径.
其他的编号的根路径和详细配置由用户设置.

### `asset_episode`

资产表和剧集表的关联表

只有文件编码格式是视频格式的文件才可能会在 `asset_episode` 表中有记录.

和 `asset` 表记录唯一对应, 保存资产与剧集之间的关联.

| 字段                 | 类型       | 约束                                        | 说明                            |
| -------------------- | ---------- | ------------------------------------------- | ------------------------------- |
| `asset_pre16mib_md5` | `BLOB(16)` | PRIMARY KEY, FOREIGN KEY, ON DELETE CASCADE | 关联 `asset.asset_pre16mib_md5` |
| `episode_id`         | `INTEGER`  | NOT NULL, FOREIGN KEY, ON DELETE CASCADE    | 关联 `episode.episode_id`       |

外键: `asset_pre16mib_md5 -> asset.asset_pre16mib_md5 ON DELETE CASCADE`.

索引: `idx_asset_episode_episode_id(episode_id)`.
