# Versioning

Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The version in `pubspec.yaml` is the package version. `CHANGELOG.md` records every published version.

While the major version is 0, a minor bump may change the public API. A patch bump is a fix that keeps the API. From 1.0.0 onward, breaking API changes require a major bump.

Publish from a commit on `main` whose `pubspec.yaml` version matches the changelog heading. Do not republish a version number. `publish_to` is unset so the package can go to pub.dev. The example app stays `publish_to: none`.
