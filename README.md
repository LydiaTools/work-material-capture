# 工作过程素材库（低资源试用版）

这个工具参考 WorkReview 的思路，记录“我正在做什么”，不持续录屏。

它每 5 秒用 macOS 原生接口看一次当前应用和窗口。只有工作状态发生变化时才写一条记录；应用或窗口切换后最多留一张截图，同一工作画面最多每 120 秒留一张。它不录音、不录视频、不实时 OCR，也不实时调用 AI。

## 保存什么

- 工作轨迹：`/Volumes/Obsidian知识库/Codex工作运行/30_工作过程素材/工作过程素材库/context/context-timeline.jsonl`
- 关键截图：同目录下的 `context-screenshots/`
- 每日整理：同目录下的 `daily-index/YYYY-MM-DD.json`

图片和记录只写外接硬盘。外盘没有挂载或不可写时直接停止，不回退到内置盘。

## 怎么用

```zsh
# 开始
zsh /Users/macmini/Developer/work-material-capture/bin/start.sh

# 看是否运行，以及当前内存、CPU、图片数量和占用空间
zsh /Users/macmini/Developer/work-material-capture/bin/status.sh

# 暂停 / 恢复 / 停止
zsh /Users/macmini/Developer/work-material-capture/bin/pause.sh
zsh /Users/macmini/Developer/work-material-capture/bin/resume.sh
zsh /Users/macmini/Developer/work-material-capture/bin/stop.sh

# 下班后按规则合并当天工作段；不会调用模型
zsh /Users/macmini/Developer/work-material-capture/bin/organize-day.sh
```

目前不设开机启动。先在真实工作中试用，确认资源占用和截图内容都合适，再决定是否常驻。

## 资源保护

- 空闲 2 分钟后不截图。
- 系统出现内存压力时暂停截图。
- 记录器本身超过 80MB 内存或平均 CPU 超过 2% 时进入降级；连续 60 秒超限就退出。
- 关闭主界面、OCR、AI、视频编码和声音采集，避免占用正常工作的内存与 CPU。
- 当前测试只证明“空闲路径”可低资源运行；需要在用户真实操作窗口时再验收截图路径。

## 隐私

`config/sensitive-apps.txt` 每行可写一个应用名或 bundle ID。命中后只保留状态，不截图。锁屏、支付、验证码、私聊、客户资料和账号后台仍应人工检查；所有图片默认都是 `unreviewed`、`public_eligible:false`，不能直接发布。

## 以后怎么做视频

先用时间线和关键截图找出某个选题的真实过程，再挑能公开的图片。静态图可以做缩放、标注和前后对比；只有确实需要展示操作手感的节点，第二阶段才补一段很短的动态录屏。这样不会为了偶尔用到的素材全天录制。

## 旧实验

`CaptureSegment.swift`、`capture_loop.sh` 和外盘 `试跑/` 里的文件是连续录屏实验记录。这个方向已经停止，默认命令不会调用它们，也没有后台进程或开机任务。
