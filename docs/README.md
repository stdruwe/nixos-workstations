# Documentation index

The Markdown files in this directory are the canonical long-form documentation for the public NixOS workstation repository. Keep operational rationale here rather than relying on chat history or undocumented knowledge.

## Start here

- [`../CURRENT-STATE.md`](../CURRENT-STATE.md) — durable description of the currently supported repository state.
- [`operational-invariants.md`](operational-invariants.md) — non-obvious hardware workarounds, fixed delays, service ordering, cross-repository dependencies, and the tests/removal criteria required before changing them.
- [`deployment-json.md`](deployment-json.md) — canonical schema and behavior for `/etc/nixos/local/deployment.json`.

## Installation, release and recovery

- [`release-process.md`](release-process.md) — canonical paired-release checklist, including the required Home Manager first / NixOS second publication order and post-release artifact verification.
- [`install-package.md`](install-package.md) — version-matched public installation package and release workflow.
- [`home-manager-install-bundle.md`](home-manager-install-bundle.md) — Home Manager bundle integration during NixOS installation.
- [`secure-boot-tpm2.md`](secure-boot-tpm2.md) — Secure Boot and TPM2 post-install procedure.
- [`profile-identity-migration.md`](profile-identity-migration.md) — profile/identity/local-state migration model.
- [`apple-macbook-air-8-1-install.md`](apple-macbook-air-8-1-install.md) — MacBookAir8,1 T2 dual-boot installation procedure.
- [`apple-macbook-air-8-1-postinstall.md`](apple-macbook-air-8-1-postinstall.md) — MacBookAir8,1 post-install verification and maintenance.

## Provenance

- [`third-party-material.md`](third-party-material.md) — provenance, redistribution boundaries, and handling of local third-party/vendor material.

## Documentation rule

Code should explain the local mechanism. `CURRENT-STATE.md` should describe the durable supported state. `operational-invariants.md` should preserve the reason behind unusual values and workarounds so later audits do not optimize away behavior whose purpose is not obvious from the expression itself.

If an existing unusual setting has no verified rationale, preserve the behavior while investigating and record that the rationale is unresolved instead of inventing an explanation.
