# Reference

Complete Quadlet syntax, annotated RPM spec file, sysusers.d integration, troubleshooting, test matrix, and log aggregation notes for rootless Podman RPM deployments.

## Quadlet `.container` Syntax

```ini
[Unit]
Description=My Application Container
After=network-online.target
Wants=network-online.target

[Container]
# === Image and Identity ===
Image=registry.example.com/myapp:1.0    # or Image=myapp.image (Podman 4.8+)
ContainerName=myapp
Entrypoint=/usr/bin/myapp
Exec=--config /etc/myapp/config.yaml

# === Image Pull ===
Pull=never                               # Podman 4.6+; critical for air-gapped

# === Networking ===
Network=myapp.network                    # reference to .network Quadlet (creates dependency)
PublishPort=8080:8080
PublishPort=8443:8443
HostName=myapp
DNS=10.0.0.1
DNSSearch=example.com
AddHost=db:10.89.0.11
IP=10.89.0.10

# === Storage ===
Volume=myapp-data.volume:/var/lib/myapp:Z   # reference to .volume Quadlet (creates dependency)
Volume=/etc/myapp:/etc/myapp:ro              # bind mount, read-only, no relabel
Mount=type=tmpfs,destination=/tmp
Tmpfs=/run

# === Environment ===
Environment=APP_ENV=production
EnvironmentFile=/etc/myapp/env

# === User/Group Mapping ===
# For rootless services, keep-id maps the host service user's UID/GID into the container.
UserNS=keep-id
# If the image expects a specific UID inside the container (e.g., 1000), use:
#   UserNS=keep-id:uid=1000,gid=1000
# Avoid setting User=/Group= alongside keep-id; they override the process UID independently
# of the namespace mapping, which can cause the process to run under a subordinate UID
# instead of the host service user's identity.

# === Security ===
NoNewPrivileges=true
DropCapability=ALL                       # Podman 4.6+
AddCapability=CAP_NET_BIND_SERVICE       # add back specific caps if needed
ReadOnly=true
ReadOnlyTmpfs=true                       # Podman 4.8+; omit for earlier 4.x
SeccompProfile=/etc/myapp/seccomp.json
SecurityLabelType=container_runtime_t
# Do NOT set SecurityLabelLevel=s0 unless you have a specific reason

# === Health Checks ===
HealthCmd=curl -f http://localhost:8080/health || exit 1
HealthInterval=30s
HealthRetries=3
HealthStartPeriod=10s
HealthTimeout=5s
HealthOnFailure=kill                     # Podman 4.6+; kill integrates best with systemd Restart=

# === Auto-Update (optional) ===
# AutoUpdate=registry                    # for connected environments; checks remote registry
# AutoUpdate=local                       # for air-gapped; checks local storage only (no registry contact)

# === Logging ===
LogDriver=journald

# === Resource Limits ===
PidsLimit=4096
ShmSize=256m

# === Pass-Through ===
PodmanArgs=--memory 512m --cpus 2        # arbitrary podman run flags

[Service]
Restart=always
RestartSec=10
TimeoutStartSec=900
TimeoutStopSec=60

[Install]
WantedBy=default.target                  # rootless
# WantedBy=multi-user.target             # rootful
```

### Podman 4.x vs 5.x Directive Compatibility (RHEL-Focused)

Quadlet features expanded across Podman 4.x minor releases. Do not treat compatibility as simply "4 vs 5."

| Directive / Feature | Podman 4.6+ (RHEL baseline) | Podman 4.8+ | Podman 5.x | Notes |
|---|---|---|---|---|
| `Pull=never` | Yes | Yes | Yes | Prefer `Pull=never` for air-gapped stability |
| `DropCapability=ALL` | Yes | Yes | Yes | Available in 4.6+ Quadlet |
| `HealthOnFailure=kill` | Yes | Yes | Yes | Available in 4.6+; `kill` integrates best with systemd `Restart=` |
| `ReadOnlyTmpfs=true` | No | Yes | Yes | Present in 4.8+ docs; omit for early 4.x |
| `.image` unit type + `Image=name.image` | No | Yes | Yes | `.image` available from 4.8+; if unavailable, use `podman load` fallback |
| `AutoUpdate=` | Yes | Yes | Yes | `registry` and `local` policies both available |

If you must support multiple Podman 4 minor versions, keep two variants:
- **Baseline (4.6-compatible)**: avoid `.image` and `ReadOnlyTmpfs`
- **Enhanced (4.8+/5.x)**: may use `.image` and additional hardening flags

## Quadlet `.image` Syntax (Podman 4.8+/5.x)

Quadlet `.image` units generate a oneshot systemd service that ensures an image is present in the local store. Useful for air-gapped deployments because they can import from `docker-archive:` or `oci-archive:` without contacting a registry.

Before using `.image` on a target host, verify support by checking the local `podman-systemd.unit(5)` man page or running the Quadlet generator in `--dryrun` mode.

```ini
[Unit]
Description=app_name image import (air-gapped)

[Image]
Image=docker-archive:/var/lib/app_name/images/app_name-image.tar
ImageTag=localhost/app_name:1.2.3

[Install]
WantedBy=default.target
```

The `Image=` value supports transport prefixes: `docker-archive:`, `oci-archive:`, `docker://`, `oci:`.

## Quadlet `.volume` Syntax

```ini
[Unit]
Description=MyApp Data Volume

[Volume]
VolumeName=myapp-data
Label=app=myapp
Driver=local
# Rootless: omit User=/Group= (volume is owned by the rootless service user).
# Rootful: you may set User=/Group= to control host ownership.
```

Default volume name: `systemd-<unitname>`.

## Quadlet `.network` Syntax

```ini
[Unit]
Description=MyApp Network

[Network]
NetworkName=myapp-net
Driver=bridge
Subnet=10.89.0.0/24
Gateway=10.89.0.1
IPv6=false
Internal=false
Label=app=myapp
```

Default network name: `systemd-<unitname>`.

## Annotated RPM Spec File

This is an annotated reference spec for a rootless Quadlet RPM. Customize `Name`, `Version`, sources, and Quadlet contents for your application.

```specfile
Name:           app_name-quadlet
Version:        1.2.3
Release:        1%{?dist}
Summary:        app_name as a rootless Podman Quadlet user service
License:        Proprietary
URL:            https://example.invalid/app_name
BuildArch:      noarch

# --- Policy toggles (default: off for restricted environments) ---
%global manage_linger  0
%global manage_subids  0

# --- Service identity ---
%global svc_user    app_name
%global svc_group   app_name

# --- Paths ---
%global etc_dir     /etc/app_name
%global varlib_dir  /var/lib/app_name
%global img_dir     %{varlib_dir}/images
%global img_tar     %{img_dir}/app_name-image.tar
%global quadlet_vendor_dir  %{_datadir}/%{name}/quadlet
%global quadlet_rootless_base /etc/containers/systemd/users

# --- Dependencies ---
Requires:       podman >= 4.6
Requires:       systemd
Requires:       shadow-utils
Requires:       slirp4netns
Requires:       container-selinux

# fuse-overlayfs: required on EL8 (kernel < 5.11), optional on EL9+
%if 0%{?rhel} && 0%{?rhel} < 9
Requires:       fuse-overlayfs
%else
Recommends:     fuse-overlayfs
%endif

# Mutual exclusivity with native variant
Conflicts:      app_name

%description
Rootless Podman/Quadlet deployment of app_name.
Supports Podman 4.x (EL8) and Podman 5.x (EL9/EL10).
Air-gapped: container image provided out-of-band.

# --- %install: ship vendor templates and config dirs ---
%install
rm -rf %{buildroot}

# Vendor quadlet templates (tracked by RPM)
install -d %{buildroot}%{quadlet_vendor_dir}
# ... create app_name.container.podman5, app_name.container.podman4,
#     app_name.image, app_name-image-load.service here ...

# Config and state directories
install -d %{buildroot}%{etc_dir}
install -d %{buildroot}%{varlib_dir}
install -d %{buildroot}%{img_dir}

# Example env file (noreplace so admin edits are preserved)
cat > %{buildroot}%{etc_dir}/app_name.env <<'EOF'
# app_name environment overrides
EOF

# tmpfiles.d for directory ownership (see note below)
install -d %{buildroot}%{_tmpfilesdir}
cat > %{buildroot}%{_tmpfilesdir}/app_name.conf <<EOF
d %{varlib_dir} 0750 %{svc_user} %{svc_group} -
d %{img_dir}    0750 %{svc_user} %{svc_group} -
EOF

# --- %pre: create service user/group ---
%pre
getent group %{svc_group} >/dev/null || groupadd -r %{svc_group}
getent passwd %{svc_user} >/dev/null || \
    useradd -r -g %{svc_group} -d %{varlib_dir} -s /sbin/nologin \
    -c "app_name service account" %{svc_user}

# --- %post: install Quadlet files to UID path ---
%post
# Apply tmpfiles (sets ownership on varlib/img dirs)
if [ -x /usr/bin/systemd-tmpfiles ]; then
    /usr/bin/systemd-tmpfiles --create %{_tmpfilesdir}/app_name.conf >/dev/null 2>&1 || :
fi

svc_uid="$(id -u %{svc_user} 2>/dev/null || echo "")"
if [ -z "$svc_uid" ]; then
    echo "WARNING: service user %{svc_user} not found; skipping Quadlet installation." >&2
    exit 0
fi

# Detect Podman version (major.minor)
podman_major=4
podman_minor=6
if command -v podman >/dev/null 2>&1; then
    podman_ver="$(podman --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
    podman_major="$(echo "$podman_ver" | cut -d. -f1)"
    podman_minor="$(echo "$podman_ver" | cut -d. -f2)"
    [ -z "$podman_major" ] && podman_major=4
    [ -z "$podman_minor" ] && podman_minor=6
fi

# .image units are available in Podman 4.8+ (and all 5.x)
supports_image_unit=0
if [ "$podman_major" -gt 4 ] || { [ "$podman_major" -eq 4 ] && [ "$podman_minor" -ge 8 ]; }; then
    supports_image_unit=1
fi

# Create rootless Quadlet directory for this user (root-owned; admin-managed policy)
install -d -m 0755 %{quadlet_rootless_base}/$svc_uid

# Install Quadlet files (install-if-absent; admin-managed once present)
if [ "$supports_image_unit" -eq 1 ]; then
    # Podman 4.8+/5.x: native .image Quadlet
    [ ! -e %{quadlet_rootless_base}/$svc_uid/app_name.image ] && \
        install -m 0644 %{quadlet_vendor_dir}/app_name.image \
            %{quadlet_rootless_base}/$svc_uid/app_name.image
    [ ! -e %{quadlet_rootless_base}/$svc_uid/app_name.container ] && \
        install -m 0644 %{quadlet_vendor_dir}/app_name.container.podman5 \
            %{quadlet_rootless_base}/$svc_uid/app_name.container
    # Clean up fallback if present
    rm -f %{quadlet_rootless_base}/$svc_uid/app_name-image-load.service 2>/dev/null || :
else
    # Podman 4.6-4.7: no .image unit; use fallback systemd load service
    [ ! -e %{quadlet_rootless_base}/$svc_uid/app_name-image-load.service ] && \
        install -m 0644 %{quadlet_vendor_dir}/app_name-image-load.service \
            %{quadlet_rootless_base}/$svc_uid/app_name-image-load.service
    [ ! -e %{quadlet_rootless_base}/$svc_uid/app_name.container ] && \
        install -m 0644 %{quadlet_vendor_dir}/app_name.container.podman4 \
            %{quadlet_rootless_base}/$svc_uid/app_name.container
    # Clean up .image if present
    rm -f %{quadlet_rootless_base}/$svc_uid/app_name.image 2>/dev/null || :
fi

# Do NOT chown the Quadlet directory to the service user.
# Quadlet policy files should remain root:root (0755/0644) so the service user
# cannot modify its own unit definitions. The Quadlet generator reads these files
# during daemon-reload and does not require user ownership.

# Optional: allocate subids (policy-controlled)
if [ "%{manage_subids}" = "1" ]; then
    if ! grep -qE '^%{svc_user}:' /etc/subuid 2>/dev/null; then
        start=1000000
        if [ -r /etc/subuid ] && [ -s /etc/subuid ]; then
            last_end=$(awk -F: '{end=$2+$3; if(end>max) max=end} END{if(max) print max}' /etc/subuid)
            [ -n "$last_end" ] && [ "$last_end" -gt "$start" ] 2>/dev/null && start=$last_end
        fi
        echo "%{svc_user}:$start:65536" >> /etc/subuid || :
    fi
    if ! grep -qE '^%{svc_user}:' /etc/subgid 2>/dev/null; then
        start=1000000
        if [ -r /etc/subgid ] && [ -s /etc/subgid ]; then
            last_end=$(awk -F: '{end=$2+$3; if(end>max) max=end} END{if(max) print max}' /etc/subgid)
            [ -n "$last_end" ] && [ "$last_end" -gt "$start" ] 2>/dev/null && start=$last_end
        fi
        echo "%{svc_user}:$start:65536" >> /etc/subgid || :
    fi
fi

# Optional: enable lingering (policy-controlled)
if [ "%{manage_linger}" = "1" ]; then
    mkdir -p /var/lib/systemd/linger
    touch /var/lib/systemd/linger/%{svc_user}
fi

# Best-effort: start user manager and reload
/bin/systemctl start user@"$svc_uid".service >/dev/null 2>&1 || :
/bin/systemctl --user --machine=%{svc_user}@.host daemon-reload >/dev/null 2>&1 || :

# --- %preun: clean up ghost files ---
%preun
if [ $1 -eq 0 ]; then
    svc_uid="$(id -u %{svc_user} 2>/dev/null || echo "")"
    /bin/systemctl --user --machine=%{svc_user}@.host stop app_name.service >/dev/null 2>&1 || :
    if [ -n "$svc_uid" ]; then
        rm -f %{quadlet_rootless_base}/$svc_uid/app_name.image 2>/dev/null || :
        rm -f %{quadlet_rootless_base}/$svc_uid/app_name.container 2>/dev/null || :
        rm -f %{quadlet_rootless_base}/$svc_uid/app_name-image-load.service 2>/dev/null || :
        rmdir %{quadlet_rootless_base}/$svc_uid 2>/dev/null || :
    fi
fi

# --- %postun: reload user manager ---
%postun
if [ $1 -eq 0 ]; then
    /bin/systemctl --user --machine=%{svc_user}@.host daemon-reload >/dev/null 2>&1 || :
fi

# --- %files: only RPM-tracked content ---
%files
%dir %{quadlet_vendor_dir}
%{quadlet_vendor_dir}/app_name.image
%{quadlet_vendor_dir}/app_name.container.podman5
%{quadlet_vendor_dir}/app_name.container.podman4
%{quadlet_vendor_dir}/app_name-image-load.service

%dir %{etc_dir}
%config(noreplace) %{etc_dir}/app_name.env

%{_tmpfilesdir}/app_name.conf

# Ownership set by tmpfiles.d, not %attr
%dir %{varlib_dir}
%dir %{img_dir}
```

### Key Design Decisions

**Why tmpfiles.d instead of %attr?** The service user may not exist on the build host (e.g., in mock/koji). `%attr(-, app_name, app_name)` would fail at build time. tmpfiles.d defers ownership to install time when the user exists.

**Why install-if-absent?** Quadlet files in the UID path are admin-managed. Overwriting on upgrade would destroy admin customizations. Ship vendor templates and only copy on first install.

**Why clean up in %preun?** Quadlet files in `/etc/containers/systemd/users/<UID>/` are created in `%post`, not listed in `%files`. RPM does not track them, so explicit removal is required.

**Why default policy toggles to off?** In restricted environments (DoD, FedRAMP, STIG), modifying `/etc/subuid`, `/etc/subgid`, or enabling lingering may require change management approval. The RPM should not silently alter security posture.

**Why keep Quadlet directory root-owned?** Quadlet files in `/etc/containers/systemd/users/<UID>/` represent admin-managed policy. Chowning them to the service user would allow a compromised container (running as the service user) to modify its own unit definition. Keep them root:root (0755/0644). The Quadlet generator reads these files and does not require user ownership.

## sysusers.d Integration

Modern approach for service user creation (alternative to manual `useradd` in `%pre`).

### sysusers.d File

```ini
# /usr/lib/sysusers.d/app_name.conf
u app_name - "app_name service account" /var/lib/app_name /sbin/nologin
```

### RPM Integration by Platform

| Platform | Approach |
|---|---|
| RHEL 8/9 | `%sysusers_create_compat` macro in `%pre` (generates `useradd`/`groupadd` commands) |
| Fedora 42+ | Native RPM 4.19+ support (no scriptlet needed, just package the file) |

```specfile
Source1: app_name.sysusers

BuildRequires: systemd-rpm-macros

%install
install -D -m 0644 %{SOURCE1} %{buildroot}%{_sysusersdir}/app_name.conf

%pre
%sysusers_create_compat %{SOURCE1}

%files
%{_sysusersdir}/app_name.conf
```

sysusers.d does **not** allocate subuid/subgid ranges. Handle those separately in `%post` (see policy toggles in the spec above).

## Service User UID/GID Strategy

This skill assumes one rootless service user per application. Decide whether you need stable numeric IDs.

### When Stable UID/GID Matters

Use a fixed UID/GID when:
- Multiple hosts access the same persistent storage (NFS/Gluster/etc.)
- You need predictable ownership during fleet rollouts
- Host-based ACLs or audit rules are keyed by numeric UID

### Recommended Allocation Pattern

Reserve an organizational range (example: 20000-29999). Track assignments in a small registry (Git-managed file, CMDB, etc.). In the RPM, expose macros and use them consistently:

```specfile
%global svc_user  app_name
%global svc_group app_name
%global svc_uid   20010
%global svc_gid   20010
```

Then in `%pre`:

```bash
getent group %{svc_group} >/dev/null || groupadd -r -g %{svc_gid} %{svc_group} || :
getent passwd %{svc_user} >/dev/null || \
    useradd -r -u %{svc_uid} -g %{svc_gid} -d /var/lib/%{svc_user} \
    -s /sbin/nologin -c "%{svc_user} service account" %{svc_user} || :
```

### Container User Mapping and Volume Ownership

Rootless containers cannot write to host directories unless UID/GID mappings line up. The recommended baseline:

- Use `UserNS=keep-id` in the `.container` file (maps the host service user's UID/GID to the same values inside the container)
- Ensure the container image runs its process as a non-root user matching the service UID, or set `User=`/`Group=` in the `.container` file
- Own persistent host directories by the service user (via `tmpfiles.d`)

Advanced mappings using explicit UID/GID maps exist but are beyond the baseline packaging pattern; if you need them, document the mapping contract explicitly in the application's deployment guide.

## Podman 4.x Fallback Load Service

Use this when the target host does not support Quadlet `.image` units.

Best practice: create the tarball with the final tag already embedded (e.g., `localhost/app_name:1.2.3`). Then `podman load` restores the tag automatically and no post-tagging heuristics are needed.

Template: `app_name-image-load.service`

```ini
[Unit]
Description=app_name image import (air-gapped, Podman 4.x fallback)
ConditionPathExists=/var/lib/app_name/images/app_name-image.tar

[Service]
Type=oneshot
RemainAfterExit=yes
TimeoutStartSec=900
ExecStart=/usr/bin/podman load -i /var/lib/app_name/images/app_name-image.tar

[Install]
WantedBy=default.target
```

Wire it from the `.container` unit via dependencies:

```ini
[Unit]
Requires=app_name-image-load.service
After=app_name-image-load.service
```

## Podman Auto-Update

### Connected Environments: `AutoUpdate=registry`

```ini
[Container]
Image=registry.example.com/app_name:latest
AutoUpdate=registry
```

Checks remote registry for newer digests. Enable the timer for the service user:

```bash
systemctl --user --machine=app_name@.host enable --now podman-auto-update.timer
```

### Air-Gapped Environments: `AutoUpdate=local`

```ini
[Container]
Image=localhost/app_name:latest
AutoUpdate=local
```

Compares the running container's image digest against the same tag in local storage. No registry contact occurs. Update workflow:
1. Transfer new image tar to the host
2. Load: `runuser -u app_name -- podman load -i /path/to/new-image.tar`
3. Trigger: `podman auto-update` or wait for the `podman-auto-update.timer`

**Note:** For RPM-packaged deployments, explicit rollout (upgrade RPM, load tar, restart service) is generally preferred over timer-driven auto-update, as it provides clearer audit trails and aligns with change management processes in restricted environments.

## Troubleshooting Checklist

### "Unit not found"

1. Verify Quadlet files exist: `ls -la /etc/containers/systemd/users/$(id -u app_name)/`
2. Run generator dry-run: `/usr/libexec/podman/quadlet --dryrun --user /etc/containers/systemd/users/$(id -u app_name)/`
3. Reload user manager: `systemctl --user --machine=app_name@.host daemon-reload`

### "Permission denied / cannot chown / ID mapping"

1. Check subuid/subgid: `grep app_name /etc/subuid /etc/subgid`
2. Verify 65536 count and no overlaps: `cat /etc/subuid | sort -t: -k2 -n`
3. If subids changed after first use: `runuser -u app_name -- podman system migrate`

### `--machine=app_name@.host` fails

1. **User manager not running:** `systemctl start user@$(id -u app_name).service`
2. **systemd-machined not running:** `systemctl start systemd-machined.service && systemctl enable systemd-machined.service`
3. **Lingering not enabled:** `loginctl show-user app_name -p Linger`

### Image import fails

1. Verify tar exists and is readable: `runuser -u app_name -- test -r /var/lib/app_name/images/app_name-image.tar && echo OK`
2. On Podman 4.8+/5.x: `systemctl --user --machine=app_name@.host status app_name-image.service`
3. On Podman 4.x (fallback): `systemctl --user --machine=app_name@.host status app_name-image-load.service`
4. Manual load: `runuser -u app_name -- podman load -i /var/lib/app_name/images/app_name-image.tar`

### SELinux AVC denials

1. Check: `ausearch -m avc -ts recent | grep app_name`
2. For `/var/lib/app_name`: the `:Z` flag should handle this automatically
3. For `/etc/app_name`: set context manually with `semanage fcontext` (see SELinux section in SKILL.md)

## Test Matrix

### Host-Level Checks

- `podman --version` -- note major and minor version
- `podman info --format '{{.Host.CgroupsVersion}}'` -- must be `v2`
- `command -v newuidmap newgidmap` -- both present
- `rpm -q slirp4netns` -- present
- `rpm -q fuse-overlayfs` -- present (required on EL8)

### Service User Checks

- `/etc/subuid` and `/etc/subgid` contain `app_name:*:65536` with no overlaps
- `loginctl show-user app_name -p Linger` reports `Linger=yes`
- `systemctl status user@$(id -u app_name).service` is active

### Quadlet Verification

- Files exist in `/etc/containers/systemd/users/<UID>/`
- Generator dry-run produces valid output (no errors)
- `daemon-reload` succeeds
- Service is visible: `systemctl --user --machine=app_name@.host list-units | grep app_name`

### Air-Gapped Image Checks

**Podman 4.8+/5.x (`.image` Quadlet):**
- Image tar exists and is readable by service user
- `app_name-image.service` imports image successfully
- `runuser -u app_name -- podman images` shows expected tag
- Container starts without pull attempts

**Podman 4.x (fallback load service):**
- Image tar exists and is readable by service user
- `app_name-image-load.service` loads image and restores tag
- `runuser -u app_name -- podman images` shows expected tag
- Container starts after load service completes

### Runtime Checks

- Application endpoint responds (e.g., `curl http://localhost:8080/health`)
- Journald logs exist: `journalctl --user --machine=app_name@.host -u app_name.service --no-pager -n 20`
- No SELinux AVC denials: `ausearch -m avc -ts recent | grep app_name`
- Volume mounts have correct SELinux context: `ls -laZ /var/lib/app_name/`

## Log Aggregation

Rootless container logs go to the **user journal**, not the system journal. Configure log collectors (rsyslog, Fluentd, SIEM forwarders) to capture user journals.

Key journal fields for correlation:
- `_UID` -- service user's UID
- `_SYSTEMD_USER_UNIT` -- systemd user unit name
- `CONTAINER_NAME` -- Podman container name

User journals are stored in:
- `/run/log/journal/<machine-id>/` (volatile)
- `/var/log/journal/<machine-id>/` (persistent, if configured)

To view another user's journal from an admin account:
- Use `--machine=` (preferred)
- Or add the admin to the `systemd-journal` group and filter: `journalctl _UID=<service-user-uid>`
