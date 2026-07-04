# Action Matrix

## Implemented in Core

| Area | Action IDs |
| --- | --- |
| Copy | `copy.absolute-paths`, `copy.file-urls`, `copy.file-names`, `copy.parent-directories`, `copy.markdown-links`, `copy.shell-escaped-paths` |
| Create | `create.text-file`, `create.markdown-file`, `create.json-file`, `create.yaml-file` |
| Move | `move.cut-items`, `move.paste-cut-items` |
| Utility | `utility.md5`, `utility.sha256`, `archive.zip-items` |
| Open | `open.terminal`, `open.vscode`, `open.cursor`, `open.reveal-in-finder` |

## Installed on This Mac via Native Finder Sync

| Finder Action | Scope |
| --- | --- |
| `复制路径` / `复制当前文件夹路径` | Selected files/folders or empty Finder folder area |
| `复制 Shell 路径` | Selected files/folders or empty Finder folder area |
| `复制名称` | Selected files/folders |
| `复制父路径` | Selected files/folders |
| `复制 Git 相对路径` | Selected files/folders inside a Git repo |
| `复制项目` | Selected files/folders; can be pasted repeatedly |
| `剪切项目` | Selected files/folders; clears buffer after a successful paste |
| `粘贴到这里` / `粘贴到当前文件夹` | Selected folder, selected file's parent folder, or empty Finder folder area |
| `在终端打开` | Selected folders, selected files' parent directory, or current folder |
| `在 VS Code 打开` | Selected folders, selected files' parent directory, or current folder |
| `在 Cursor 打开` | Selected folders, selected files' parent directory, or current folder |
| `新建文本文件` | Selected folder or current folder |
| `新建 Markdown 文件` | Selected folder or current folder |
| `压缩所选项目` | Selected items sharing the same parent directory |

The old Automator Quick Actions fallback is intentionally uninstalled on this Mac so Finder's `服务` menu does not duplicate RightMenu entries.

## Next Daily-Use Actions

| Area | Candidate Actions |
| --- | --- |
| Favorites | Copy to favorite directory, move to favorite directory, reveal favorite directory |
| Developer | Copy repo-relative path, open Git remote URL, open in iTerm2 |
| Utilities | File size summary |
| Archive | Unzip here |
| Images | Convert to PNG/JPEG/WebP |
| Dangerous | Permanent delete, chmod writable, hide/show selected files |

Dangerous actions should require confirmation and execution logging before they appear in the Finder menu.
