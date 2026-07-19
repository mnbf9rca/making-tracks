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

## 7. Weekly cleanup

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
