# AGENTS.md — RightMenu（macOS Finder 右键增强，side project）

自用优先、产品级基础的 Finder 右键工具（对标 iRightMouse）。Swift Package + 原生 Finder Sync 扩展 + 菜单栏控制面板。

## 先读

1. `STATUS.md` — 当前状态与下一步（本项目的 current，轻量版）
2. `docs/ARCHITECTURE.md` — 架构；`docs/MVP.md` — 范围；`docs/DEVELOPMENT.md` — 完整开发指南

## 关键事实

- 本机只有 Swift Command Line Tools，无完整 Xcode：`swift build` / `swift run` 可用，`swift test` 与 `xcodebuild` 不可用，测试跑 `swift run rightmenu-smoke-tests`
- Finder Sync 扩展是沙盒的；paste 执行经 `rightmenu://paste-items` URL scheme 委托给非沙盒宿主 app
- 新增/改名用户可见 action 时**先改 manifest**：原生菜单 `native/rightmenu-native-actions.json`，共享元数据 `actions/rightmenu-actions.json`

## 验证命令

```sh
swift build && swift run rightmenu-smoke-tests
python3 scripts/doctor.py                          # 全量体检
python3 scripts/build-native-finder-sync.py install # 构建+安装 Finder 扩展
```

## 协议

遵循仓库内轻量协议：side project 不设完整 projects 目录，`STATUS.md` 兼任 current + ideas（顶部当前状态只重写不追加，底部想法池只追加）；会话结束更新 STATUS.md 即完成收尾。
