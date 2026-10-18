# Contributing

This repository accepts work that a maintainer has already agreed to. An unsolicited pull request, including drive-by refactors and new features, will be closed.

## Issues

Open an issue from the templates. Blank issues are disabled.

A bug report needs the package version, the device or desktop target, and what the scan decided (`locked` or the reject reason). Do not paste a full MRZ, a PAN, a TCKN, or a photo of a real document.

A feature request needs the user-facing behavior and why the current API cannot express it. Maintainer agreement is a label: `accepted`.

## Pull requests

A pull request must contain a line of the form `Fixes #123` (or `Closes` / `Resolves`) pointing at an **open** issue that carries the `accepted` label. CI checks that link and that label. A PR that fails the check is not reviewed.

The change should match the issue. Include a changelog entry under the next version when behavior changes. Tests cover validation and pipeline changes. `flutter analyze` and `flutter test` pass in the package and in `example/`.

Do not add a network call or image write on the scan path. Do not log a PAN, an MRZ line, or a TCKN.

## Maintainers

Only a maintainer applies `accepted`. Commenting on an issue is not acceptance. Opening a PR does not create acceptance after the fact.
