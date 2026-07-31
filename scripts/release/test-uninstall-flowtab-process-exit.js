#!/usr/bin/env node

const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fileSystem = require("node:fs");
const operatingSystem = require("node:os");
const path = require("node:path");

const uninstaller = require("./uninstall-flowtab.js");
const applicationExitWatchdogSeconds =
  uninstaller.applicationExitWatchdogSeconds;

function makeObservation(bundleIdentifier = "io.github.potato-dumplings.flowtab") {
  return {
    state: uninstaller.makeApplicationExitObservationState(bundleIdentifier),
    cancel() {
      this.state.cancelled = true;
    },
  };
}

function processEvidence(activeApplications = [], readbackError = null) {
  return { activeApplications, readbackError };
}

function testImmediateAbsenceAvoidsClockAndWait() {
  const observation = makeObservation();
  let clockCount = 0;
  let waitCount = 0;

  const evidence = uninstaller.waitForApplicationExit(observation, {
    monotonicNow() {
      clockCount += 1;
      return 0;
    },
    readEvidence() {
      return processEvidence();
    },
    waitForChange() {
      waitCount += 1;
    },
    watchdogSeconds: applicationExitWatchdogSeconds,
  });

  assert.equal(uninstaller.applicationExitIsSatisfied(evidence), true);
  assert.equal(clockCount, 0);
  assert.equal(waitCount, 0);
}

function testTerminationEventDrivesFinalReadback() {
  const observation = makeObservation();
  let processIsPresent = true;
  const deadlines = [];

  const evidence = uninstaller.waitForApplicationExit(observation, {
    monotonicNow() {
      return 4;
    },
    readEvidence() {
      return processEvidence(processIsPresent ? ["pid=42"] : []);
    },
    waitForChange(_, deadline) {
      deadlines.push(deadline);
      processIsPresent = false;
      uninstaller.recordApplicationTermination(observation.state, {
        bundleIdentifier: observation.state.bundleIdentifier,
        executablePath: "/Applications/Flow Tab.app/Contents/MacOS/FlowTab",
        launchDate: "2026-07-31T20:00:00Z",
        processIdentifier: 42,
      });
    },
    watchdogSeconds: applicationExitWatchdogSeconds,
  });

  assert.equal(uninstaller.applicationExitIsSatisfied(evidence), true);
  assert.deepEqual(deadlines, [4 + applicationExitWatchdogSeconds]);
  assert.equal(observation.state.generation, 1);
}

function testSlowSchedulingCannotOverrideSatisfiedReadback() {
  const observation = makeObservation();
  let processIsPresent = true;
  let now = 8;

  const evidence = uninstaller.waitForApplicationExit(observation, {
    monotonicNow() {
      return now;
    },
    readEvidence() {
      return processEvidence(processIsPresent ? ["pid=84"] : []);
    },
    waitForChange() {
      now = 800;
      processIsPresent = false;
    },
    watchdogSeconds: applicationExitWatchdogSeconds,
  });

  assert.equal(uninstaller.applicationExitIsSatisfied(evidence), true);
}

function testWatchdogReportsLastEvidence() {
  const observation = makeObservation();
  let clockCount = 0;

  assert.throws(
    () => uninstaller.waitForApplicationExit(observation, {
      monotonicNow() {
        clockCount += 1;
        return clockCount === 1
          ? 3
          : 3 + applicationExitWatchdogSeconds;
      },
      readEvidence() {
        return processEvidence([
          "bundleIdentifier=io.github.potato-dumplings.flowtab pid=126",
        ]);
      },
      waitForChange() {
      },
      watchdogSeconds: applicationExitWatchdogSeconds,
    }),
    (error) => {
      assert.match(error.message, /unmetCondition=applicationAbsent/);
      assert.match(error.message, /watchdogSeconds=10/);
      assert.match(error.message, /pid=126/);
      assert.match(error.message, /lastNotification=none/);
      return true;
    }
  );
}

function testReadbackErrorCannotEstablishAbsence() {
  const observation = makeObservation();
  let clockCount = 0;

  assert.throws(
    () => uninstaller.waitForApplicationExit(observation, {
      monotonicNow() {
        clockCount += 1;
        return clockCount === 1
          ? 20
          : 20 + applicationExitWatchdogSeconds;
      },
      readEvidence() {
        return processEvidence([], "synthetic workspace failure");
      },
      waitForChange() {
      },
      watchdogSeconds: applicationExitWatchdogSeconds,
    }),
    /lastObservation=readbackError=synthetic workspace failure/
  );
}

function testCancellationAndNotificationOrdering() {
  const state = uninstaller.makeApplicationExitObservationState(
    "io.github.potato-dumplings.flowtab"
  );
  const targetRecord = {
    bundleIdentifier: state.bundleIdentifier,
    executablePath: "/Applications/Flow Tab.app/Contents/MacOS/FlowTab",
    launchDate: "2026-07-31T20:00:00Z",
    processIdentifier: 168,
  };

  assert.equal(
    uninstaller.recordApplicationTermination(state, {
      ...targetRecord,
      bundleIdentifier: "com.example.other",
    }),
    false
  );
  assert.equal(uninstaller.recordApplicationTermination(state, targetRecord), true);
  assert.equal(uninstaller.recordApplicationTermination(state, targetRecord), false);
  assert.equal(
    uninstaller.recordApplicationTermination(state, {
      ...targetRecord,
      launchDate: "2026-07-31T20:01:00Z",
    }),
    true
  );
  assert.equal(state.generation, 2);

  state.cancelled = true;
  assert.equal(
    uninstaller.recordApplicationTermination(state, {
      ...targetRecord,
      processIdentifier: 210,
    }),
    false
  );
  assert.throws(
    () => uninstaller.waitForApplicationExit(
      { state },
      {
        monotonicNow() {
          throw new Error("cancelled wait must not read the clock");
        },
        readEvidence() {
          throw new Error("cancelled wait must not read process state");
        },
        waitForChange() {
          throw new Error("cancelled wait must not start");
        },
        watchdogSeconds: applicationExitWatchdogSeconds,
      }
    ),
    /was cancelled/
  );
}

function testObservationOwnsTriggerAndCleanup() {
  const successOrder = [];
  const successObservation = makeObservation();
  successObservation.cancel = () => {
    successOrder.push("cancel");
    successObservation.state.cancelled = true;
  };

  uninstaller.withApplicationExitObservation(
    () => {
      successOrder.push("observe");
      return successObservation;
    },
    () => successOrder.push("trigger"),
    () => successOrder.push("wait")
  );
  assert.deepEqual(successOrder, ["observe", "trigger", "wait", "cancel"]);

  const failureOrder = [];
  const failureObservation = makeObservation();
  failureObservation.cancel = () => failureOrder.push("cancel");
  assert.throws(
    () => uninstaller.withApplicationExitObservation(
      () => {
        failureOrder.push("observe");
        return failureObservation;
      },
      () => failureOrder.push("trigger"),
      () => {
        failureOrder.push("wait");
        throw new Error("synthetic wait failure");
      }
    ),
    /synthetic wait failure/
  );
  assert.deepEqual(failureOrder, ["observe", "trigger", "wait", "cancel"]);
}

function testPrivilegedRemovalGuardRequiresFreshAbsence() {
  const absentProcessName = `FlowTabAbsent${process.pid}`;
  childProcess.execFileSync(
    "/bin/sh",
    ["-c", uninstaller.makeProcessAbsenceGuardCommand(absentProcessName)],
    { stdio: "pipe" }
  );

  const currentProcessName = "Finder";
  const currentProcessIdentifiers = childProcess.execFileSync(
    "/usr/bin/pgrep",
    ["-x", currentProcessName],
    { encoding: "utf8" }
  ).trim().split(/\s+/);
  assert.ok(currentProcessIdentifiers.length > 0);
  const guarded = childProcess.spawnSync(
    "/bin/sh",
    ["-c", uninstaller.makeProcessAbsenceGuardCommand(currentProcessName)],
    { encoding: "utf8" }
  );
  assert.equal(guarded.status, 1);
  assert.match(guarded.stderr, /unmetCondition=processAbsent/);
  assert.match(guarded.stderr, new RegExp(`processName=${currentProcessName}`));
  assert.match(
    guarded.stderr,
    new RegExp(`\\b${currentProcessIdentifiers[0]}\\b`)
  );

  const source = fileSystem.readFileSync(
    path.join(__dirname, "uninstall-flowtab.js"),
    "utf8"
  );
  const guardIndex = source.lastIndexOf(
    "makeProcessAbsenceGuardCommand(appProcessName)"
  );
  const removalIndex = source.lastIndexOf(
    "`/bin/rm -rf ${shellQuote(appInstallPath)}`"
  );
  assert.ok(guardIndex >= 0 && guardIndex < removalIndex);
  assert.equal(source.includes("delay(1)"), false);
}

function cleanupFixtureProcess(bundleIdentifier) {
  const script = [
    'ObjC.import("AppKit")',
    `var apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier("${bundleIdentifier}")`,
    "for (var index = 0; index < Number(apps.count); index += 1) {",
    "  apps.objectAtIndex(index).forceTerminate",
    "}",
    "true",
  ].join("; ");
  childProcess.spawnSync("/usr/bin/osascript", ["-l", "JavaScript", "-e", script]);
}

function testRealWorkspaceTerminationObservation() {
  const temporaryRoot = fileSystem.mkdtempSync(
    path.join(operatingSystem.tmpdir(), "flowtab-uninstaller-exit-")
  );
  const fixturePath = path.join(temporaryRoot, "FlowTab Exit Fixture.app");
  const compiledUninstallerPath = path.join(
    temporaryRoot,
    "Uninstall Flow Tab.app"
  );
  const fixtureBundleIdentifier = `io.github.flowtab.exit-fixture.p${process.pid}`;
  const uninstallerPath = path.join(__dirname, "uninstall-flowtab.js");
  const observerProbePath = path.join(
    __dirname,
    "test-uninstall-flowtab-workspace-observer.jxa"
  );

  try {
    childProcess.execFileSync(
      "/usr/bin/osacompile",
      [
        "-l",
        "JavaScript",
        "-s",
        "-e",
        "function run() {}",
        "-o",
        fixturePath,
      ],
      { stdio: "pipe" }
    );
    childProcess.execFileSync(
      "/usr/bin/plutil",
      [
        "-replace",
        "CFBundleIdentifier",
        "-string",
        fixtureBundleIdentifier,
        path.join(fixturePath, "Contents", "Info.plist"),
      ],
      { stdio: "pipe" }
    );
    childProcess.execFileSync(
      "/usr/bin/codesign",
      ["--force", "--sign", "-", fixturePath],
      { stdio: "pipe" }
    );
    childProcess.execFileSync(
      "/usr/bin/osacompile",
      ["-l", "JavaScript", "-o", compiledUninstallerPath, uninstallerPath],
      { stdio: "pipe" }
    );

    const output = childProcess.execFileSync(
      "/usr/bin/osascript",
      [
        "-l",
        "JavaScript",
        observerProbePath,
        uninstallerPath,
        fixturePath,
        fixtureBundleIdentifier,
      ],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }
    );
    assert.match(output, /observed exact workspace termination/);
  } finally {
    cleanupFixtureProcess(fixtureBundleIdentifier);
    fileSystem.rmSync(temporaryRoot, { force: true, recursive: true });
  }
}

testImmediateAbsenceAvoidsClockAndWait();
testTerminationEventDrivesFinalReadback();
testSlowSchedulingCannotOverrideSatisfiedReadback();
testWatchdogReportsLastEvidence();
testReadbackErrorCannotEstablishAbsence();
testCancellationAndNotificationOrdering();
testObservationOwnsTriggerAndCleanup();
testPrivilegedRemovalGuardRequiresFreshAbsence();
testRealWorkspaceTerminationObservation();

console.log(
  "Uninstaller process-exit checks use exact readback, workspace events, cancellation, and watchdog evidence."
);
