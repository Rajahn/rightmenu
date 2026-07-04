# Smart Clipboard History

RightMenu includes a focused menu-bar clipboard history in `RightMenuNative.app`.

## Scope

The feature is intentionally smaller than a full clipboard manager. It captures common daily clipboard content, classifies it automatically, and makes it easy to find and reuse.

Supported categories:

- `文本`
- `链接`
- `文件/路径`
- `代码`
- `图片`
- `固定`

## Behavior

- The host app polls `NSPasteboard.general.changeCount`.
- New clipboard content is persisted to:

```text
~/Library/Application Support/RightMenu/clipboard-history.json
```

- Duplicate content is moved to the top instead of creating another row.
- History keeps up to 100 unpinned records; pinned records are preserved.
- Clicking `复制` writes the record back to the system clipboard.
- `固定` / `取消固定` keeps important items at the top.
- `删除` removes one record.
- Link records expose `打开`.

## Classification

Classification is local and deterministic:

- File URLs from the pasteboard become `文件/路径`.
- Existing path-like text, `file://` URLs, and shell-escaped paths become `文件/路径`.
- Single HTTP/HTTPS URLs become `链接`.
- Multi-line snippets with common code markers become `代码`.
- Pasteboard images become `图片`.
- Everything else becomes `文本`.

## Product Boundary

This is the first product-facing feature that broadens RightMenu beyond Finder's right-click menu. It still fits the same target user: people moving from Windows to macOS who expect copied content to remain recoverable and easy to reuse.

Out of scope for now:

- Cloud sync
- Full rich-text preservation
- AI summarization
- Cross-device clipboard
- Complex snippet libraries
