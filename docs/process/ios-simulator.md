# iOS simulator runbook — commands and cleanup

`AGENTS.md` → **iOS simulator** states the law: one designated simulator, one fleet-wide lock on every
simulator-backed `xcodebuild`, host package tests take no lock. This is how to run it.

The Mac is shared by every agent and by Rob. Two runs against one simulator collide in `testmanagerd` and app
install state, and a full disk kills CoreSimulator fleet-wide (incidents → *Disk exhaustion killed the
simulator fleet*).

---

## 1. The designated simulator

| Field | Value |
| --- | --- |
| Name | `agent-ios-tests` |
| Device type | `iPhone 17` |
| Runtime | `com.apple.CoreSimulator.SimRuntime.iOS-26-2` |
| UDID | `C4A64D49-24A2-4429-B6E2-AD9A14142A99` |

Recreate it if it is missing:

```bash
xcrun simctl create agent-ios-tests "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-26-2
```

Boot with `xcrun simctl bootstatus "$UDID" -b` — idempotent and blocking. **Do not use `simctl boot` in agent
scripts**; it returns before the device is usable.

The fleet lock is `/private/tmp/making-tracks-ios-tests.lock`. `flock` is at `/opt/homebrew/bin/flock`.
The retired lock path `/tmp/agent-ios-sim.lock` does **not** serialize fleet work; do not use it. If there is
any doubt about who holds the simulator, check the canonical lock directly before starting work:

```bash
lsof /private/tmp/making-tracks-ios-tests.lock
```

Add a second simulator only if lock waits become a *measured* bottleneck. One simulator plus `flock` is the
policy.

---

## 2. Which tests need the lock

Simulator-backed work uses the app project `ios/App/MakingTracks.xcodeproj`, scheme `MakingTracks`, run from
the repo root. Every `xcodebuild` invocation against it — **build or test** — takes the lock, because a
Release build contends for the same simulator, `testmanagerd` and derived-data state as a test run.

⚠️ **Run these from an `ios`-based branch.** `develop`'s `ios/` tree lags `ios`: its `project.yml` carries
neither warnings-as-errors nor the `MakingTracksTests` target. The commands below still *succeed* on a
`develop`-based worktree, but they build a weaker project — a Release build that cannot fail on warnings, and
a test run missing the app test target. A gate you believe you passed did not run. App work belongs on `ios`
anyway (`AGENTS.md` → **iOS branch**); this is what goes wrong if it isn't.

The `/ios` Swift package's host tests (`cd ios && swift test`) never touch CoreSimulator and must **not** take
the lock.

---

## 3. The test command

One destination, addressed by UDID, with parallel and concurrent-destination testing disabled:

```bash
flock /private/tmp/making-tracks-ios-tests.lock sh -ec '
  UDID=C4A64D49-24A2-4429-B6E2-AD9A14142A99
  xcrun simctl bootstatus "$UDID" -b
  xcodebuild \
    -project ios/App/MakingTracks.xcodeproj \
    -scheme MakingTracks \
    -destination "platform=iOS Simulator,id=$UDID" \
    -parallel-testing-enabled NO \
    -disable-concurrent-destination-testing \
    test
'
```

## 4. The Release-configuration build

Required once before any PR touching the iOS app target (`AGENTS.md` → **Review gates**):

```bash
flock /private/tmp/making-tracks-ios-tests.lock sh -ec '
  UDID=C4A64D49-24A2-4429-B6E2-AD9A14142A99
  xcrun simctl bootstatus "$UDID" -b
  xcodebuild build \
    -configuration Release \
    -project ios/App/MakingTracks.xcodeproj \
    -scheme MakingTracks \
    -destination "platform=iOS Simulator,id=$UDID"
'
```

---

## 5. Disk hygiene idiom

Derived data and result bundles are the biggest disk producers on this host. A stable derived-data path per
agent, and the result bundle deleted as soon as its counts are read:

```bash
DD=/private/tmp/dd-<agent-name>          # e.g. /private/tmp/dd-codex4 — stable, reused every run
RB=/private/tmp/<agent-name>.xcresult
rm -rf "$RB"
xcodebuild ... -derivedDataPath "$DD" -resultBundlePath "$RB" test
# ... extract pass/fail counts from "$RB" ...
rm -rf "$RB"
```

Per-run numbered or timestamped derived-data directories (`dd-1`, `dd-run-2`) accumulate without bound. One
reusable path lets each build overwrite the last.

---

## 6. Simulator clones

Parallel testing and multi-destination runs are the normal paths that spawn clones. The single-destination
command in §3 is the required defense. Leaked clones hide in XCTest's separate device set:

```bash
xcrun simctl --set testing list
```

---

## 7. Device poisoning

A simulator can become poisoned even when the app is correct. The known signature is:

- app or UI test failures report `Test crashed with signal kill`
- no fresh app `.ips` crash report appears under `~/Library/Logs/DiagnosticReports`
- simulator unified logs show `launchd_sim` / RunningBoard app exits as `SIGTERM(15)` sent by `xcodebuild`
- there is no jetsam, watchdog / `0x8BADF00D`, or app assertion/crash evidence
- the same clean-baseline test passes on a freshly-created simulator of the same device type/runtime

Do not bisect code until the environment axis is isolated. The discriminator is a same-baseline, same-test
run on a temporary fresh device:

```bash
flock /private/tmp/making-tracks-ios-tests.lock sh -ec '
  TMP_UDID=$(xcrun simctl create mt-poison-check "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-26-2)
  trap "xcrun simctl delete \"$TMP_UDID\"" EXIT
  xcrun simctl bootstatus "$TMP_UDID" -b
  xcodebuild \
    -project ios/App/MakingTracks.xcodeproj \
    -scheme MakingTracks \
    -destination "platform=iOS Simulator,id=$TMP_UDID" \
    -parallel-testing-enabled NO \
    -disable-concurrent-destination-testing \
    -only-testing:<target>/<suite>/<test> \
    test
'
```

If the temporary device passes and the designated device fails with the signature above, repair the designated
device under the same canonical lock:

```bash
flock /private/tmp/making-tracks-ios-tests.lock sh -ec '
  UDID=C4A64D49-24A2-4429-B6E2-AD9A14142A99
  xcrun simctl shutdown "$UDID" || true
  xcrun simctl erase "$UDID"
  xcrun simctl bootstatus "$UDID" -b
'
```

Then rerun the original repro on the designated device before releasing the lock or starting a full gate.
Heavy multi-suite days may warrant a scheduled single-device erase under the lock. Never erase by symptom
alone: collect the kill signature and run the fresh-device discriminator first.

---

## 8. Weekly cleanup

Takes the fleet lock, so cleanup cannot race an active run:

```bash
flock /private/tmp/making-tracks-ios-tests.lock sh -ec '
  xcrun simctl --set testing delete all
  xcrun simctl delete unavailable
  find ~/Library/Developer/Xcode/DerivedData -mindepth 1 -maxdepth 1 -type d -mtime +14 \
    \( -name "MakingTracks-*" -o -name "MakingTracksData-*" -o -name "agent-ios-tests-*" \) \
    -prune -print -exec rm -rf {} +
'
```

**Never put `simctl delete all` or `simctl shutdown all` in a shared script.** Unscoped, those destroy or
disrupt Rob's simulators and every other agent's. The `--set testing` scoping above is what makes the cleanup
safe.
