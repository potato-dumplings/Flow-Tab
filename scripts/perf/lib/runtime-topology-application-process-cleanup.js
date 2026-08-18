const applicationProcessExitWatchdogSeconds = 2;
const applicationProcessExitPollIntervalSeconds = 0.05;

function applicationIdentityKey(record) {
  return [
    record.bundleIdentifier,
    record.processIdentifier,
    record.launchDateSeconds,
    record.bundlePath,
    record.executablePath,
  ].join("|");
}

function classifyExactProcessObservation(expectedStartIdentity, observation) {
  if (observation.readbackError) {
    return "readback_error";
  }
  if (!observation.present || observation.state.startsWith("Z")) {
    return "exited";
  }
  if (observation.startIdentity !== expectedStartIdentity) {
    return "identity_changed";
  }
  return "running";
}

function exactProcessExitIsSatisfied(evidence) {
  return !evidence.readbackError && evidence.activeProcesses.length === 0;
}

function formatExactProcessExitEvidence(evidence) {
  if (evidence.readbackError) {
    return `readbackError=${evidence.readbackError}`;
  }
  return `activeProcesses=${JSON.stringify(evidence.activeProcesses)}`;
}

function requireExactProcessExit(waitFailure, evidence) {
  if (waitFailure) {
    throw waitFailure;
  }
  if (!exactProcessExitIsSatisfied(evidence)) {
    throw new Error([
      "Independent application process cleanup did not reach exact absence.",
      "unmetCondition=postRequestApplicationProcessesAbsent",
      `lastObservation=${formatExactProcessExitEvidence(evidence)}`,
    ].join("\n"));
  }
}

function waitForExactProcessExit(observation, dependencies) {
  if (observation.cancelled) {
    throw new Error("Exact-process observation was cancelled.");
  }
  let lastEvidence = dependencies.readEvidence();
  if (exactProcessExitIsSatisfied(lastEvidence)) {
    return lastEvidence;
  }

  const deadline = dependencies.monotonicNow() + dependencies.watchdogSeconds;
  while (true) {
    dependencies.waitForNextReadback();
    if (observation.cancelled) {
      throw new Error("Exact-process observation was cancelled.");
    }
    lastEvidence = dependencies.readEvidence();
    if (exactProcessExitIsSatisfied(lastEvidence)) {
      return lastEvidence;
    }
    if (dependencies.monotonicNow() >= deadline) {
      throw new Error([
        "Timed out waiting for exact application processes to exit.",
        "unmetCondition=postRequestApplicationProcessesAbsent",
        `watchdogSeconds=${dependencies.watchdogSeconds}`,
        `lastObservation=${formatExactProcessExitEvidence(lastEvidence)}`,
      ].join("\n"));
    }
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    applicationIdentityKey,
    applicationProcessExitPollIntervalSeconds,
    applicationProcessExitWatchdogSeconds,
    classifyExactProcessObservation,
    exactProcessExitIsSatisfied,
    formatExactProcessExitEvidence,
    requireExactProcessExit,
    waitForExactProcessExit,
  };
}

if (typeof ObjC !== "undefined") {
  ObjC.import("Foundation");
}

function runTool(executablePath, arguments) {
  const task = $.NSTask.alloc.init;
  const outputPipe = $.NSPipe.pipe;
  task.executableURL = $.NSURL.fileURLWithPath(executablePath);
  task.arguments = arguments;
  task.standardOutput = outputPipe;
  task.standardError = outputPipe;
  const error = $();
  if (!task.launchAndReturnError(error)) {
    throw new Error(
      `Unable to launch ${executablePath}: ${error.localizedDescription.js}`
    );
  }
  task.waitUntilExit;
  const data = outputPipe.fileHandleForReading.readDataToEndOfFile;
  const value = $.NSString.alloc.initWithDataEncoding(
    data,
    $.NSUTF8StringEncoding
  );
  return {
    output: value.isNil() ? "" : String(ObjC.unwrap(value)),
    status: Number(task.terminationStatus),
  };
}

function exactProcessReadback(processIdentifier, expectedStartIdentity) {
  const result = runTool("/bin/ps", [
    "-p",
    String(processIdentifier),
    "-o",
    "pid=,ppid=,state=,lstart=,command=",
  ]);
  const output = result.output.trim().replace(/\s+/g, " ");
  if (result.status !== 0 || output === "") {
    const existence = runTool("/bin/kill", ["-0", String(processIdentifier)]);
    if (existence.status === 0) {
      return {
        condition: "readback_error",
        record: `pid=${processIdentifier} readbackError=ps status=${result.status}`,
        startIdentity: "",
      };
    }
    return {
      condition: "exited",
      record: `pid=${processIdentifier} state=absent`,
      startIdentity: "",
    };
  }

  const fields = output.split(" ");
  if (fields.length < 9 || Number(fields[0]) !== Number(processIdentifier)) {
    return {
      condition: "readback_error",
      record: `pid=${processIdentifier} readbackError=unexpectedRecord output=${output}`,
      startIdentity: "",
    };
  }
  const state = fields[2];
  const startIdentity = fields.slice(3, 8).join(" ");
  const condition = classifyExactProcessObservation(expectedStartIdentity, {
    present: true,
    readbackError: null,
    startIdentity,
    state,
  });
  return { condition, record: output, startIdentity };
}

function readExactProcessEvidence(records) {
  const activeProcesses = [];
  const observations = [];
  const readbackErrors = [];
  records.forEach((record) => {
    if (!record.processStartIdentity) {
      readbackErrors.push(
        `pid=${record.processIdentifier} readbackError=missingExpectedStartIdentity`
      );
      return;
    }
    const observation = exactProcessReadback(
      record.processIdentifier,
      record.processStartIdentity
    );
    observations.push({
      identity: applicationIdentityKey(record),
      ...observation,
    });
    if (observation.condition === "readback_error") {
      readbackErrors.push(observation.record);
    } else if (observation.condition === "running") {
      activeProcesses.push({
        ...record,
        processRecord: observation.record,
      });
    }
  });
  return {
    activeProcesses,
    observations,
    readbackError: readbackErrors.length > 0 ? readbackErrors.join("; ") : null,
  };
}

function requestExactProcessExit(records) {
  const outcomes = [];
  records.forEach((record) => {
    const observation = exactProcessReadback(
      record.processIdentifier,
      record.processStartIdentity
    );
    if (observation.condition !== "running") {
      return;
    }
    const result = runTool("/bin/kill", ["-KILL", String(record.processIdentifier)]);
    outcomes.push({
      accepted: result.status === 0,
      identity: applicationIdentityKey(record),
      processIdentifier: record.processIdentifier,
      processStartIdentity: record.processStartIdentity,
    });
  });
  return outcomes;
}

function readText(path) {
  const error = $();
  const value = $.NSString.stringWithContentsOfFileEncodingError(
    path,
    $.NSUTF8StringEncoding,
    error
  );
  if (value.isNil()) {
    throw new Error(`Unable to read ${path}: ${error.localizedDescription.js}`);
  }
  return ObjC.unwrap(value);
}

function writeJSON(path, payload) {
  const error = $();
  const value = $.NSString.stringWithString(
    `${JSON.stringify(payload, null, 2)}\n`
  );
  if (!value.writeToFileAtomicallyEncodingError(
    path,
    true,
    $.NSUTF8StringEncoding,
    error
  )) {
    throw new Error(`Unable to write ${path}: ${error.localizedDescription.js}`);
  }
}

function monotonicUptime() {
  return Number($.NSProcessInfo.processInfo.systemUptime);
}

function waitForProcessReadbackCadence() {
  $.NSRunLoop.currentRunLoop.runModeBeforeDate(
    $.NSDefaultRunLoopMode,
    $.NSDate.dateWithTimeIntervalSinceNow(
      applicationProcessExitPollIntervalSeconds
    )
  );
}

function cleanupExactApplicationProcesses(evidencePath) {
  const evidence = JSON.parse(readText(evidencePath));
  if (evidence.schemaVersion !== 1 || evidence.verdict !== "absent") {
    throw new Error("Application lifecycle evidence is not ready for process cleanup.");
  }
  if (!Array.isArray(evidence.initialActiveApplications)) {
    throw new Error("Application lifecycle evidence lacks initial identities.");
  }
  const observation = { cancelled: false };
  let failure = null;
  try {
    let processWaitFailure = null;
    let processEvidence = readExactProcessEvidence(
      evidence.initialActiveApplications
    );
    evidence.initialActiveProcesses = processEvidence.activeProcesses;
    evidence.initialProcessObservations = processEvidence.observations;
    evidence.processForceRequests = requestExactProcessExit(
      processEvidence.activeProcesses
    );
    try {
      waitForExactProcessExit(observation, {
        monotonicNow: monotonicUptime,
        readEvidence: () => readExactProcessEvidence(
          evidence.initialActiveApplications
        ),
        waitForNextReadback: waitForProcessReadbackCadence,
        watchdogSeconds: applicationProcessExitWatchdogSeconds,
      });
    } catch (error) {
      processWaitFailure = error;
      evidence.processWaitError = String(error.message || error);
    }
    processEvidence = readExactProcessEvidence(
      evidence.initialActiveApplications
    );
    evidence.finalActiveProcesses = processEvidence.activeProcesses;
    evidence.finalProcessObservations = processEvidence.observations;
    evidence.finalProcessReadbackError = processEvidence.readbackError;
    requireExactProcessExit(processWaitFailure, processEvidence);
    evidence.processVerdict = "absent";
  } catch (error) {
    failure = error;
    evidence.verdict = "failed";
    evidence.processVerdict = "failed";
    evidence.processError = String(error.message || error);
  } finally {
    observation.cancelled = true;
    evidence.processObservationCancelled = observation.cancelled;
    writeJSON(evidencePath, evidence);
  }
  if (failure) {
    throw failure;
  }
  return "Independent application process cleanup reached exact absence.";
}

function run(arguments) {
  if (arguments.length !== 2 || arguments[0] !== "cleanup") {
    throw new Error("Expected cleanup and one application evidence path.");
  }
  return cleanupExactApplicationProcesses(arguments[1]);
}
