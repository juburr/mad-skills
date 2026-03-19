---
name: podman-rpms
description: Guides building RPMs that deploy containers with rootless Podman and Quadlet
  on RHEL 8/9/10. Use when packaging containerized applications as RPMs, writing Quadlet
  unit files, configuring rootless Podman service users, handling air-gapped image
  delivery, or managing Podman 4.x/5.x compatibility.
---

# Podman RPMs

Guide for building RPMs that deploy containerized applications using **rootless Podman** and **Quadlet** systemd integration on **RHEL 8, 9, and 10**.

## Architecture

Each application gets:
- A **dedicated service user** with its own rootless Podman storage, user namespace, and systemd user instance
- **Quadlet files** that declare containers, volumes, networks, and optionally images as systemd-managed units
- **Air-gapped image delivery** via OCI/docker-archive tarballs (no registry required)
- A single RPM that detects the installed Podman version and installs the correct Quadlet variant

### Rootless Security Model

Rootless Podman runs containers without root privileges using user namespaces. Each service user is an isolation boundary:
- Own subordinate UID/GID ranges (`/etc/subuid`, `/etc/subgid`)
- Own container storage (images, layers, containers)
- Own systemd user manager instance (when lingering is enabled)
- Automatic per-container SELinux MCS labels (by default)

Compromise of one service user does not grant access to other users' containers or to root.

## Quadlet Overview

Quadlet is a systemd generator included with Podman that converts declarative unit files into transient systemd services. Place files in the search paths and run `daemon-reload`; the generator creates corresponding `.service` units automatically.

**RHEL note:** While Quadlet was integrated upstream in Podman 4.4 (as a Technology Preview on RHEL), Red Hat documentation states Quadlet is fully supported beginning with **Podman v4.6**. Treat **4.6** as the minimum for production RHEL deployments.

### File Types

| Extension | Available From | Purpose |
|---|---|---|
| `.container` | 4.6+ | Run a container as a service |
| `.volume` | 4.6+ | Create a named Podman volume |
| `.network` | 4.6+ | Create a named Podman network |
| `.kube` | 4.6+ | Run a Kubernetes YAML manifest |
| `.image` | 4.8+ | Pull or import a container image |
| `.build` | 5.0+ | Build an image from a Containerfile |
| `.pod` | 5.0+ | Create and manage a Podman pod |

Do not assume availability purely from major version; verify on the target host (see **Feature Detection** under *Service Management*).

### Search Paths

**Rootful (system):**

| Path | Purpose |
|---|---|
| `/usr/share/containers/systemd/` | Vendor/RPM-provided units |
| `/etc/containers/systemd/` | Admin-managed units |

**Rootless (user):**

| Path | Purpose |
|---|---|
| `/etc/containers/systemd/users/<UID>/` | Admin-managed, per-user by UID |
| `/etc/containers/systemd/users/` | Admin-managed, all users |
| `~/.config/containers/systemd/` | User's own units |

For rootless RPM deployments, files go to `/etc/containers/systemd/users/<UID>/`. The UID is not known at build time, so the RPM ships vendor templates and copies the correct variant in `%post`.

## Rootless Prerequisites

### Service Account UID/GID Strategy

Decide whether service users get **stable numeric IDs** or **dynamically allocated IDs**:

- **Stable UID/GID (recommended for fleets / shared storage):**
  - Pick a numeric UID/GID from an organization-reserved range and use it consistently across hosts.
  - Maintain a simple registry (e.g., Git-managed `uids.csv`) to avoid collisions.
  - Benefits: predictable ownership on persistent volumes (including NFS), consistent audit correlation.

- **Dynamic UID/GID (acceptable for single hosts / local storage only):**
  - Use `useradd -r` (or `sysusers.d` with `-`) and let the system assign IDs.
  - Simpler, but volume ownership may break across nodes.

This is separate from subordinate ID ranges used for user namespaces (see below).

### Subordinate UID/GID Ranges

Rootless containers require subordinate ID mappings in `/etc/subuid` and `/etc/subgid`:

```
app_name:<start>:65536
```

Rules:
- Allocate **65536** IDs per user (full 16-bit range for container images)
- Ranges must **not overlap** across any users (including interactive users with auto-allocated ranges)
- Convention: start service user ranges at **1,000,000+** to avoid collision with interactive user auto-allocations (often ~100000)
- Inspect existing ranges before allocating: `cat /etc/subuid /etc/subgid | sort -t: -k2 -n`
- If ranges change after containers exist, run `podman system migrate` as the service user

### Lingering

Enable lingering so the user's systemd manager runs at boot without interactive login:

```bash
loginctl enable-linger app_name
```

In RPM scriptlets, directly creating `/var/lib/systemd/linger/<username>` is often more reliable (scriptlets may run in contexts where `systemd-logind` is not active).

### Networking Helper

Rootless networking requires one of:
- **slirp4netns** (NAT-based) -- default on Podman < 5.0
- **pasta** (from `passt` package) -- default on Podman >= 5.0, copies host network config

For deterministic fleet behavior, set `default_rootless_network_cmd` in `containers.conf` (admin policy decision) and ensure the corresponding package is installed (`slirp4netns` and/or `passt`). While `Network=` in a `.container` file can also accept mode values like `pasta` or `slirp4netns` (it maps to `podman run --network`), prefer `containers.conf` for site-wide policy and reserve `Network=` for attaching named networks (e.g., `Network=myapp.network`).

### Storage Driver

- **RHEL 8** (kernel < 5.11): Typically requires `fuse-overlayfs` for rootless overlay
- **RHEL 9+** (kernel >= 5.14): Native overlay in user namespaces typically available; `fuse-overlayfs` optional

Verify on the target host: `podman info --format '{{.Store.GraphDriverName}}'`

### cgroup v2

Quadlet requires **cgroup v2**. RHEL 9+ defaults to v2. RHEL 8 defaults to v1 and requires a kernel boot parameter:

```bash
grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=1"
# Requires reboot
```

Verify: `podman info --format '{{.Host.CgroupsVersion}}'` (must be `v2`).

## Air-Gapped Image Delivery

No registry required. Two common delivery patterns:

### Pattern A (Recommended): Bundle Image Tar as RPM Payload

The RPM ships a tarball into `/var/lib/app_name/images/` along with either a `.image` Quadlet unit (if supported) or a fallback `podman load` oneshot service.

Pros: fully offline install; no separate artifact management.

### Pattern B: External Image Drop

RPM creates directories and installs Quadlet units. Operator drops `/var/lib/app_name/images/app_name-image.tar` out-of-band.

### Creating the Tar

In the connected build environment:

```bash
podman save --format docker-archive -o app_name-image.tar localhost/app_name:1.2.3
# or: podman save --format oci-archive -o app_name-image.tar localhost/app_name:1.2.3
```

Ensure the desired tag is included in the archive. `docker-archive` is the most portable format; `podman load` restores the embedded tag automatically.

### Importing on the Air-Gapped Host

If `.image` Quadlet units are supported (Podman 4.8+), prefer them:

```ini
[Image]
Image=docker-archive:/var/lib/app_name/images/app_name-image.tar
ImageTag=localhost/app_name:1.2.3
```

The `.container` references `Image=app_name.image`, creating an automatic dependency.

Otherwise, use a fallback `podman load` oneshot service (see `references/reference.md`).

### Image Tar Ownership

The tar must be readable by the service user:

```bash
install -d -m 0750 -o app_name -g app_name /var/lib/app_name/images
chown app_name:app_name /var/lib/app_name/images/app_name-image.tar
chmod 0640 /var/lib/app_name/images/app_name-image.tar
```

### Avoiding Slow or Failed Starts

When importing large images, systemd's default `TimeoutStartSec` (often 90s) can be too short. Set explicitly:

```ini
[Service]
TimeoutStartSec=900
```

## RPM Packaging Pattern

### Vendor Template Strategy

Ship both Podman 4.x and 5.x variants as vendor templates in an RPM-tracked directory. Detect the Podman version in `%post` and copy the correct variant to the UID-specific rootless path.

```
/usr/share/app_name-quadlet/quadlet/
    app_name.container.podman5    # Podman 5.x variant
    app_name.container.podman4    # Podman 4.x variant
    app_name.image                # if target supports .image units
    app_name-image-load.service   # fallback when .image is not available
```

### Install-If-Absent

Treat Quadlet files in `/etc/containers/systemd/users/<UID>/` as admin-managed. On upgrades, do not overwrite if the file already exists:

```bash
if [ ! -e "$quadlet_dir/app_name.container" ]; then
    install -m 0644 "$vendor_dir/app_name.container.podman5" \
        "$quadlet_dir/app_name.container"
fi
```

### Quadlet Directory Ownership

Keep `/etc/containers/systemd/users/<UID>/` and its files **root:root** (mode 0755/0644). The Quadlet generator reads these files during the user's `daemon-reload` and does not require user ownership. Making policy files writable by the service user would allow a compromised container process to modify its own unit definition on next restart.

Only **data directories** (`/var/lib/app_name`, image tar directory, etc.) should be owned by the service user.

### Policy Toggles

Use RPM macros to control whether the RPM makes policy-sensitive system changes:

```specfile
%global manage_linger  0    # 1 = RPM enables lingering
%global manage_subids  0    # 1 = RPM allocates subuid/subgid ranges
```

Default to **off** in restricted environments. Document that admins must provision these manually if toggles are disabled.

### Mutual Exclusivity

If shipping both native and containerized variants of an application:

```specfile
# In app_name-quadlet.spec:
Conflicts: app_name

# In app_name.spec:
Conflicts: app_name-quadlet
```

### Directory Ownership via tmpfiles.d

The service user may not exist on the build host, so `%attr` cannot reliably set ownership by username. Use `tmpfiles.d` as the authoritative ownership mechanism:

```ini
# /usr/lib/tmpfiles.d/app_name.conf
d /var/lib/app_name        0750 app_name app_name -
d /var/lib/app_name/images 0750 app_name app_name -
d /var/log/app_name        0750 app_name app_name -
```

Apply in `%post`:

```bash
systemd-tmpfiles --create /usr/lib/tmpfiles.d/app_name.conf >/dev/null 2>&1 || :
```

### Scriptlet Overview

| Scriptlet | Purpose |
|---|---|
| `%pre` | Create service user/group if missing |
| `%post` | Apply tmpfiles, detect Podman version, install Quadlet files (install-if-absent), optionally manage subids/linger |
| `%preun` ($1=0) | Stop user service, remove Quadlet files from UID path, rmdir if empty |
| `%postun` ($1=0) | Reload user manager (best-effort) |

All scriptlets must be **defensive**: do not fail the install if systemd/logind are not running (image builds, chroots).

### RPM Scriptlet Argument (`$1`)

| Scriptlet | Fresh Install | Upgrade | Uninstall |
|---|---|---|---|
| `%pre` | 1 | 2 | (not run) |
| `%post` | 1 | 2 | (not run) |
| `%preun` | (not run) | 1 | 0 |
| `%postun` | (not run) | 1 | 0 |

During upgrade, execution order is: new `%pre` -> new files installed -> new `%post` -> old `%preun` -> old files removed -> old `%postun`.

### Podman Version Detection in %post

```bash
podman_major=4
podman_minor=6
if command -v podman >/dev/null 2>&1; then
    podman_ver="$(podman --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
    podman_major="$(echo "$podman_ver" | cut -d. -f1)"
    podman_minor="$(echo "$podman_ver" | cut -d. -f2)"
    [ -z "$podman_major" ] && podman_major=4
    [ -z "$podman_minor" ] && podman_minor=6
fi

# .image units are available in Podman 4.8+
supports_image_unit=0
if [ "$podman_major" -gt 4 ] || { [ "$podman_major" -eq 4 ] && [ "$podman_minor" -ge 8 ]; }; then
    supports_image_unit=1
fi
```

Default to 4.6 if detection fails (safer fallback). Gate `.image` usage on 4.8+, not just major version 5.

### Dependencies

```specfile
Requires:       podman >= 4.6
Requires:       systemd
Requires:       shadow-utils
Requires:       slirp4netns
Requires:       container-selinux

# pasta networking (RHEL 9+; passt package introduced in RHEL 9.2)
%if 0%{?rhel} && 0%{?rhel} >= 9
Recommends:     passt
%endif

# fuse-overlayfs: typically required on EL8 for rootless
%if 0%{?rhel} && 0%{?rhel} < 9
Requires:       fuse-overlayfs
%else
Recommends:     fuse-overlayfs
%endif
```

## Service Management

### Feature Detection

On the target host, verify what Quadlet supports:
- Consult `podman-systemd.unit(5)` on the host
- Dry-run the generator to catch syntax errors:

```bash
/usr/libexec/podman/quadlet --dryrun --user \
    /etc/containers/systemd/users/$(id -u app_name)/
```

### Preferred Command Style

Operate rootless user services without interactive `su`:

```bash
systemctl --user --machine=app_name@.host daemon-reload
systemctl --user --machine=app_name@.host start app_name.service
systemctl --user --machine=app_name@.host status app_name.service
journalctl --user --machine=app_name@.host -u app_name.service -b
```

Requirements:
- `systemd-machined.service` must be running on the host
- The user manager must be running (lingering enabled + `user@UID.service` active)

**Important:** Quadlet-generated services are transient; do **not** `systemctl enable` them. The Quadlet generator applies the `[Install]` section (e.g., `WantedBy=default.target`) automatically during generation. Use `start`/`restart`/`stop` only.

### Fallback (if `--machine=` is unavailable)

```bash
sudo -u app_name \
    XDG_RUNTIME_DIR="/run/user/$(id -u app_name)" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u app_name)/bus" \
    systemctl --user status app_name.service
```

## SELinux

### Volume Mount Labels

| Flag | Behavior | Use When |
|---|---|---|
| `:Z` | Private relabel (container's MCS label) | Volume exclusively used by one container (e.g., `/var/lib/app_name`) |
| `:z` | Shared relabel (`container_file_t:s0`) | Volume shared between multiple containers |
| (none) | No relabel | System directories; set context administratively |

**Never** use `:z` or `:Z` on system directories (`/etc`, `/usr`, `/home`). For `/etc/app_name`, set the context manually:

```bash
semanage fcontext -a -t container_file_t "/etc/app_name(/.*)?"
restorecon -R /etc/app_name
```

### MCS Isolation

Avoid setting `SecurityLabelLevel=s0` unless you fully understand the consequences. The default behavior assigns a unique MCS label per container, providing mandatory access control isolation even between containers under the same Unix user.

## RHEL Platform Differences

| Feature | RHEL 8 | RHEL 9 | RHEL 10 |
|---|---|---|---|
| Podman delivery | Module streams | RPM | RPM |
| Podman version range | 4.x | 4.x – 5.x | 5.x |
| Quadlet support (RHEL GA) | Podman >= 4.6 | Podman >= 4.6 | Yes |
| Default cgroups | v1 (must enable v2) | v2 | v2 |
| OCI runtime | runc | crun | crun |
| Rootless network default | slirp4netns | slirp4netns (4.x) / pasta (5.x) | pasta |
| Rootless overlay | fuse-overlayfs typically required | native overlay typical | native overlay |
| `.image` Quadlet | Podman >= 4.8 | Podman >= 4.8 | Yes |

**RHEL 8 module streams:** The `container-tools:rhel8` rolling stream provides Podman 4.6+ with Quadlet. The `container-tools:4.0` stable stream ships Podman 4.0 which does **not** include Quadlet. Ensure the rolling stream is enabled:

```bash
dnf module enable container-tools:rhel8
```

## Privileged Ports

Rootless containers cannot bind ports < 1024 by default. Options:
- **Unprivileged ports** (8080/8443) with a reverse proxy in front (most common)
- **Sysctl**: `net.ipv4.ip_unprivileged_port_start=80` (host-wide change, requires policy approval)
- **Firewall redirect**: `firewall-cmd --add-forward-port=port=80:proto=tcp:toport=8080`

## Upgrade/Rollback

1. Install/upgrade RPM: `dnf upgrade ./app_name-quadlet-NEW.rpm`
2. Update image tar (bundled via RPM or dropped externally)
3. Reload user manager: `systemctl --user --machine=app_name@.host daemon-reload`
4. Restart: `systemctl --user --machine=app_name@.host restart app_name.service`

If the host Podman version changed (e.g., EL8 to EL9 migration), reinstall the RPM to trigger `%post` version detection:

```bash
dnf reinstall app_name-quadlet
```

Rollback is symmetric: reinstall old RPM + old image tar, restart.

## Reference Files

| File | Contents | Load when |
|---|---|---|
| `references/reference.md` | Complete Quadlet syntax for all file types, Podman 4.x/5.x directive compatibility table, annotated RPM spec file, sysusers.d integration, UID/GID allocation patterns, container user mapping, troubleshooting checklist, test matrix, log aggregation notes | Writing Quadlet files, building an RPM spec, debugging deployment issues, or verifying a test matrix |
