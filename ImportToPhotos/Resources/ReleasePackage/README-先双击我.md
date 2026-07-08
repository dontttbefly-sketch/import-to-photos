# ImportToPhotos GitHub Release 安装说明

这个包来自 GitHub Release。当前版本没有 Apple Developer ID 公证，只适合你信任来源的小范围安装。第一次打开时 macOS 可能会提示无法验证开发者，这是正常现象。

## 安装

1. 从 GitHub Release 下载 `ImportToPhotos-v...zip`，不要点 `Code -> Download ZIP` 下载源码包。
2. 解压 zip。
3. 右键点击 `Install.command`，选择“打开”。
4. 如果 macOS 再次提示安全风险，确认“打开”。
5. 安装完成后，第一次同步图片时，请允许 Photos 权限。
6. 在 Finder 里右键未同步图片，优先找 `★ 同步进相册`。如果顶层菜单没出现，请到“快速操作”或“服务”里找 `★ 同步进相册`。

右键同步会直接导入所选图片；成功后只标记源文件，不额外复制或留存副本。

## 出问题时

双击 `Doctor.command`，把窗口里的诊断结果发给开发者。

常见情况：

- Finder 顶层右键菜单不出现：先用“快速操作/服务”里的 `★ 同步进相册`。
- 第一次同步要求 Photos 权限：请选择允许。
- 提示架构不匹配：这个包和你的 Mac CPU 不匹配，需要换另一个安装包。

## 卸载

双击 `Uninstall.command`。
