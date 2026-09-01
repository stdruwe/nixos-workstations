# Paired release procedure

This repository and `stdruwe/home-manager-workstations` are released as one version-matched workstation configuration. Both repositories use the same semantic-version tag, beginning with `v0.1.0`.

The order below is part of the release contract. The NixOS release workflow starts as soon as a NixOS GitHub release is published and immediately checks out the matching Home Manager tag. Therefore the matching Home Manager tag must already exist before the NixOS release is published.

## Pre-release validation

For a planned tag such as `v0.1.0`:

1. Finish all intended NixOS and Home Manager changes and merge them to `main`.
2. Run the Home Manager `Refresh Home Manager release lock` workflow manually and let it finish successfully.
3. If that workflow commits a changed `flake.lock.bootstrap`, manually dispatch the normal Home Manager CI for the resulting `main` commit and let it finish successfully. A push made by the release-lock workflow through `GITHUB_TOKEN` does not trigger another push workflow automatically.
4. Run the NixOS `Refresh NixOS release lock` workflow manually and let it finish successfully. This refresh covers the tracked `lon.nix`/`lon.lock` state and the tracked `pkgs/filebot-source.nix` FileBot bootstrap source before validating all three hardware profiles.
5. If that workflow commits changed `lon.nix`, `lon.lock` or `pkgs/filebot-source.nix`, manually dispatch the normal NixOS CI for the resulting `main` commit and let it finish successfully. A push made by the release-lock workflow through `GITHUB_TOKEN` does not trigger another push workflow automatically.
6. Confirm that both repositories' final `main` commits are the exact commits intended for the release and that both normal CI suites are green.
7. Do not create release tags while either release-lock workflow or its follow-up CI is still changing or validating `main`.

The refresh workflows maintain release/bootstrap state only. Installed machines continue to own their independent ignored live dependency state.

## Release notes

Every published release should start with a short curated summary that explains the release in user-facing terms. Do not rely on GitHub's automatically generated pull-request list as the complete release description.

The summary should cover the most relevant functional changes, important fixes or compatibility notes, and any installation or upgrade implications. Detailed generated change lists may follow the summary.

For paired releases, keep the Home Manager and NixOS summaries consistent with each other while describing repository-specific changes where useful.

## Required release order

### 1. Publish Home Manager first

Create and publish the Home Manager release with the planned tag, for example:

```text
v0.1.0
```

Include the curated release summary before any generated change list.

Verify that the tag resolves to the intended final Home Manager `main` commit. No NixOS installation archive is generated from this release; its primary role in the paired release is to establish the exact Home Manager tag that the NixOS packaging workflow will consume.

### 2. Publish NixOS second

Only after the matching Home Manager tag exists, create and publish the NixOS release with the exact same tag.

Include the curated release summary before any generated change list.

Publishing the NixOS release triggers `.github/workflows/release-install-package.yml`. That workflow:

1. checks out the NixOS release tag;
2. checks out `stdruwe/home-manager-workstations` at the identical tag;
3. builds the version-bound combined installation package;
4. verifies its SHA-256 checksum;
5. uploads the package and checksum to the NixOS GitHub release.

Publishing NixOS first is invalid release ordering: the packaging job can fail because the matching Home Manager tag does not yet exist.

## Post-release verification

Do not consider the paired release complete until all of the following are true:

- the Home Manager release/tag exists at the intended commit;
- the NixOS release/tag exists at the intended commit;
- both release descriptions contain the intended curated summary;
- the NixOS `Release install package` workflow completed successfully;
- the NixOS release contains both expected assets:

```text
nixos-install-vX.Y.Z.tar.zst
nixos-install-vX.Y.Z.tar.zst.sha256
```

- the published checksum verifies the archive;
- `INSTALL-SNAPSHOT.txt` inside the archive records tag `vX.Y.Z` and the intended exact NixOS and Home Manager commit SHAs.

For the first public release, substitute `v0.1.0` for `vX.Y.Z`.

## Published tags are immutable

Do not move or rewrite a published release tag merely to correct a release mistake. If a published tag points at the wrong state, fix the repositories and publish a new semantic-version release instead. This keeps installation snapshots reproducible and prevents an existing version from resolving to different source code over time.

## Related documentation

- [`install-package.md`](install-package.md) describes the combined package format and installation workflow.
- [`home-manager-install-bundle.md`](home-manager-install-bundle.md) describes Home Manager integration during installation.
- [`../CURRENT-STATE.md`](../CURRENT-STATE.md) records the durable repository/release model.
