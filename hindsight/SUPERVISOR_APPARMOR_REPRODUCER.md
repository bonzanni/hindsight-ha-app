# Supervisor reproducer: changed app profile can retain stale compiled policy

## Summary

Updating a repository app whose `apparmor.txt` changed did not reliably replace
the policy enforced by the kernel. Supervisor stored the new source profile,
but the container continued to behave as if an older compiled cache entry were
loaded. Update, restart, reinstall, and host reboot did not correct it. Removing
the one app's stale compiled entries and then running an app update finally
caused recompilation.

## Observed environment

- Home Assistant Supervisor 2026.06.2
- HAOS 18.1 on `generic-x86-64` / amd64
- Repository app slug/profile: `5884eb17_hindsight`
- Affected transition: Hindsight `0.2.0` → `0.2.1`; `0.2.2` was published only
  to force another profile-load attempt
- Rechecked read-only on 2026-07-12: the running container reports
  `5884eb17_hindsight` from Docker's `.AppArmorProfile`, and Supervisor stores
  the corrected source at `/data/apps/git/5884eb17/hindsight/apparmor.txt`
- Observed compiled cache entry:
  `/data/apparmor/cache/2b809d0d.0/5884eb17_hindsight`

## Minimal profile change

Old profile:

```text
signal (send),
```

New profile:

```text
signal (send,receive),
```

All s6, shell, API, and pg0 processes share this one profile. AppArmor checks a
signal at both ends, so the old rule prevents in-container shutdown signalling.

## Reproduction and evidence

1. Install the old version and verify the container is confined:

   ```bash
   docker inspect --format '{{.AppArmorProfile}}' addon_5884eb17_hindsight
   # 5884eb17_hindsight
   ```

2. Update the repository so its stored profile contains the new rule. Confirm
   independently inside the Supervisor container:

   ```bash
   docker exec hassio_supervisor grep -n signal \
     /data/apps/git/5884eb17/hindsight/apparmor.txt
   # signal (send,receive),
   ```

3. Update the app, then send a harmless signal between processes inside the
   confined container:

   ```bash
   docker exec addon_5884eb17_hindsight kill -CONT 1
   ```

   In the stale state this returned `Operation not permitted`. A Supervisor
   stop then exhausted its grace period and the container exited `137`, which
   is behavioral evidence that the loaded policy still lacked receive access.
4. Record the compiled entry before recovery:

   ```bash
   docker exec hassio_supervisor find /data/apparmor/cache \
     -name 5884eb17_hindsight -print
   ```

   Also capture its timestamp, the stored source-profile hash, Docker's active
   profile name, Supervisor/HAOS versions, the update API response, and relevant
   kernel AppArmor denials.
5. Restart, reinstall, and reboot were each observed not to recompile the
   changed profile. At the time, a genuinely newer version (`0.2.2`) was
   available. The operation that finally worked was:

   - stop the app;
   - remove only
     `/data/apparmor/cache/*/5884eb17_hindsight` inside the Supervisor
     container;
   - invoke the Supervisor app **update** operation;
   - start and repeat `SIGCONT` plus Supervisor stop.

   After that update, `SIGCONT` succeeded and Supervisor stop exited cleanly.
   A same-version update after reaching the latest version is not a valid
   recovery trigger; reproduce this only with a pending newer version.

## Expected behavior

When the source content of an app's `apparmor.txt` changes, the next install or
update should invalidate any compiled entry for that app and load policy built
from the new source. A normal operator should never need to mutate Supervisor's
cache directly.

## Safety boundary

The Hindsight image does not access host policy/cache paths, disable AppArmor,
request host privileges, or broaden its profile. Cache removal is an exceptional
maintainer recovery performed only after evidence collection, scoped to this
single profile, and must not become an app startup action or routine user step.
