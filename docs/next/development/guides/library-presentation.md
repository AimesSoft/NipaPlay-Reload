# 首页、媒体库分类与图片

## 先读事实

用 `media.library.search_merged` 查作品及可播放状态，`ui.library.page` / `ui.library.items` 查来源与类别。远端离线时可能看到缓存；服务器作品用于合并分类须有已接受身份。

## 选择呈现

- `ui.shelves.put` 设置首页主视觉或命名书架，书架项使用已有媒体库作品并按输入顺序呈现；`ui.shelves.remove` 移除整处或单项。主视觉一次一部，不提供可配置轮播。
- `ui.present` 在当前对话摆作品、剧集、候选、任务或选项卡片；部分外部作品可用来源引用。它不会因此自动入库。
- `ui.library.put` / `configure` 管理条件、手选或来源原样类别；`move`、`remove`、`restore` 调整与恢复。条件按已有事实持续计算，未知值不满足对应条件；原始类别隐藏与排序只影响本机，不改来源文件。原始与整理形式可切换。
- `media.artwork.set` 用可读取的 HTTP(S) 地址或本地文件设置海报、背景、Logo 或剧集截图；`clear` 清除覆盖并显示来源事实。设置已有图片不要求生成图片能力；首页选择作品与修改其背景是不同操作。

## 作品详情页

剧集下面依次是角色、演员、制作人员、图片、信息和外部链接；没有内容的区块不出现。页面每处取哪个字段、按什么规则选来源：

| 位置 | 显示的字段 | 由规则的哪部分决定 | 默认来源顺序 |
| --- | --- | --- | --- |
| `hero.title` | title | `sources.title` | bangumi → tmdb → dandanplay |
| `hero.originalTitle` | originalTitle | `sources.originalTitle` | tmdb → bangumi → dandanplay |
| `hero.meta` | 年份、集数或时长、制作公司、评分 | `sources.year` / `episodeCount` / `runtimeMs` / `studio`；`ratings` | tmdb → bangumi → dandanplay；评分全部显示 |
| `copy.overview` | overview | `sources.overview` | tmdb 优先，同语言时取更完整的一份 |
| `section.characters` | Bangumi 角色与声优 | `sections`、`limits.characters` | — |
| `section.cast` | TMDB 演员（饰演角色），或 Bangumi 声优 | `sources.people`、`sections`、`limits.cast` | tmdb → bangumi；默认有角色时不重复列演员 |
| `section.crew` | TMDB 主创与职员（导演、原作、系列构成、音乐……），或 Bangumi staff | `sources.people`、`sections`、`limits.crew` | tmdb → bangumi |
| `section.gallery` | TMDB 剧照、背景与海报（打开详情页时读取） | `sections`、`limits.gallery` | — |
| `section.facts` | 原名、类型、首播/上映、完结、状态、季集、时长、形式、播出、制作、国家、原始语言、预算与票房、标签 | `sources.genres`、`sources.tags`、`sections` | 标签 bangumi 优先，其余 tmdb 优先 |
| `section.links` | TMDB、Bangumi、IMDb、弹弹play、官网 | `sections` | — |

- 读：`media.metadata.ui_facts` 的 `presentation` 给出每个字段当前的值、来自哪个来源、其他来源能给的值和可显示的评分；`ui.detail.layout` 给出默认规则、本机规则和某部作品的规则。
- 改：`ui.detail.layout.set`，`scope` 为 `global`（本机所有作品）或作品 ID（只这一部，随作品合并保留）；`rule` 整份替换该范围的规则，省略的部分退回上一层（作品 → 本机 → 默认）；`reset: true` 删除。规则点名某字段的来源顺序后，排在前面且有该字段的来源胜出，不再按语言或长短挑；同一来源里中文仍优先。`ratings` 只显示点名的来源并按顺序；`sections` 决定区块顺序，没列的隐藏。
- 用户或梨花对单项文字的修改（`media.metadata.override` / `put`）始终显示在任何来源之前；规则只决定来源之间怎么选。
- 合并媒体库里只在别的设备上的作品，规则在那台设备上改。

## 核对和恢复

确认目标作品、顺序、图片角色和来源，再读取首页或类别结果并打开页面检查。图片需要成功读取和解码；来源缺少图片不代表自动生成。清除覆盖不会删除原文件；类别隐藏/移除不删除源文件。涉及媒体身份或作品合并见[媒体身份](media-identity.md)；实时参数以目标 `nipa describe` 为准。
