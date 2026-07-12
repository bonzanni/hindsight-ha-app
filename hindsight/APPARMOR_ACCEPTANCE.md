# Hindsight v0.3.0 HAOS acceptance

This is the release gate for the published image on the configured production
Home Assistant OS host. It must be run after the GHCR publication workflow has
succeeded. It is not reproduced by plain `docker run`, which is unconfined.

Use the production-console scripts from the repository root with `HPC_CODEX=1`.
The configured target must remain `5884eb17_hindsight`; stop if target checks
or Supervisor health checks fail. Because production requires confirmation,
approve each install/update/start/stop operation deliberately.

1. Before updating, require the existing installation to report version
   `0.2.2`. Create or identify a memory-bank sentinel and record the pg0
   `PG_VERSION`. Capture Supervisor's options as a secret-safe baseline: replace
   `openrouter_api_key` with only `<set>` or `<empty>`, canonicalize the resulting
   JSON, and record its SHA-256 plus the explicit non-secret option values. Do
   not print or attach the credential. Run the production-console update
   operation and update to the published `v0.3.0` app through Supervisor. Then
   require version `0.3.0`, state `started`, and `buildable: false`, and require
   the same redacted-options SHA-256/non-secret values. In a separate fresh-install
   check, require Supervisor to download `ghcr.io/bonzanni/hindsight:0.3.0`
   rather than start a local build.
2. Use the console's read-only SSH operation to inspect the running container:

   ```bash
   docker inspect --format '{{.AppArmorProfile}}' addon_5884eb17_hindsight
   ```

   Require exactly `5884eb17_hindsight`. Record the image ID/digest at the same
   time so the test is tied to the published artifact.
3. Find a process inside that container and send the harmless intra-profile
   `SIGCONT` through the console's exec operation. Require exit status `0`:

   ```bash
   kill -CONT 1
   ```

   `Operation not permitted` is a failed AppArmor gate.
4. Record a start timestamp, then submit the stop through the
   production-console/Supervisor stop operation. That command returns when the
   request is accepted, not when shutdown is complete: poll once per second
   until both Supervisor reports `stopped` and Docker reports
   `.State.Running=false`. Fail the gate if that state transition has not
   completed within 30 seconds. Only after both states agree, inspect the
   stopped container and require `.State.ExitCode` (container exit code) `0`,
   not `137`.
5. Start through Supervisor, then run the production-console smoke probes.
   Require API health and ingress success. Confirm the pre-update memory-bank
   sentinel still exists and that `/data/.pg0/instances/hindsight/data/PG_VERSION`
   matches the recorded value; together with the options comparison in step 1,
   this proves the `0.2.2` → `0.3.0` update preserved `/data` and Supervisor
   options.
6. Run the production-console AppArmor harvest operation for the acceptance
   window. Require no AppArmor denial related to signalling, s6 shutdown,
   Hindsight, or pg0. Attach the clean output (or explicit no-match result) to
   the release evidence.

## Exceptional compiled-profile cache recovery

Do not clear AppArmor caches during routine installs, and never add this to the
container startup. The cache belongs to HAOS/Supervisor, outside the app's
security boundary. If and only if the stored `apparmor.txt` contains
`signal (send,receive)` while the active profile still rejects step 3, collect
all reproducer evidence first and stop normal retry loops.

Recovery is executable only when Supervisor has a genuinely pending newer app
version: the update operation is what re-invokes `apparmor_parser`. If the
failure is discovered after `0.3.0` is already the latest version, do not imply
that a same-version update will work. Prepare and publish a subsequent patch
version, then stop Hindsight, remove only the compiled
`5884eb17_hindsight` entries below Supervisor's
`/data/apparmor/cache/<kernel-features>/`, and perform that pending Supervisor
update. Restart/reboot alone did not recompile the policy in the observed
failure. Never delete the cache tree wholesale, change another profile,
disable AppArmor, or grant host privileges.

See [`SUPERVISOR_APPARMOR_REPRODUCER.md`](SUPERVISOR_APPARMOR_REPRODUCER.md)
for the evidence bundle and upstream issue text.
