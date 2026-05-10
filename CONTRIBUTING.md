# Contributing to LayerLens

Thanks for your interest. PRs and issue reports are welcome.

## Filing issues

Use the [issue templates](.github/ISSUE_TEMPLATE) — they prompt for the
things I'll need anyway (macOS version, keyboard, app version, logs).
For security issues, see [SECURITY.md](./SECURITY.md) — please report
those privately, not as public issues.

## Building from source

```sh
swift build               # debug build
swift test                # core library tests
swift run LayerLens       # launch from the terminal
swift run LayerLensProbe  # CLI to enumerate connected QMK keyboards
```

Requirements:
- macOS 14+ on Apple Silicon
- Xcode 26 or newer (for the bundled Swift toolchain)

## Style

Code is formatted with `swift-format` using the rules in
[`.swift-format`](./.swift-format). Lint locally before pushing:

```sh
swift format lint --strict --recursive Sources Tests
```

CI runs the same check; PRs that don't pass won't be reviewed until
they do.

## Commit messages

Releases are auto-generated from git history by
[git-cliff](./cliff.toml). Please follow the
[Conventional Commits](https://www.conventionalcommits.org/) prefix
convention so commits land in the right release-note section:

| Prefix | Section |
| --- | --- |
| `feat:` | Features |
| `fix:` | Bug Fixes |
| `perf:` | Performance |
| `refactor:` | Refactor |
| `docs:` | Documentation |
| `test:` | Tests |
| `build:` / `ci:` / `chore:` | Build / CI / Chore |

Non-conforming commits still merge — they just appear under "Other"
in the changelog.

## Pull requests

- Branch from `main`, open the PR against `main`.
- Keep PRs focused; one logical change per PR is much easier to review.
- Include a Test plan in the description (the
  [PR template](.github/PULL_REQUEST_TEMPLATE.md) prompts for it).
- Don't bump the version or modify `appcast.xml` in a PR — those are
  released via tag pushes from `main`.

## Licensing

LayerLens is GPL-3.0-only. By submitting a contribution, you agree
that your code will be released under the same license.
