# Import To Photos Component Notes

This folder contains the macOS app source. See the root [README.md](../README.md) for full build, usage, duplicate-marker, privacy, and troubleshooting documentation.

Quick build:

```sh
./Scripts/build.sh
```

Build a universal app for release:

```sh
./Scripts/build.sh --universal
```

Create a GitHub Release zip:

```sh
./Scripts/package_release.sh --universal
```

Install the Finder right-click menu:

```sh
./Scripts/install_finder_extension.sh
```

Quick dry-run:

```sh
./dist/ImportToPhotos.app/Contents/MacOS/ImportToPhotos --dry-run /path/to/folder
```

Regression tests:

```sh
./Scripts/test_marker_behavior.sh
./Scripts/test_finder_sync_behavior.sh
./Scripts/test_right_click_experience.sh
./Scripts/test_release_package.sh
```
