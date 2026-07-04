# RightMenu · STATUS

更新时间：2026-07-04

## 当前状态

- Phase 1（自用核心）action 集已基本落地：路径/URL/文件名/父目录/Markdown 链接/shell 转义路径复制、Windows 式复制剪切粘贴、新建 text/md/json/yaml、Terminal/VS Code/Cursor 打开
- 原生链路可用：`RightMenuCore` 包 + `rightmenu-cli` + Finder Sync 扩展（`build-native-finder-sync.py install` 安装）+ `RightMenuNative.app` 控制面板
- 菜单栏剪贴板历史可用：`RightMenuNative.app` 提供 `剪贴板历史` 窗口，本地记录文本/链接/文件路径/代码/图片，支持 `⌃⌥V` 快捷唤出、搜索、复制、固定、删除
- 右键配置面板保留：状态菜单 `右键配置面板` 和 `rightmenu://control-panel` 都可以打开原来的 Finder 右键动作启用/隐藏配置
- 本机验证通过：`python3 scripts/doctor.py` 10/10；Finder 右键 `复制路径` 写入的路径会进入剪贴板历史
- 未启用：`swift test`（工具链缺模块）、`xcodebuild` 产品级 app 目标（需完整 Xcode）、`macos/RightMenuApp` SwiftUI 壳

## 下一步

- 给剪贴板历史补设置项：快捷键自定义、保留条数、开机启动、是否记录图片、是否隐藏敏感片段
- 后续产品化再考虑更强分类：代码语言识别、路径可达性、URL 标题抓取、开发者常用片段聚合

## 想法池（只追加）

- 自定义 action pack 支持（README 既定远期目标）
