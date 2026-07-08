# Import To Photos

Import To Photos 是一个纯本地 macOS 工具，用于把文件夹或单张图片导入系统 Photos Library。导入成功后，工具会在源文件上写入本地扩展属性标记，后续运行会自动跳过已导入文件，避免重复导入，同时保留原文件不变。

## 功能

- 使用 Swift、AppKit、Photos.framework 和 Finder Sync 构建，不联网，不上传图片。
- 支持双击 app、命令行和 Finder 右键同步。
- 导入成功后写入 `local.import-to-photos.uploaded`，用于跳过已导入图片。
- Finder 右键入口会把图片复制到默认上传目录，再导入 Photos，并同时标记原图和复制件。
- 提供 `Install.command`、`Doctor.command`、`Uninstall.command`，方便普通用户安装、诊断和卸载。
- 支持 `--dry-run` 预览待导入和已跳过文件。

支持常见图片和 RAW 格式，包括 `jpg`、`jpeg`、`png`、`heic`、`heif`、`gif`、`tiff`、`webp`、`avif`、`dng`、`cr2`、`cr3`、`nef`、`arw`、`raf`、`rw2`、`orf`、`raw` 等。

## 安装

普通用户请从 [GitHub Releases](https://github.com/dontttbefly-sketch/import-to-photos/releases) 下载 `ImportToPhotos-v...zip`。不要点 GitHub 页面里的 **Code > Download ZIP**，那是源码包，不是可直接安装的发行包。

解压 Release zip 后：

1. 右键点击 `Install.command`，选择“打开”。
2. 按 macOS 安全提示确认打开。
3. 第一次同步图片时，允许 Photos 权限。
4. 在 Finder 中右键未同步图片，选择 `同步进相册`；如果顶层菜单未出现，请在“快速操作”或“服务”中选择 `★ 同步进相册`。

当前发行包使用 adhoc 签名，未进行 Apple Developer ID 公证。首次打开时 macOS 会显示安全确认，这是免费分发方式的限制。

## 使用

### Finder 右键

安装后，Finder 右键未同步图片时会优先显示 `同步进相册`。

![Finder 右键菜单中的同步进相册入口](docs/screenshots/finder-sync-menu.png)

如果顶层菜单未显示，请使用 **快速操作/服务 > ★ 同步进相册**。两个入口都会调用同一套同步逻辑。

右键同步完成后会显示短提示；如果失败，请运行 `Doctor.command` 或查看日志：

```text
~/Library/Containers/local.import-to-photos.finder-sync/Data/Library/Application Support/ImportToPhotos/finder-sync.log
/tmp/local.import-to-photos/app.log
```

### 命令行

构建后可以直接传入文件夹或图片路径：

```sh
./ImportToPhotos/dist/ImportToPhotos.app/Contents/MacOS/ImportToPhotos /path/to/folder
./ImportToPhotos/dist/ImportToPhotos.app/Contents/MacOS/ImportToPhotos /path/to/image.png
```

预览导入结果，不写入 Photos，也不写入标记：

```sh
./ImportToPhotos/dist/ImportToPhotos.app/Contents/MacOS/ImportToPhotos --dry-run /path/to/folder
```

如果路径以 `-` 开头，用 `--` 结束选项解析：

```sh
./ImportToPhotos/dist/ImportToPhotos.app/Contents/MacOS/ImportToPhotos --dry-run -- /path/to/-image.png
```

### 默认导入目录

如需为双击 app 固定默认目录，在 `ImportToPhotos/Resources/` 下创建：

```text
DefaultImportFolder.txt
```

内容写入绝对路径，例如：

```text
/Users/you/Pictures/Incoming
```

仓库提供模板：`ImportToPhotos/Resources/DefaultImportFolder.example.txt`。真实 `DefaultImportFolder.txt` 通常包含个人路径，已被 `.gitignore` 忽略，不应提交。

## 已导入标记

工具只根据扩展属性判断是否已导入，不计算文件哈希，也不查询 Photos Library。

查看标记：

```sh
xattr -p local.import-to-photos.uploaded /path/to/image.png
```

删除标记，让文件下次可以重新导入：

```sh
xattr -d local.import-to-photos.uploaded /path/to/image.png
```

## 构建

要求：

- macOS 12 或更新版本
- Apple Swift 编译器

构建当前架构 app：

```sh
./ImportToPhotos/Scripts/build.sh
```

构建 universal app：

```sh
./ImportToPhotos/Scripts/build.sh --universal
```

构建结果：

```text
ImportToPhotos/dist/ImportToPhotos.app
```

生成 GitHub Release zip：

```sh
./ImportToPhotos/Scripts/package_release.sh --universal
```

Release zip 会包含预编译 app、Finder 服务 workflow、LaunchAgent、安装脚本、诊断脚本、卸载脚本和用户安装说明。

## 测试

```sh
./ImportToPhotos/Scripts/test_marker_behavior.sh
./ImportToPhotos/Scripts/test_finder_sync_behavior.sh
./ImportToPhotos/Scripts/test_right_click_experience.sh
./ImportToPhotos/Scripts/test_release_package.sh
```

建议发布前再验证 universal 构建和签名：

```sh
./ImportToPhotos/Scripts/build.sh --universal
lipo -archs ImportToPhotos/dist/ImportToPhotos.app/Contents/MacOS/ImportToPhotos
codesign --verify --deep --strict ImportToPhotos/dist/ImportToPhotos.app
```

## 隐私与安全

- 程序不联网，不上传图片。
- 程序不会删除、移动或重命名原图。
- 右键同步会额外复制一份图片到默认上传目录。
- Photos 权限由 macOS 管理；如果权限被拒绝，请在系统设置中允许该 app 添加照片。
- 不要提交真实照片、个人默认路径、`.env`、`.state/`、`rules.json`、日志文件或构建产物。
- Release zip 只上传到 GitHub Releases，不提交进仓库。

更多公开仓库安全规则见 [SECURITY.md](SECURITY.md)。

## 常见问题

### 为什么图片还在原文件夹？

这是设计行为。工具只把图片导入 Photos Library，不清理源文件。

### 为什么第二次点击没有再次导入？

文件已经带有 `local.import-to-photos.uploaded` 标记。删除该扩展属性后可以重新导入。

### Finder 顶层右键菜单不显示怎么办？

先使用“快速操作”或“服务”里的 `★ 同步进相册`。如果仍不可用，运行 `Doctor.command`，并确认系统设置中已启用 `ImportToPhotos 扩展`。

### 后台服务会自动扫描照片吗？

不会。LaunchAgent 只保持后台处理器可用，不会自动扫描文件夹，也不会主动导入照片。

## 项目结构

```text
.
├── ImportThisFolderToPhotos.command
├── ImportToPhotos/
│   ├── Sources/
│   │   ├── App/
│   │   ├── FinderSyncExtension/
│   │   └── Shared/
│   ├── Resources/
│   ├── Scripts/
│   ├── Tools/
│   └── README.md
├── SECURITY.md
└── README.md
```

核心逻辑位于 `ImportToPhotos/Sources/`：主程序在 `App/`，Finder 右键扩展在 `FinderSyncExtension/`，图片类型、扩展属性标记和任务队列等共享逻辑在 `Shared/`。
