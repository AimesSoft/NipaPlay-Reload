# Database upsert/link 测试输出

测试文件: `test/database/upsert_link_test.dart`

执行命令: 

```bash
flutter test --no-pub --reporter expanded test/database/upsert_link_test.dart
```

## Session 1: 初始化内存数据库

| 表                     | 行数 | 状态 |
| ---------------------- | ---: | ---- |
| `anime`                |    0 | 空   |
| `episode`              |    0 | 空   |
| `dandanplay_anime`     |    0 | 空   |
| `dandanplay_episode`   |    0 | 空   |
| `bangumi_anime`        |    0 | 空   |
| `bangumi_episode`      |    0 | 空   |
| `asset_episode`        |    0 | 空   |
| `episode_watch_status` |    0 | 空   |

## Session 2: 首次写入

### `anime`

| anime_id |
| -------: |
|        1 |
|        2 |

### `episode`

| episode_id | anime_id |
| ---------: | -------: |
|          1 |        1 |
|          2 |        1 |
|          3 |        2 |
|          4 |        2 |

### `dandanplay_anime`

| dandanplay_anime_id | anime_id |
| ------------------: | -------: |
|                  10 |        1 |

### `dandanplay_episode`

| dandanplay_episode_id | dandanplay_anime_id | episode_id |
| --------------------: | ------------------: | ---------: |
|                   101 |                  10 |          1 |
|                   102 |                  10 |          2 |

### `bangumi_anime`

| bangumi_anime_id | anime_id |
| ---------------: | -------: |
|               20 |        2 |

### `bangumi_episode`

| bangumi_episode_id | bangumi_anime_id | episode_id |
| -----------------: | ---------------: | ---------: |
|                201 |               20 |          3 |
|                202 |               20 |          4 |

| 空表                   | 行数 |
| ---------------------- | ---: |
| `asset_episode`        |    0 |
| `episode_watch_status` |    0 |

## Session 3: 增量写入

### `anime`

| anime_id |
| -------: |
|        1 |
|        2 |

### `episode`

| episode_id | anime_id |
| ---------: | -------: |
|          1 |        1 |
|          2 |        1 |
|          3 |        2 |
|          4 |        2 |
|          5 |        1 |

### `dandanplay_anime`

| dandanplay_anime_id | anime_id |
| ------------------: | -------: |
|                  10 |        1 |

### `dandanplay_episode`

| dandanplay_episode_id | dandanplay_anime_id | episode_id |
| --------------------: | ------------------: | ---------: |
|                   101 |                  10 |          1 |
|                   102 |                  10 |          2 |
|                   103 |                  10 |          5 |

### `bangumi_anime`

| bangumi_anime_id | anime_id |
| ---------------: | -------: |
|               20 |        2 |

### `bangumi_episode`

| bangumi_episode_id | bangumi_anime_id | episode_id |
| -----------------: | ---------------: | ---------: |
|                201 |               20 |          3 |
|                202 |               20 |          4 |

| 空表                   | 行数 |
| ---------------------- | ---: |
| `asset_episode`        |    0 |
| `episode_watch_status` |    0 |

## Session 4: 建立 Anime 关联

### `anime`

| anime_id |
| -------: |
|     9000 |

### `episode`

| episode_id | anime_id |
| ---------: | -------: |
|          1 |     9000 |
|          2 |     9000 |
|          3 |     9000 |
|          4 |     9000 |
|          5 |     9000 |

### `dandanplay_anime`

| dandanplay_anime_id | anime_id |
| ------------------: | -------: |
|                  10 |     9000 |

### `dandanplay_episode`

| dandanplay_episode_id | dandanplay_anime_id | episode_id |
| --------------------: | ------------------: | ---------: |
|                   101 |                  10 |          1 |
|                   102 |                  10 |          2 |
|                   103 |                  10 |          5 |

### `bangumi_anime`

| bangumi_anime_id | anime_id |
| ---------------: | -------: |
|               20 |     9000 |

### `bangumi_episode`

| bangumi_episode_id | bangumi_anime_id | episode_id |
| -----------------: | ---------------: | ---------: |
|                201 |               20 |          3 |
|                202 |               20 |          4 |

| 空表                   | 行数 |
| ---------------------- | ---: |
| `asset_episode`        |    0 |
| `episode_watch_status` |    0 |

## Session 5: 建立 Episode 关联

### `anime`

| anime_id |
| -------: |
|     9000 |

### `episode`

| episode_id | anime_id |
| ---------: | -------: |
|          2 |     9000 |
|          4 |     9000 |
|          5 |     9000 |
|       9101 |     9000 |

### `dandanplay_anime`

| dandanplay_anime_id | anime_id |
| ------------------: | -------: |
|                  10 |     9000 |

### `dandanplay_episode`

| dandanplay_episode_id | dandanplay_anime_id | episode_id |
| --------------------: | ------------------: | ---------: |
|                   101 |                  10 |       9101 |
|                   102 |                  10 |          2 |
|                   103 |                  10 |          5 |

### `bangumi_anime`

| bangumi_anime_id | anime_id |
| ---------------: | -------: |
|               20 |     9000 |

### `bangumi_episode`

| bangumi_episode_id | bangumi_anime_id | episode_id |
| -----------------: | ---------------: | ---------: |
|                201 |               20 |       9101 |
|                202 |               20 |          4 |

| 空表                   | 行数 |
| ---------------------- | ---: |
| `asset_episode`        |    0 |
| `episode_watch_status` |    0 |

## Session 6: 建立视频资产关联

### `anime`

| anime_id |
| -------: |
|     9000 |

### `episode`

| episode_id | anime_id |
| ---------: | -------: |
|          2 |     9000 |
|          4 |     9000 |
|          5 |     9000 |
|       9101 |     9000 |

### `dandanplay_anime`

| dandanplay_anime_id | anime_id |
| ------------------: | -------: |
|                  10 |     9000 |

### `dandanplay_episode`

| dandanplay_episode_id | dandanplay_anime_id | episode_id |
| --------------------: | ------------------: | ---------: |
|                   101 |                  10 |       9101 |
|                   102 |                  10 |          2 |
|                   103 |                  10 |          5 |

### `bangumi_anime`

| bangumi_anime_id | anime_id |
| ---------------: | -------: |
|               20 |     9000 |

### `bangumi_episode`

| bangumi_episode_id | bangumi_anime_id | episode_id |
| -----------------: | ---------------: | ---------: |
|                201 |               20 |       9101 |
|                202 |               20 |          4 |

### `asset_episode`

| asset_pre16mib_md5                 | episode_id | link_options | danmaku_offset_dandanplay | danmaku_offset_user | duration | internal_subtitle_track_count |
| ---------------------------------- | ---------: | ------------ | ------------------------: | ------------------: | -------- | ----------------------------- |
| `000102030405060708090a0b0c0d0e0f` |       9101 | `00000001`   |                       1.5 |                 2.0 | `null`   | `null`                        |

### `episode_watch_status`

| 行数 | 状态 |
| ---: | ---- |
|    0 | 空   |

## 结果

| 检查项                         | 结果 |
| ------------------------------ | ---- |
| Dandanplay/Bangumi 首次 upsert | 通过 |
| Dandanplay Episode 增量 upsert | 通过 |
| Anime 统一 ID 关联             | 通过 |
| Episode 统一 ID 关联           | 通过 |
| 视频资产关联 Episode           | 通过 |
| 关联选项及弹幕偏移读写         | 通过 |
