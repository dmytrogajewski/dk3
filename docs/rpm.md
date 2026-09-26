# Private RPM with local game assets

The asset-inclusive x86-64 RPM contains the independent native client/server,
both renderers, game modules, converted game packages, the selected HD/appearance
artwork, dkguard and the online guest CLI. It is a development snapshot. The assets
retain their original ownership; this local bundle is not a public GPL-only release.

Build from an existing verified online installation and a public CA certificate:

```sh
python3 packaging/rpm/build.py --runtime zig-out/online/play/current \
  --coordinator https://161.104.54.191 \
  --ca ~/.local/state/dk3-online-203/test-root.crt
```

The build requires `rpmbuild`, Python 3 and the existing `zig-out/bin/dkguard` and
`dk3-online` products. Output is under `zig-out/rpm/RPMS/x86_64/`, with a SHA-256
sidecar. It includes only allowlisted, manifest-verified runtime files and the
public certificate. Profiles, saves, guest identities, server credentials and
private CA keys are excluded. The package does not install or start hosting services.

On another compatible Fedora x86-64 machine, copy the RPM and install it:

```sh
sudo dnf install ./dk3-0.1.0-208.fc43.x86_64.rpm
/usr/bin/dk3
```

The desktop application is named **dk3**. A new profile defaults to the provisioned
HTTPS room service and its explicitly trusted CA. Choose **Multiplayer → Internet
rooms** or **Create Internet room**. Each machine creates its own persistent guest
identity. The host currently supports one simultaneous room; existing rooms can be
joined by several players. Empty rooms expire after five minutes without humans.

Profiles and saves use `$XDG_DATA_HOME/dk3` (default `~/.local/share/dk3`), with state
under `$XDG_STATE_HOME/dk3`. Existing development checkout profiles are not changed.
Later online-setting changes are preserved. On the development machine, the older
`~/.local/bin/dk3` command takes precedence; use `/usr/bin/dk3` for the RPM build.

The package records native shared-library requirements. It was built for Fedora 43;
installation on other distributions or older libc versions is not yet verified.
The RPM and its embedded game assets must stay out of public source releases.
