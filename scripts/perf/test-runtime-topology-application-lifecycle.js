#!/usr/bin/env node

const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fileSystem = require("node:fs");
const operatingSystem = require("node:os");
const path = require("node:path");

const lifecycle = require("./lib/runtime-topology-application-lifecycle.js");
const processCleanup = require(
  "./lib/runtime-topology-application-process-cleanup.js"
);

const lifecyclePath = path.join(
  __dirname,
  "lib/runtime-topology-application-lifecycle.js"
);
const processCleanupPath = path.join(
  __dirname,
  "lib/runtime-topology-application-process-cleanup.js"
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
const realProcessMaxLifetimeSeconds = 10;
const realProcessReadinessPollMilliseconds = 10;
const realProcessReadinessWatchdogMilliseconds = 2_000;

function applicationRecord(overrides = {}) {
  return {
    bundleIdentifier: "com.example.fixture",
    bundlePath: "/tmp/Fixture.app",
    executablePath: "/tmp/Fixture.app/Contents/MacOS/applet",
    launchDateSeconds: 807_000_000,
    processIdentifier: 42,
    processStartIdentity: "Fri Jul 31 22:00:00 2026",
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

function exactProcessEvidence(activeProcesses = [], readbackError = null) {
  return { activeProcesses, readbackError };
}

function testExactProcessClassification() {
  const expectedStartIdentity = "Fri Jul 31 22:00:00 2026";
  assert.equal(processCleanup.classifyExactProcessObservation(
    expectedStartIdentity,
    { present: false, readbackError: null, startIdentity: "", state: "" }
  ), "exited");
  assert.equal(processCleanup.classifyExactProcessObservation(
    expectedStartIdentity,
    {
      present: true,
      readbackError: null,
      startIdentity: expectedStartIdentity,
      state: "Z",
    }
  ), "exited");
  assert.equal(processCleanup.classifyExactProcessObservation(
    expectedStartIdentity,
    {
      present: true,
      readbackError: null,
      startIdentity: "Fri Jul 31 22:01:00 2026",
      state: "S",
    }
  ), "identity_changed");
  assert.equal(processCleanup.classifyExactProcessObservation(
    expectedStartIdentity,
    {
      present: true,
      readbackError: "synthetic ps failure",
      startIdentity: "",
      state: "",
    }
  ), "readback_error");
}

function testExactProcessInitialAndSlowSchedulingEvidence() {
  const observation = { cancelled: false };
  let clockCount = 0;
  let waitCount = 0;
  let evidence = processCleanup.waitForExactProcessExit(observation, {
    monotonicNow() {
      clockCount += 1;
      return 0;
    },
    readEvidence() {
      return exactProcessEvidence();
    },
    waitForNextReadback() {
      waitCount += 1;
    },
    watchdogSeconds: processCleanup.applicationProcessExitWatchdogSeconds,
  });
  assert.equal(processCleanup.exactProcessExitIsSatisfied(evidence), true);
  assert.equal(clockCount, 0);
  assert.equal(waitCount, 0);

  let active = true;
  let now = 8;
  evidence = processCleanup.waitForExactProcessExit(observation, {
    monotonicNow() {
      return now;
    },
    readEvidence() {
      return exactProcessEvidence(active ? [applicationRecord()] : []);
    },
    waitForNextReadback() {
      now = 800;
      active = false;
    },
    watchdogSeconds: processCleanup.applicationProcessExitWatchdogSeconds,
  });
  assert.equal(processCleanup.exactProcessExitIsSatisfied(evidence), true);
}

function testExactProcessWatchdogAndCancellation() {
  let clockCount = 0;
  assert.throws(
    () => processCleanup.waitForExactProcessExit(
      { cancelled: false },
      {
        monotonicNow() {
          clockCount += 1;
          return clockCount === 1 ? 3 : 5;
        },
        readEvidence() {
          return exactProcessEvidence([applicationRecord({ processIdentifier: 126 })]);
        },
        waitForNextReadback() {
        },
        watchdogSeconds: processCleanup.applicationProcessExitWatchdogSeconds,
      }
    ),
    (error) => {
      assert.match(error.message, /postRequestApplicationProcessesAbsent/);
      assert.match(error.message, /processIdentifier.*126/);
      return true;
    }
  );

  const cancelled = { cancelled: true };
  assert.throws(
    () => processCleanup.waitForExactProcessExit(cancelled, {
      monotonicNow() {
        throw new Error("cancelled process observation read the clock");
      },
      readEvidence() {
        throw new Error("cancelled process observation read process state");
      },
      waitForNextReadback() {
        throw new Error("cancelled process observation waited");
      },
      watchdogSeconds: processCleanup.applicationProcessExitWatchdogSeconds,
    }),
    /was cancelled/
  );
}

function testExactProcessWaitFailureCannotBeOverriddenByFinalReadback() {
  const waitFailure = new Error([
    "Timed out waiting for exact application processes to exit.",
    "unmetCondition=postRequestApplicationProcessesAbsent",
  ].join("\n"));
  assert.throws(
    () => processCleanup.requireExactProcessExit(
      waitFailure,
      exactProcessEvidence()
    ),
    /postRequestApplicationProcessesAbsent/
  );
  assert.throws(
    () => processCleanup.requireExactProcessExit(
      null,
      exactProcessEvidence([applicationRecord({ processIdentifier: 127 })])
    ),
    (error) => {
      assert.match(error.message, /postRequestApplicationProcessesAbsent/);
      assert.match(error.message, /processIdentifier.*127/);
      return true;
    }
  );
  assert.doesNotThrow(
    () => processCleanup.requireExactProcessExit(null, exactProcessEvidence())
  );
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
  assert.throws(
    () => lifecycle.requireApplicationExit(
      new Error("force watchdog expired"),
      applicationEvidence(),
      "identity=already-absent"
    ),
    /force watchdog expired/
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
  const lifecycleOutput = childProcess.execFileSync(
    "/usr/bin/osascript",
    ["-l", "JavaScript", lifecyclePath, ...arguments],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }
  ).trim();
  if (arguments[0] !== "terminate") {
    return lifecycleOutput;
  }
  const processOutput = childProcess.execFileSync(
    "/usr/bin/osascript",
    ["-l", "JavaScript", processCleanupPath, "cleanup", arguments[2]],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }
  ).trim();
  return [lifecycleOutput, processOutput].filter(Boolean).join("\n");
}

function exactProcessIsActive(record) {
  const result = childProcess.spawnSync(
    "/bin/ps",
    ["-p", String(record.processIdentifier), "-o", "state=,lstart="],
    { encoding: "utf8" }
  );
  if (result.status !== 0 || !result.stdout.trim()) {
    return false;
  }
  const fields = result.stdout.trim().replace(/\s+/g, " ").split(" ");
  return !fields[0].startsWith("Z")
    && fields.slice(1, 6).join(" ") === record.processStartIdentity;
}

function testRealExactProcessCleanupAfterApplicationAbsence() {
  const temporaryRoot = fileSystem.mkdtempSync(
    path.join(operatingSystem.tmpdir(), "flowtab-runtime-process-exit-")
  );
  const readyPath = path.join(temporaryRoot, "ready");
  const evidencePath = path.join(temporaryRoot, "evidence.json");
  let fixture = null;
  let fixtureRecord = null;
  try {
    fixture = childProcess.spawn(
      "/usr/bin/perl",
      [
        "-e",
        '$SIG{TERM}=sub{}; open(my $fh, ">", $ARGV[0]) or die $!; print $fh "ready\\n"; close($fh); sleep $ARGV[1]',
        readyPath,
        String(realProcessMaxLifetimeSeconds),
      ],
      { stdio: "ignore" }
    );
    const readinessDeadline = performance.now()
      + realProcessReadinessWatchdogMilliseconds;
    while (
      !fileSystem.existsSync(readyPath)
      && performance.now() < readinessDeadline
    ) {
      Atomics.wait(
        new Int32Array(new SharedArrayBuffer(4)),
        0,
        0,
        realProcessReadinessPollMilliseconds
      );
    }
    assert.equal(fileSystem.existsSync(readyPath), true);
    const startIdentity = childProcess.execFileSync(
      "/bin/ps",
      ["-p", String(fixture.pid), "-o", "lstart="],
      { encoding: "utf8" }
    ).trim().replace(/\s+/g, " ");
    fixtureRecord = applicationRecord({
      bundleIdentifier: "io.github.flowtab.process-fixture",
      bundlePath: path.join(temporaryRoot, "Process Fixture.app"),
      executablePath: "/usr/bin/perl",
      launchDateSeconds: 807_000_100,
      processIdentifier: fixture.pid,
      processStartIdentity: startIdentity,
    });
    fileSystem.writeFileSync(evidencePath, JSON.stringify({
      schemaVersion: 1,
      verdict: "absent",
      initialActiveApplications: [fixtureRecord],
    }));
    childProcess.execFileSync(
      "/usr/bin/osascript",
      ["-l", "JavaScript", processCleanupPath, "cleanup", evidencePath],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }
    );
    const evidence = JSON.parse(fileSystem.readFileSync(evidencePath, "utf8"));
    assert.equal(evidence.processVerdict, "absent");
    assert.equal(evidence.processObservationCancelled, true);
    assert.deepEqual(
      evidence.initialActiveProcesses.map(processCleanup.applicationIdentityKey),
      [processCleanup.applicationIdentityKey(fixtureRecord)]
    );
    assert.deepEqual(
      evidence.processForceRequests.map((request) => request.identity),
      [processCleanup.applicationIdentityKey(fixtureRecord)]
    );
    assert.ok(evidence.processForceRequests.every((request) => request.accepted));
    assert.deepEqual(evidence.finalActiveProcesses, []);
    assert.equal(exactProcessIsActive(fixtureRecord), false);
  } finally {
    if (fixtureRecord && exactProcessIsActive(fixtureRecord)) {
      try {
        process.kill(fixtureRecord.processIdentifier, "SIGKILL");
      } catch (_) {
      }
    }
    fileSystem.rmSync(temporaryRoot, { force: true, recursive: true });
  }
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
  let baselineCapturedRecord = null;
  let postRequestCapturedRecord = null;
  let fixtureProcessesCleaned = false;
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
    baselineCapturedRecord = JSON.parse(
      fileSystem.readFileSync(baselinePath, "utf8")
    ).capturedApplications[0];
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
    postRequestCapturedRecord = evidence.initialActiveApplications[0];
    assert.equal(evidence.verdict, "absent");
    assert.doesNotMatch(evidence.lastNotification, /readbackError/);
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
    assert.deepEqual(
      evidence.initialActiveApplications.map(lifecycle.applicationIdentityKey),
      [lifecycle.applicationIdentityKey(postRequestRecord)]
    );
    assert.deepEqual(evidence.finalActiveApplications, []);
    assert.equal(evidence.processVerdict, "absent");
    assert.equal(evidence.processObservationCancelled, true);
    assert.ok(evidence.initialActiveProcesses.length <= 1);
    assert.ok(evidence.processForceRequests.length <= 1);
    assert.ok(evidence.processForceRequests.every((request) => request.accepted));
    assert.deepEqual(evidence.finalActiveProcesses, []);
    assert.equal(exactProcessIsActive(postRequestCapturedRecord), false);
    assert.equal(exactProcessIsActive(baselineCapturedRecord), true);

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
    const cleanupEvidence = JSON.parse(
      fileSystem.readFileSync(cleanupEvidencePath, "utf8")
    );
    assert.equal(cleanupEvidence.verdict, "absent");
    assert.doesNotMatch(cleanupEvidence.lastNotification, /readbackError/);
    assert.equal(cleanupEvidence.processVerdict, "absent");
    assert.equal(exactProcessIsActive(baselineCapturedRecord), false);
    fixtureProcessesCleaned = true;
  } finally {
    if (!fixtureProcessesCleaned) {
      [baselineCapturedRecord, postRequestCapturedRecord]
        .filter(Boolean)
        .forEach((record) => {
          if (exactProcessIsActive(record)) {
            try {
              process.kill(record.processIdentifier, "SIGKILL");
            } catch (_) {
            }
          }
        });
    }
    fileSystem.rmSync(temporaryRoot, { force: true, recursive: true });
  }
}

function testRuntimeTopologyCallerContract() {
  const source = fileSystem.readFileSync(runnerPath, "utf8");
  const lifecycleSource = fileSystem.readFileSync(lifecyclePath, "utf8");
  const processCleanupSource = fileSystem.readFileSync(processCleanupPath, "utf8");
  const cleanupOwnerStart = source.indexOf("cleanup_independent_applications() {");
  const processCleanupOwnerStart = processCleanupSource.indexOf(
    "function cleanupExactApplicationProcesses"
  );
  const baselineIndex = source.lastIndexOf("if ! capture_application_baseline; then");
  const triggerIndex = source.lastIndexOf("run_ui_test &");
  assert.ok(baselineIndex >= 0 && baselineIndex < triggerIndex);
  assert.ok(source.includes("cleanup_independent_applications || true"));
  assert.ok(source.includes('"application_cleanup_exit_code"'));
  assert.ok(
    source.indexOf('"$APPLICATION_PROCESS_CLEANUP_TOOL"', cleanupOwnerStart)
      > source.indexOf('"$APPLICATION_LIFECYCLE_TOOL"', cleanupOwnerStart)
  );

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
  assert.ok(
    processCleanupSource.indexOf(
      "let processEvidence = readExactProcessEvidence(",
      processCleanupOwnerStart
    ) < processCleanupSource.indexOf(
      "evidence.processForceRequests = requestExactProcessExit(",
      processCleanupOwnerStart
    )
  );
}

testExactProcessClassification();
testExactProcessInitialAndSlowSchedulingEvidence();
testExactProcessWatchdogAndCancellation();
testExactProcessWaitFailureCannotBeOverriddenByFinalReadback();
testBaselineAndExactPathSelection();
testNotificationOrderingAndCancellation();
testImmediateAbsenceAvoidsClockAndWait();
testTerminationEventDrivesFinalReadback();
testSlowSchedulingCannotOverrideSatisfiedReadback();
testWatchdogAndReadbackDiagnostics();
testCancellationStopsObservation();
testWorkflowBundleIdentifierReadback();
testRealExactProcessCleanupAfterApplicationAbsence();
testRealPostBaselineTerminationPreservesBaselineIdentity();
testRuntimeTopologyCallerContract();

console.log(
  "Runtime-topology application lifecycle checks workspace and exact-process evidence, cancellation, and watchdog diagnostics."
);
