# Local deployment configuration

`/etc/nixos/local/deployment.json` contains optional machine- or site-specific
values that must not be embedded in the public hardware profiles. The complete
`/etc/nixos/local/` directory is ignored by Git. A clean checkout remains
evaluable without deployment-specific values during the installer bootstrap;
after activation an empty deployment is represented by `{}`. Every documented
key is optional unless a subsection is present and says otherwise.

This document is the canonical reference for the deployment keys consumed by
the NixOS and matching Home Manager repositories.

## General rules

- The file must contain one JSON object.
- Keep hardware identity in `local/profile.nix` and user/machine identity in
  `local/identity.json`; do not duplicate those values here.
- Public SSH keys and internal service addresses are valid deployment data, but
  they still reveal infrastructure details. Keep the file out of the public
  repository.
- Passwords, API tokens, private SSH keys and other secrets should live in the
  dedicated credential stores referenced by the configuration, not directly in
  `deployment.json`.
- Unknown keys are currently ignored. Document new consumed keys here when they
  are added to the configuration.

## Complete example

The following example intentionally uses documentation-only addresses and keys.
Only keep the sections required by the target machine.

```json
{
  "userAuthorizedKeys": [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleUserKey workstation"
  ],
  "networking": {
    "localSubnets": [
      "192.0.2.0/24",
      "2001:db8:1234::/64"
    ]
  },
  "plasma": {
    "dolphinBookmark": {
      "title": "fileserver",
      "url": "smb://fileserver.example"
    }
  },
  "plasmaDisplayLayout": {
    "delaySeconds": 30,
    "outputs": [
      {
        "id": "DP-1",
        "scale": 1,
        "position": "0,0",
        "priority": 1,
        "brightness": 1.0
      }
    ]
  },
  "nixBuilder": {
    "authorizedKeys": [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleBuilderClient client"
    ]
  },
  "remoteBuilder": {
    "hostName": "builder.example",
    "protocol": "ssh-ng",
    "system": "x86_64-linux",
    "sshUser": "nix-ssh",
    "sshKey": "/root/.ssh/nixbuilder_ed25519",
    "maxJobs": 4,
    "speedFactor": 8,
    "supportedFeatures": [
      "nixos-test",
      "benchmark",
      "big-parallel",
      "kvm"
    ],
    "publicHostKey": "BASE64_OF_COMPLETE_SSH_HOST_PUBLIC_KEY_FILE"
  },
  "hermes": {
    "habUrl": "http://homeassistant.example:8123",
    "ollamaBaseUrl": "http://ollama.example:11434/v1"
  },
  "topgrade": {
    "updateManagedDependencies": true
  }
}
```

## `userAuthorizedKeys`

Type: array of strings.

Adds the listed OpenSSH public keys to the normal local user's
`authorized_keys`. The default is an empty list.

```json
{
  "userAuthorizedKeys": [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleUserKey workstation"
  ]
}
```

Do not put private keys in this list.

## `networking.localSubnets`

Type: array of IPv4 and/or IPv6 CIDR strings.

Declares physical LAN prefixes that should take precedence over overlapping
overlay/subnet routes such as Tailscale advertised routes while the workstation
is actually attached to that LAN.

```json
{
  "networking": {
    "localSubnets": [
      "192.0.2.0/24",
      "2001:db8:1234::/64"
    ]
  }
}
```

For each prefix NixOS installs a policy rule with priority `2500` that consults
the `main` routing table while suppressing its default route
(`suppress_prefixlength 0`). This has two important effects:

1. when the LAN is directly connected, its specific connected route wins over
   an overlapping Tailscale subnet route;
2. when the workstation is away from that LAN, the ordinary default route is
   ignored by this rule and lookup falls through to Tailscale's policy rules.

This avoids the asymmetric-routing failure that otherwise prevents local
services such as KDE Connect from working when a Tailscale subnet route overlaps
with the current physical LAN.

The list defaults to empty, in which case no additional policy rules are
installed.

## `plasma.dolphinBookmark`

Used by Plasma profiles to add one deployment-specific network bookmark to
Dolphin.

Fields:

- `url` — string, required when the subsection is present.
- `title` — string, optional; defaults to `Network share`.

```json
{
  "plasma": {
    "dolphinBookmark": {
      "title": "fileserver",
      "url": "smb://fileserver.example"
    }
  }
}
```

## `plasmaDisplayLayout`

Used by the HP Z2 Tower G9 profile for the delayed Plasma display-layout
application. Display connector identities are deployment-specific and therefore
are intentionally not part of the public hardware profile.

The default `30`-second delay is an intentional part of the HP Plasma startup
sequence, not merely a cosmetic wait. Plasma is allowed to finish its initial
screen and panel discovery before the final two-monitor KScreen layout is
applied. Applying that layout too early previously caused Plasma to create or
migrate unnecessary additional application bars/panels while the output
topology was still changing.

The matching Home Manager HP profile performs its one-time second-panel
bootstrap after `35` seconds. That five-second margin deliberately places panel
creation after the NixOS display-layout change. Treat the `30 s` NixOS delay and
`35 s` Home Manager bootstrap delay as one cross-repository ordering invariant.
Do not change `delaySeconds` independently without reviewing and testing the
Home Manager panel bootstrap at the same time.

Fields:

- `delaySeconds` — number, optional; defaults to `30`. The tested/default value
  participates in the panel-ordering invariant described above.
- `outputs` — non-empty array, required when `plasmaDisplayLayout` is present.

Each output object supports:

- `id` — non-empty string, required; the KScreen output identifier.
- `scale` — number, optional; defaults to `1`.
- `position` — string, optional; defaults to `0,0`.
- `priority` — number, optional; defaults to `1`.
- `brightness` — number, optional.

```json
{
  "plasmaDisplayLayout": {
    "delaySeconds": 30,
    "outputs": [
      {
        "id": "DP-1",
        "scale": 1,
        "position": "0,0",
        "priority": 1
      },
      {
        "id": "HDMI-A-1",
        "scale": 1,
        "position": "2560,0",
        "priority": 2,
        "brightness": 0.9
      }
    ]
  }
}
```

## `nixBuilder.authorizedKeys`

Used by the HP Z2 Tower G9 profile when that workstation should expose the
restricted `nix-ssh` remote-builder service.

Type: array of OpenSSH public-key strings.

The service is enabled only when the list is non-empty.

```json
{
  "nixBuilder": {
    "authorizedKeys": [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleBuilderClient client"
    ]
  }
}
```

## `remoteBuilder`

Used by profiles that delegate builds to a deployment-specific Nix builder.
When this subsection is absent, builds remain local.

Required fields when present:

- `hostName` — non-empty string.
- `publicHostKey` — non-empty string containing the base64 encoding expected by
  Nix for the complete SSH host public-key file, including its trailing newline.

Optional fields and defaults:

- `protocol` — `ssh-ng`.
- `system` — `x86_64-linux`.
- `sshUser` — `nix-ssh`.
- `sshKey` — `/root/.ssh/nixbuilder_ed25519`.
- `maxJobs` — `4`.
- `speedFactor` — `8`.
- `supportedFeatures` — `nixos-test`, `benchmark`, `big-parallel`, `kvm`.

```json
{
  "remoteBuilder": {
    "hostName": "builder.example",
    "publicHostKey": "BASE64_OF_COMPLETE_SSH_HOST_PUBLIC_KEY_FILE"
  }
}
```

The private client key referenced by `sshKey` is not stored in
`deployment.json`.

## `hermes`

Consumed by the matching Home Manager profile that enables Hermes integration.
The values are optional non-secret service endpoints.

Fields:

- `habUrl` — string; Home Assistant/HAB base URL.
- `ollamaBaseUrl` — string; OpenAI-compatible Ollama base URL.

```json
{
  "hermes": {
    "habUrl": "http://homeassistant.example:8123",
    "ollamaBaseUrl": "http://ollama.example:11434/v1"
  }
}
```

Authentication tokens remain in the user's Hermes environment/credential file,
not in this JSON file.

## `topgrade.updateManagedDependencies`

Type: boolean. Default: `true`.

Controls whether the guarded Topgrade pre-command advances the machine-local
managed dependency state (`lon`/FileBot and Home Manager flake inputs). It does
not disable the NixOS candidate safety build.

```json
{
  "topgrade": {
    "updateManagedDependencies": false
  }
}
```

## Backup and recovery

`local/deployment.json` is one of exactly three canonical NixOS recovery files,
alongside `local/profile.nix` and `local/identity.json`. The helper
`scripts/backup-config.sh` archives `/etc/nixos/local/` as one unit.

Release/bootstrap lock files do not belong in that recovery set: they are
refreshed by repository maintenance and subsequently by Topgrade on installed
systems. Downloaded fonts, wallpaper and other reproducible generated state are
also intentionally excluded.

The long-term documentation source remains this repository. A GitHub Wiki may
mirror selected files later, but the Markdown under `docs/` remains canonical.
