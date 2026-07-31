#!/usr/bin/env node

const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fileSystem = require("node:fs");
const operatingSystem = require("node:os");
const path = require("node:path");

const lifecycle = require("./lib/runtime-topology-application-lifecycle.js");

const lifecyclePath = path.join(
  __dirname,
  "lib/runtime-topology-application-lifecycle.js"
);
const evidenceToolPath = path.join(
  __dirname,
  "lib/runtime-topology-evidence.py"
);
const workspaceProbePath = path.join(
  __dirname,
  "test-runtime-topology-application-workspace.jxa"
);
const runnerPath = path.join(__dirname, "runtime-topology-pressure.sh");
const realFixtureQuitDelaySeconds = 10;

function applicationRecord(overrides = {}) {
  return {
    bundleIdentifier: "com.example.fixture",
    bundlePath: "/tmp/Fixture.app",
    executablePath: "/tmp/Fixture.app/Contents/MacOS/applet",
    launchDateSeconds: 807_000_000,
    processIdentifier: 42,
    ...overrides,
  };
}

function expectedApplication(overrides = {}) {
  return {
    bundleIdentifier: "com.example.fixture",
    bundlePath: "/tmp/Fixture.app",
    ...overrides,
  };
}

function makeObservation() {
  const state = lifecycle.makeApplicationExitObservationState(
    [],
    [expectedApplication()]
  );
  return {
    state,
    cancel() {
      state.cancelled = true;
    },
  };
}

function applicationEvidence(activeApplications = [], readbackError = null) {
  return { activeApplications, readbackError };
}

function testBaselineAndExactPathSelection() {
  const baseline = applicationRecord();
  const postRequest = applicationRecord({
    launchDateSeconds: baseline.launchDateSeconds + 1,
    processIdentifier: 84,
  });
  const records = [
    baseline,
    postRequest,
    postRequest,
    applicationRecord({
      bundleIdentifier: "com.example.other",
      processIdentifier: 126,
    }),
    applicationRecord({
      bundlePath: "/tmp/Other.app",
      processIdentifier: 168,
    }),
  ];
  assert.deepEqual(
    lifecycle.selectPostBaselineApplications(
      records,
      [baseline],
      [expectedApplication()]
    ),
    [postRequest]
  );
}

function testNotificationOrderingAndCancellation() {
  const baseline = applicationRecord();
  const target = applicationRecord({
    launchDateSeconds: baseline.launchDateSeconds + 1,
    processIdentifier: 84,
  });
  const state = lifecycle.makeApplicationExitObservationState(
    [baseline],
    [expectedApplication()]
  );
  assert.equal(lifecycle.recordApplicationTermination(state, baseline), false);
  assert.equal(
    lifecycle.recordApplicationTermination(
      state,
      applicationRecord({ bundlePath: "/tmp/Other.app" })
    ),
    false
  );
  assert.equal(lifecycle.recordApplicationTermination(state, target), true);
  assert.equal(lifecycle.recordApplicationTermination(state, target), false);
  assert.equal(state.generation, 1);
  state.cancelled = true;
  assert.equal(
    lifecycle.recordApplicationTermination(
      state,
      applicationRecord({ processIdentifier: 126 })
    ),
    false
  );
}

function testImmediateAbsenceAvoidsClockAndWait() {
  const observation = makeObservation();
  let clockCount = 0;
  let waitCount = 0;
  const evidence = lifecycle.waitForApplicationExit(observation, {
    monotonicNow() {
      clockCount += 1;
      return 0;
    },
    readEvidence() {
      return applicationEvidence();
    },
    waitForChange() {
      waitCount += 1;
    },
    watchdogSeconds: lifecycle.applicationTerminationGraceSeconds,
  });
  assert.equal(lifecycle.applicationExitIsSatisfied(evidence), true);
  assert.equal(clockCount, 0);
  assert.equal(waitCount, 0);
}

function testTerminationEventDrivesFinalReadback() {
  const observation = makeObservation();
  let active = true;
  const target = applicationRecord();
  const evidence = lifecycle.waitForApplicationExit(observation, {
    monotonicNow() {
      return 4;
    },
    readEvidence() {
      return applicationEvidence(active ? [target] : []);
    },
    waitForChange() {
      assert.equal(
        lifecycle.recordApplicationTermination(observation.state, target),
        true
      );
      active = false;
    },
    watchdogSeconds: lifecycle.applicationTerminationGraceSeconds,
  });
  assert.equal(lifecycle.applicationExitIsSatisfied(evidence), true);
  assert.equal(observation.state.generation, 1);
}

function testSlowSchedulingCannotOverrideSatisfiedReadback() {
  const observation = makeObservation();
  let active = true;
  let now = 8;
  const evidence = lifecycle.waitForApplicationExit(observation, {
    monotonicNow() {
      return now;
    },
    readEvidence() {
      return applicationEvidence(active ? [applicationRecord()] : []);
    },
    waitForChange() {
      now = 800;
      active = false;
    },
    watchdogSeconds: lifecycle.applicationTerminationGraceSeconds,
  });
  assert.equal(lifecycle.applicationExitIsSatisfied(evidence), true);
}

function testWatchdogAndReadbackDiagnostics() {
  const observation = makeObservation();
  let clockCount = 0;
  assert.throws(
    () => lifecycle.waitForApplicationExit(observation, {
      monotonicNow() {
        clockCount += 1;
        return clockCount === 1 ? 3 : 5;
      },
      readEvidence() {
        return applicationEvidence([applicationRecord({ processIdentifier: 126 })]);
      },
      waitForChange() {
      },
      watchdogSeconds: lifecycle.applicationTerminationGraceSeconds,
    }),
    (error) => {
      assert.match(error.message, /postRequestApplicationsAbsent/);
      assert.match(error.message, /processIdentifier.*126/);
      assert.match(error.message, /lastNotification=none/);
      return true;
    }
  );

  clockCount = 0;
  assert.throws(
    () => lifecycle.waitForApplicationExit(makeObservation(), {
      monotonicNow() {
        clockCount += 1;
        return clockCount === 1 ? 10 : 12;
      },
      readEvidence() {
        return applicationEvidence([], "synthetic workspace failure");
      },
      waitForChange() {
      },
      watchdogSeconds: lifecycle.applicationTerminationGraceSeconds,
    }),
    /readbackError=synthetic workspace failure/
  );
}

function testCancellationStopsObservation() {
  const observation = makeObservation();
  observation.cancel();
  assert.throws(
    () => lifecycle.waitForApplicationExit(observation, {
      monotonicNow() {
        throw new Error("cancelled observation must not read clock");
      },
      readEvidence() {
        throw new Error("cancelled observation must not read applications");
      },
      waitForChange() {
        throw new Error("cancelled observation must not wait");
      },
      watchdogSeconds: lifecycle.applicationTerminationGraceSeconds,
    }),
    /was cancelled/
  );
}

function testWorkflowBundleIdentifierReadback() {
  const temporaryRoot = fileSystem.mkdtempSync(
    path.join(operatingSystem.tmpdir(), "flowtab-workflow-identities-")
  );
  const firstPath = path.join(temporaryRoot, "first.json");
  const secondPath = path.join(temporaryRoot, "second.json");
  try {
    fileSystem.writeFileSync(firstPath, JSON.stringify({
      apps: [
        { bundleId: "com.example.zeta" },
        { bundleId: "com.example.alpha" },
      ],
    }));
    fileSystem.writeFileSync(secondPath, JSON.stringify({
      apps: [
        { bundleId: "com.example.alpha" },
        { bundleId: "com.example.beta" },
      ],
    }));
    const output = childProcess.execFileSync(
      "/usr/bin/python3",
      [evidenceToolPath, "workflow-bundle-identifiers", firstPath, secondPath],
      { encoding: "utf8" }
    );
    assert.deepEqual(output.trim().split("\n"), [
      "com.example.alpha",
      "com.example.beta",
      "com.example.zeta",
    ]);
  } finally {
    fileSystem.rmSync(temporaryRoot, { force: true, recursive: true });
  }
}

function runWorkspaceProbe(operation, value) {
  const output = childProcess.execFileSync(
    "/usr/bin/osascript",
    ["-l", "JavaScript", workspaceProbePath, operation, value],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }
  ).trim();
  return output;
}

function runLifecycleTool(arguments) {
  return childProcess.execFileSync(
    "/usr/bin/osascript",
    ["-l", "JavaScript", lifecyclePath, ...arguments],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }
  ).trim();
}

function testRealPostBaselineTerminationPreservesBaselineIdentity() {
  const temporaryRoot = fileSystem.mkdtempSync(
    path.join(operatingSystem.tmpdir(), "flowtab-runtime-app-exit-")
  );
  const fixturePath = path.join(temporaryRoot, "Lifecycle Fixture.app");
  const baselinePath = path.join(temporaryRoot, "baseline.json");
  const evidencePath = path.join(temporaryRoot, "evidence.json");
  const cleanupBaselinePath = path.join(temporaryRoot, "cleanup-baseline.json");
  const cleanupEvidencePath = path.join(temporaryRoot, "cleanup-evidence.json");
  const bundleIdentifier = `io.github.flowtab.lifecycle-fixture.p${process.pid}`;
  try {
    childProcess.execFileSync(
      "/usr/bin/osacompile",
      [
        "-l",
        "AppleScript",
        "-s",
        "-e",
        "on run",
        "-e",
        "end run",
        "-e",
        "on idle",
        "-e",
        "return 1",
        "-e",
        "end idle",
        "-e",
        "on quit",
        "-e",
        `delay ${realFixtureQuitDelaySeconds}`,
        "-e",
        "continue quit",
        "-e",
        "end quit",
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
        bundleIdentifier,
        path.join(fixturePath, "Contents", "Info.plist"),
      ],
      { stdio: "pipe" }
    );
    childProcess.execFileSync(
      "/usr/bin/codesign",
      ["--force", "--sign", "-", fixturePath],
      { stdio: "pipe" }
    );

    const baselineRecord = JSON.parse(runWorkspaceProbe("launch", fixturePath));
    runLifecycleTool(["capture", baselinePath, bundleIdentifier]);
    const postRequestRecord = JSON.parse(runWorkspaceProbe("launch", fixturePath));
    assert.notEqual(
      lifecycle.applicationIdentityKey(baselineRecord),
      lifecycle.applicationIdentityKey(postRequestRecord)
    );

    runLifecycleTool([
      "terminate",
      baselinePath,
      evidencePath,
      bundleIdentifier,
      fixturePath,
    ]);
    const evidence = JSON.parse(fileSystem.readFileSync(evidencePath, "utf8"));
    assert.equal(evidence.verdict, "absent");
    assert.equal(evidence.baselineIdentityCount, 1);
    assert.equal(evidence.observerCancelled, true);
    assert.deepEqual(
      evidence.gracefulRequests.map((request) => request.identity),
      [lifecycle.applicationIdentityKey(postRequestRecord)]
    );
    assert.match(evidence.gracefulWaitError, /postRequestApplicationsAbsent/);
    assert.deepEqual(
      evidence.forceRequests.map((request) => request.identity),
      [lifecycle.applicationIdentityKey(postRequestRecord)]
    );
    assert.ok(evidence.notificationGeneration >= 1);
    assert.deepEqual(
      evidence.initialActiveApplications.map(lifecycle.applicationIdentityKey),
      [lifecycle.applicationIdentityKey(postRequestRecord)]
    );
    assert.deepEqual(evidence.finalActiveApplications, []);

    const activeRecords = JSON.parse(
      runWorkspaceProbe("active", bundleIdentifier)
    );
    assert.ok(
      activeRecords.some(
        (record) => lifecycle.applicationIdentityKey(record)
          === lifecycle.applicationIdentityKey(baselineRecord)
      )
    );
    assert.equal(
      activeRecords.some(
        (record) => lifecycle.applicationIdentityKey(record)
          === lifecycle.applicationIdentityKey(postRequestRecord)
      ),
      false
    );
  } finally {
    try {
      fileSystem.writeFileSync(cleanupBaselinePath, JSON.stringify({
        schemaVersion: 1,
        bundleIdentifiers: [bundleIdentifier],
        capturedApplications: [],
      }));
      runLifecycleTool([
        "terminate",
        cleanupBaselinePath,
        cleanupEvidencePath,
        bundleIdentifier,
        fixturePath,
      ]);
    } catch (_) {
      try {
        runWorkspaceProbe("force-all", bundleIdentifier);
      } catch (_) {
      }
    }
    fileSystem.rmSync(temporaryRoot, { force: true, recursive: true });
  }
}

function testRuntimeTopologyCallerContract() {
  const source = fileSystem.readFileSync(runnerPath, "utf8");
  const lifecycleSource = fileSystem.readFileSync(lifecyclePath, "utf8");
  const baselineIndex = source.lastIndexOf("if ! capture_application_baseline; then");
  const triggerIndex = source.lastIndexOf("run_ui_test &");
  assert.ok(baselineIndex >= 0 && baselineIndex < triggerIndex);
  assert.ok(source.includes("cleanup_independent_applications || true"));
  assert.ok(source.includes('"application_cleanup_exit_code"'));

  const observationStart = lifecycleSource.indexOf(
    "function startApplicationExitObservation"
  );
  const observerRegistration = lifecycleSource.indexOf(
    "notificationCenter.addObserverSelectorNameObject",
    observationStart
  );
  const initialReadback = lifecycleSource.indexOf(
    "observation.initialEvidence = readPostBaselineEvidence",
    observationStart
  );
  assert.ok(
    observationStart >= 0
      && observerRegistration > observationStart
      && initialReadback > observerRegistration
  );
}

testBaselineAndExactPathSelection();
testNotificationOrderingAndCancellation();
testImmediateAbsenceAvoidsClockAndWait();
testTerminationEventDrivesFinalReadback();
testSlowSchedulingCannotOverrideSatisfiedReadback();
testWatchdogAndReadbackDiagnostics();
testCancellationStopsObservation();
testWorkflowBundleIdentifierReadback();
testRealPostBaselineTerminationPreservesBaselineIdentity();
testRuntimeTopologyCallerContract();

console.log(
  "Runtime-topology application lifecycle checks baseline identity, workspace events, exact readback, cancellation, and watchdog evidence."
);
