# Import To Photos Component Notes

This folder contains the macOS app source. See the root [README.md](../README.md) for full build, usage, duplicate-marker, privacy, and troubleshooting documentation.

Quick build:

```sh
./build.sh
```

Install the Finder right-click menu:

```sh
./install_finder_extension.sh
```

Quick dry-run:

```sh
./ImportToPhotos.app/Contents/MacOS/ImportToPhotos --dry-run /path/to/folder
```

Regression tests:

```sh
./test_marker_behavior.sh
./test_finder_sync_behavior.sh
```
