# 观看记录存储优化方案

## 背景

原有的观看记录存储使用JSON文件，随着用户观看记录增多，JSON文件读写性能下降，导致UI操作可能出现卡顿。

## 优化方案

将观看记录存储从JSON文件迁移到SQLite数据库，以提高数据读写性能和应用响应速度。

## 实现细节

### 1. 新增文件

- `lib/models/watch_history_database.dart`：SQLite数据库接口类

### 2. 修改文件

- `lib/providers/watch_history_provider.dart`：更新Provider以使用数据库
- `lib/utils/video_player_state.dart`：更新播放器状态管理中的观看记录保存逻辑

### 3. 数据库结构设计

```sql
CREATE TABLE watch_history(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  file_path TEXT UNIQUE NOT NULL,
  anime_name TEXT NOT NULL,
  episode_title TEXT,
  episode_id INTEGER,
  anime_id INTEGER,
  watch_progress REAL NOT NULL,
  last_position INTEGER NOT NULL,
  duration INTEGER NOT NULL,
  last_watch_time TEXT NOT NULL,
  thumbnail_path TEXT,
  is_from_scan INTEGER NOT NULL
)

-- 创建索引以加快查询
CREATE INDEX idx_file_path ON watch_history(file_path)
CREATE INDEX idx_anime_id ON watch_history(anime_id)
CREATE INDEX idx_last_watch_time ON watch_history(last_watch_time)
```

### 4. 迁移策略

- 应用启动时，`WatchHistoryDatabase.migrateFromJson()`方法会检查数据库是否为空
- 如果为空，则从JSON文件读取历史记录并导入到数据库
- 迁移过程放在事务中执行，保证数据一致性
- 迁移成功后执行以下操作：
  1. 自动备份原JSON文件（创建`.bak.migrated`备份）
  2. 删除原JSON文件，防止重复创建和累积存储空间
  3. 清理所有其他相关备份文件（`.bak`，`.bak.*`，`.recovered.*`等）
  4. 设置`WatchHistoryManager.setMigratedToDatabase(true)`，防止再次操作JSON文件
- 导入完成后，设置标志避免重复迁移
- 即使在应用重启后，`WatchHistoryManager`也会自动检测数据库存在并禁用JSON文件操作

### 5. 性能优化

- 使用SQLite索引提高查询速度
- 通过事务批量处理数据，减少磁盘IO
- 使用常量避免字符串重复构造
- 实现缓存机制减少数据库访问次数
- 处理文件路径问题，特别是在iOS上的`/private`前缀问题

### 6. 兼容性保证

- 保持`WatchHistoryItem`模型类不变，确保与现有代码兼容
- `WatchHistoryProvider`接口保持向后兼容，只修改内部实现
- 迁移过程透明，用户无需手动操作

## 预期效果

1. **性能提升**：数据读写速度显著提高，UI响应更流畅
2. **内存占用**：减少内存中缓存的数据量，降低内存占用
3. **稳定性**：避免大型JSON文件解析和写入时可能出现的问题
4. **扩展性**：为将来的功能（如高级搜索、过滤等）提供基础

## 已解决的问题

1. JSON文件损坏风险
2. 大型JSON文件解析缓慢问题
3. 数据写入时的并发问题
4. iOS路径前缀问题处理

## 注意事项

使用SQLite数据库需要确保在各平台上正确配置SQLite依赖：
- 在iOS和Android上已内置SQLite
- 在桌面平台（Windows/macOS/Linux）上使用`sqflite_common_ffi`

## 未来改进方向

1. 实现更复杂的查询功能，如按动画名称分组查询
2. 添加批量导入/导出功能
3. 优化大量数据的分页加载 