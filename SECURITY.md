# Security Policy

ImportToPhotos is a local macOS utility. It does not require API keys, cloud credentials, or network services for normal use.

## Public Repository Rules

Do not commit:

- real photos or screenshots from a private library
- `.env`, `.env.*`, `.state/`, `rules.json`, or log files
- `ImportToPhotos/Resources/DefaultImportFolder.txt`, because it usually contains a personal local path
- build output such as `ImportToPhotos/.build/` and `ImportToPhotos/dist/`
- GitHub tokens, webhook URLs, app secrets, or other credentials

Release zip files should be attached to GitHub Releases, not committed to the repository.

## Reporting Issues

If you find a security or privacy problem, open a GitHub issue with a minimal reproduction and avoid attaching private photos, local paths, access tokens, or logs that contain personal information.
