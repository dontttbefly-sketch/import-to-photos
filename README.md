# Import To Photos

Import To Photos 是一个纯本地 macOS 工具，用于把文件夹或单张图片导入系统 Photos Library。导入成功后，工具会在源文件上写入本地扩展属性标记，后续运行会自动跳过已导入文件，避免重复导入，同时保留原文件不变。

## 功能

- 使用 Swift、AppKit、Photos.framework 和 Finder Sync 构建，不联网，不上传图片。
- 支持双击 app、命令行和 Finder 右键同步。
- 导入成功后写入 `local.import-to-photos.uploaded`，用于跳过已导入图片。
- Finder 右键入口会直接导入所选图片，成功后只标记源文件，不额外复制或留存副本。
- 如需保留副本，可以手动开启备份模式并指定备份文件夹。
- Release DMG 提供 pkg 安装器和卸载脚本，安装后通过 Finder 右键使用。
- 支持 `--dry-run` 预览待导入和已跳过文件。

支持常见图片和 RAW 格式，包括 `jpg`、`jpeg`、`png`、`heic`、`heif`、`gif`、`tiff`、`webp`、`avif`、`dng`、`cr2`、`cr3`、`nef`、`arw`、`raf`、`rw2`、`orf`、`raw` 等。

## 安装

普通用户请从 [GitHub Releases](https://github.com/dontttbefly-sketch/import-to-photos/releases) 下载 `ImportToPhotos-v...dmg`。不要点 GitHub 页面里的 **Code > Download ZIP**，那是源码包，不是可直接安装的发行包。

打开 Release dmg 后：

1. 双击挂载的磁盘里的 `Install ImportToPhotos.pkg`。
2. 按 macOS Installer 提示完成安装。
3. 安装结束时会弹出说明框，选择“确认启动”即可立即启用后台服务和 Finder 右键同步。
4. 安装完成后不需要手动打开 app；它没有主窗口。以后每次登录后会自动启动后台服务。
5. 第一次同步图片时，允许 Photos 权限。
6. 在 Finder 中右键未同步图片，选择 `同步进相册`；如果顶层菜单未出现，请在“快速操作”或“服务”中选择 `★ 同步进相册`。

当前发行包使用 adhoc 签名，未进行 Apple Developer ID 公证。首次打开时 macOS 会显示安全确认，这是免费分发方式的限制。

## 使用

### Finder 右键

安装后，Finder 右键未同步图片时会优先显示 `同步进相册`。

![Finder 右键菜单中的同步进相册入口](docs/screenshots/finder-sync-menu.png)

如果顶层菜单未显示，请使用 **快速操作/服务 > ★ 同步进相册**。两个入口都会调用同一套同步逻辑。

右键同步完成后会显示短提示；如果失败，请重新运行安装器修复右键服务，或查看日志：

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

### 默认导入目录与备份设置

Finder 右键默认直接把所选图片导入 Photos，不复制、不留存副本。双击 app 且不传路径时，会使用默认导入目录；未配置时是当前用户的 `~/Pictures/ImportToPhotos`。

如需为双击 app 固定默认目录，在 `ImportToPhotos/Resources/` 下创建：

```text
DefaultImportFolder.txt
```

内容写入绝对路径，例如：

```text
/Users/you/Pictures/Incoming
```

仓库提供模板：`ImportToPhotos/Resources/DefaultImportFolder.example.txt`。真实 `DefaultImportFolder.txt` 通常包含个人路径，已被 `.gitignore` 忽略，不应提交。

如果希望 Finder 右键导入前额外保留一份副本，创建用户设置文件：

```sh
mkdir -p "$HOME/Library/Application Support/ImportToPhotos"
cat > "$HOME/Library/Application Support/ImportToPhotos/settings.env" <<'EOF'
IMPORT_TO_PHOTOS_KEEP_COPY=1
IMPORT_TO_PHOTOS_DEFAULT_FOLDER=/Users/you/Pictures/ImportToPhotosBackup
EOF
```

开启后，右键同步会先把图片复制到 `IMPORT_TO_PHOTOS_DEFAULT_FOLDER` 指定的文件夹，再导入 Photos，并同时标记源文件和副本。若不写 `IMPORT_TO_PHOTOS_DEFAULT_FOLDER`，副本默认放在 `~/Pictures/ImportToPhotos`。删除 `IMPORT_TO_PHOTOS_KEEP_COPY` 或改为 `0`，即可恢复默认的直接导入模式。同名环境变量可用于临时覆盖 `settings.env`。

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

生成 GitHub Release dmg：

```sh
./ImportToPhotos/Scripts/package_release.sh --universal
```

Release dmg 会包含 `Install ImportToPhotos.pkg`、`Uninstall ImportToPhotos.command` 和用户安装说明。pkg 会安装预编译 app、Finder 服务 workflow 和 LaunchAgent。

开发调试时，也可以直接安装 Finder 右键菜单：

```sh
./ImportToPhotos/Scripts/install_finder_extension.sh
```

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
- Finder 右键同步不会额外复制或留存图片；导入成功后只在源文件写入本地标记。
- 只有手动开启 `IMPORT_TO_PHOTOS_KEEP_COPY=1` 时，右键同步才会创建副本。
- Photos 权限由 macOS 管理；如果权限被拒绝，请在系统设置中允许该 app 添加照片。
- 不要提交真实照片、个人默认路径、`.env`、`.state/`、`rules.json`、日志文件或构建产物。
- Release dmg 只上传到 GitHub Releases，不提交进仓库。

更多公开仓库安全规则见 [SECURITY.md](SECURITY.md)。

## 常见问题

### 为什么图片还在原文件夹？

这是设计行为。工具只把图片导入 Photos Library，不清理源文件。

### 为什么第二次点击没有再次导入？

文件已经带有 `local.import-to-photos.uploaded` 标记。删除该扩展属性后可以重新导入。

### Finder 顶层右键菜单不显示怎么办？

先使用“快速操作”或“服务”里的 `★ 同步进相册`。如果仍不可用，重新运行安装器修复右键服务，并确认系统设置中已启用 `ImportToPhotos 扩展`。

### 如何卸载？

重新打开 Release dmg，双击 `Uninstall ImportToPhotos.command`。它会移除 `/Applications/ImportToPhotos.app`、Finder 右键服务和登录后台服务。

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
