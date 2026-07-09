# ImportToPhotos GitHub Release 安装说明

这个磁盘映像来自 GitHub Release。当前版本没有 Apple Developer ID 公证，只适合你信任来源的小范围安装。第一次打开安装器时 macOS 可能会提示无法验证开发者，这是正常现象。

## 安装

1. 从 GitHub Release 下载 `ImportToPhotos-v...dmg`，不要点 `Code -> Download ZIP` 下载源码包。
2. 双击打开 dmg。
3. 双击 `Install ImportToPhotos.pkg`。
4. 按 macOS Installer 提示完成安装。
5. 安装结束时会弹出说明框，选择“确认启动”即可立即启用后台服务和 Finder 右键同步。
6. 安装完成后不需要手动打开 app；它没有主窗口。以后每次登录后会自动启动后台服务。
7. 第一次同步图片时，请允许 Photos 权限。
8. 在 Finder 或桌面右键未同步图片，优先找 `★ 同步进相册`。如果顶层菜单没出现，请到“快速操作”或“服务”里找 `★ 同步进相册`。

右键同步会直接导入所选图片；成功后只标记源文件，不额外复制或留存副本。
如需保留副本，请参考 GitHub README 里的备份设置。

## 出问题时

重新运行安装器通常可以修复 Finder 右键服务和后台服务注册问题。仍不可用时，请到 GitHub issue 反馈安装日志和 macOS 版本。

常见情况：

- Finder 或桌面顶层右键菜单不出现：先用“快速操作/服务”里的 `★ 同步进相册`。
- 第一次同步要求 Photos 权限：请选择允许。
- 提示架构不匹配：这个包和你的 Mac CPU 不匹配，需要换另一个安装包。

## 卸载

重新打开 dmg，双击 `Uninstall ImportToPhotos.command`。它会移除 app、Finder 右键服务和登录后台服务。
