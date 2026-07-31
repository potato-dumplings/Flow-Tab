const applicationTerminationGraceSeconds = 2;
const applicationForceTerminationWatchdogSeconds = 2;
const workspaceObserverClassName = "FlowTabRuntimeTopologyWorkspaceObserver";

let activeApplicationExitObservation = null;

function applicationIdentityKey(record) {
  return [
    record.bundleIdentifier,
    record.processIdentifier,
    record.launchDateSeconds,
    record.bundlePath,
    record.executablePath,
  ].join("|");
}

function expectedApplicationKey(application) {
  return [application.bundleIdentifier, application.bundlePath].join("|");
}

function deduplicateApplicationRecords(records) {
  const seen = Object.create(null);
  return records.filter((record) => {
    const key = applicationIdentityKey(record);
    if (seen[key]) {
      return false;
    }
    seen[key] = true;
    return true;
  });
}

function deduplicateExpectedApplications(applications) {
  const seen = Object.create(null);
  return applications.filter((application) => {
    const key = expectedApplicationKey(application);
    if (seen[key]) {
      return false;
    }
    seen[key] = true;
    return true;
  });
}

function makeApplicationExitObservationState(baselineRecords, expectedApplications) {
  const baselineIdentities = Object.create(null);
  const expectedIdentities = Object.create(null);
  baselineRecords.forEach((record) => {
    baselineIdentities[applicationIdentityKey(record)] = true;
  });
  expectedApplications.forEach((application) => {
    expectedIdentities[expectedApplicationKey(application)] = true;
  });
  return {
    baselineIdentities,
    cancelled: false,
    expectedIdentities,
    generation: 0,
    lastNotification: "none",
    observedNotifications: Object.create(null),
  };
}

function recordMatchesObservation(state, record) {
  return Boolean(
    state.expectedIdentities[
      expectedApplicationKey({
        bundleIdentifier: record.bundleIdentifier,
        bundlePath: record.bundlePath,
      })
    ]
  ) && !state.baselineIdentities[applicationIdentityKey(record)];
}

function selectPostBaselineApplications(records, baselineRecords, expectedApplications) {
  const state = makeApplicationExitObservationState(
    baselineRecords,
    expectedApplications
  );
  return deduplicateApplicationRecords(
    records.filter((record) => recordMatchesObservation(state, record))
  );
}

function recordApplicationTermination(state, record) {
  if (state.cancelled || !recordMatchesObservation(state, record)) {
    return false;
  }
  const key = applicationIdentityKey(record);
  if (state.observedNotifications[key]) {
    return false;
  }
  state.observedNotifications[key] = true;
  state.generation += 1;
  state.lastNotification = `identity=${key}`;
  return true;
}

function applicationExitIsSatisfied(evidence) {
  return !evidence.readbackError && evidence.activeApplications.length === 0;
}

function formatApplicationExitEvidence(evidence) {
  if (evidence.readbackError) {
    return `readbackError=${evidence.readbackError}`;
  }
  return `activeApplications=${JSON.stringify(evidence.activeApplications)}`;
}

function waitForApplicationExit(observation, dependencies) {
  if (observation.state.cancelled) {
    throw new Error("Application-exit observation was cancelled.");
  }
  let lastEvidence = dependencies.readEvidence();
  if (applicationExitIsSatisfied(lastEvidence)) {
    return lastEvidence;
  }

  const deadline = dependencies.monotonicNow() + dependencies.watchdogSeconds;
  while (true) {
    dependencies.waitForChange(observation, deadline);
    if (observation.state.cancelled) {
      throw new Error("Application-exit observation was cancelled.");
    }
    lastEvidence = dependencies.readEvidence();
    if (applicationExitIsSatisfied(lastEvidence)) {
      return lastEvidence;
    }
    if (dependencies.monotonicNow() >= deadline) {
      throw new Error([
        "Timed out waiting for exact application identities to exit.",
        "unmetCondition=postRequestApplicationsAbsent",
        `watchdogSeconds=${dependencies.watchdogSeconds}`,
        `lastObservation=${formatApplicationExitEvidence(lastEvidence)}`,
        `lastNotification=${observation.state.lastNotification}`,
      ].join("\n"));
    }
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    applicationForceTerminationWatchdogSeconds,
    applicationIdentityKey,
    applicationTerminationGraceSeconds,
    applicationExitIsSatisfied,
    deduplicateApplicationRecords,
    deduplicateExpectedApplications,
    formatApplicationExitEvidence,
    makeApplicationExitObservationState,
    recordApplicationTermination,
    selectPostBaselineApplications,
    waitForApplicationExit,
  };
}

if (typeof ObjC !== "undefined") {
  ObjC.import("AppKit");
  ObjC.import("CoreFoundation");
  ObjC.import("Foundation");
}

function objectiveCString(value, label) {
  if (!value || (typeof value.isNil === "function" && value.isNil())) {
    throw new Error(`Missing ${label} for running application.`);
  }
  const unwrapped = ObjC.unwrap(value);
  if (unwrapped === null || unwrapped === undefined || String(unwrapped) === "") {
    throw new Error(`Missing ${label} for running application.`);
  }
  return String(unwrapped);
}

function standardizedPath(path) {
  const resolvedURL = $.NSURL.fileURLWithPath(String(path))
    .standardizedURL
    .URLByResolvingSymlinksInPath;
  return objectiveCString(
    resolvedURL.path,
    "standardized path"
  );
}

function runningApplicationRecord(application) {
  const launchDate = application.launchDate;
  if (!launchDate || launchDate.isNil()) {
    throw new Error("Missing launch date for running application.");
  }
  return {
    bundleIdentifier: objectiveCString(
      application.bundleIdentifier,
      "bundle identifier"
    ),
    bundlePath: standardizedPath(
      objectiveCString(application.bundleURL.path, "bundle path")
    ),
    executablePath: standardizedPath(
      objectiveCString(application.executableURL.path, "executable path")
    ),
    launchDateSeconds: Number(launchDate.timeIntervalSinceReferenceDate),
    processIdentifier: Number(application.processIdentifier),
  };
}

function runningApplicationEntries(bundleIdentifiers) {
  const entries = [];
  const seen = Object.create(null);
  bundleIdentifiers.forEach((bundleIdentifier) => {
    const applications = $.NSRunningApplication
      .runningApplicationsWithBundleIdentifier(bundleIdentifier);
    for (let index = 0; index < Number(applications.count); index += 1) {
      const application = applications.objectAtIndex(index);
      if (Boolean(application.terminated)) {
        continue;
      }
      const record = runningApplicationRecord(application);
      const key = applicationIdentityKey(record);
      if (!seen[key]) {
        seen[key] = true;
        entries.push({ application, record });
      }
    }
  });
  return entries;
}

function readApplicationEvidence(bundleIdentifiers) {
  try {
    return {
      activeApplications: runningApplicationEntries(bundleIdentifiers)
        .map((entry) => entry.record),
      readbackError: null,
    };
  } catch (error) {
    return {
      activeApplications: [],
      readbackError: String(error.message || error),
    };
  }
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

function readJSON(path) {
  return JSON.parse(readText(path));
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

function uniqueBundleIdentifiers(expectedApplications) {
  const seen = Object.create(null);
  return expectedApplications
    .map((application) => application.bundleIdentifier)
    .filter((bundleIdentifier) => {
      if (seen[bundleIdentifier]) {
        return false;
      }
      seen[bundleIdentifier] = true;
      return true;
    });
}

function expectedApplicationsFromResolvedWorkflows(
  targetBundleIdentifier,
  targetBundlePath,
  workflowPaths
) {
  const applications = [{
    bundleIdentifier: targetBundleIdentifier,
    bundlePath: standardizedPath(targetBundlePath),
  }];
  workflowPaths.forEach((workflowPath) => {
    if (!$.NSFileManager.defaultManager.fileExistsAtPath(workflowPath)) {
      return;
    }
    const workflow = readJSON(workflowPath);
    if (!Array.isArray(workflow.apps)) {
      throw new Error(`Resolved workflow has no apps array: ${workflowPath}`);
    }
    workflow.apps.forEach((application) => {
      if (!application.bundleId || !application.appPath) {
        throw new Error(`Resolved workflow app lacks identity: ${workflowPath}`);
      }
      applications.push({
        bundleIdentifier: String(application.bundleId),
        bundlePath: standardizedPath(application.appPath),
      });
    });
  });
  return deduplicateExpectedApplications(applications);
}

function readPostBaselineEvidence(state, expectedApplications) {
  const evidence = readApplicationEvidence(
    uniqueBundleIdentifiers(expectedApplications)
  );
  if (evidence.readbackError) {
    return evidence;
  }
  return {
    activeApplications: evidence.activeApplications.filter(
      (record) => recordMatchesObservation(state, record)
    ),
    readbackError: null,
  };
}

function recordWorkspaceTerminationNotification(notification) {
  const observation = activeApplicationExitObservation;
  if (!observation || observation.state.cancelled) {
    return;
  }
  try {
    const application = notification.userInfo.objectForKey(
      $.NSWorkspaceApplicationKey
    );
    if (!application.isNil() && recordApplicationTermination(
      observation.state,
      runningApplicationRecord(application)
    )) {
      $.CFRunLoopStop($.CFRunLoopGetMain());
      $.CFRunLoopWakeUp($.CFRunLoopGetMain());
    }
  } catch (error) {
    observation.state.lastNotification =
      `readbackError=${String(error.message || error)}`;
  }
}

function ensureWorkspaceObserverClass() {
  if (typeof $[workspaceObserverClassName] !== "undefined") {
    return;
  }
  ObjC.registerSubclass({
    name: workspaceObserverClassName,
    superclass: "NSObject",
    methods: {
      "workspaceDidTerminateApplication:": {
        types: ["void", ["id"]],
        implementation: recordWorkspaceTerminationNotification,
      },
    },
  });
}

function startApplicationExitObservation(baselineRecords, expectedApplications) {
  if (activeApplicationExitObservation) {
    throw new Error("An application-exit observation is already active.");
  }
  ensureWorkspaceObserverClass();
  const state = makeApplicationExitObservationState(
    baselineRecords,
    expectedApplications
  );
  const observer = $[workspaceObserverClassName].alloc.init;
  const notificationCenter = $.NSWorkspace.sharedWorkspace.notificationCenter;
  notificationCenter.addObserverSelectorNameObject(
    observer,
    $.NSSelectorFromString("workspaceDidTerminateApplication:"),
    $.NSWorkspaceDidTerminateApplicationNotification,
    $()
  );
  const observation = {
    state,
    cancel() {
      if (state.cancelled) {
        return;
      }
      state.cancelled = true;
      notificationCenter.removeObserver(observer);
      if (activeApplicationExitObservation === observation) {
        activeApplicationExitObservation = null;
      }
    },
  };
  activeApplicationExitObservation = observation;
  observation.initialEvidence = readPostBaselineEvidence(
    state,
    expectedApplications
  );
  return observation;
}

function monotonicUptime() {
  return Number($.NSProcessInfo.processInfo.systemUptime);
}

function waitForWorkspaceChange(observation, deadline) {
  const baselineGeneration = observation.state.generation;
  while (
    !observation.state.cancelled
    && observation.state.generation === baselineGeneration
  ) {
    const remaining = deadline - monotonicUptime();
    if (remaining <= 0) {
      return;
    }
    $.NSRunLoop.currentRunLoop.runModeBeforeDate(
      $.NSDefaultRunLoopMode,
      $.NSDate.dateWithTimeIntervalSinceNow(remaining)
    );
  }
}

function requestApplicationExit(records, force) {
  const requested = Object.create(null);
  records.forEach((record) => {
    requested[applicationIdentityKey(record)] = true;
  });
  const outcomes = [];
  const entries = runningApplicationEntries(
    records.map((record) => record.bundleIdentifier)
  );
  entries.forEach((entry) => {
    const key = applicationIdentityKey(entry.record);
    if (!requested[key]) {
      return;
    }
    const accepted = force
      ? Boolean(entry.application.forceTerminate)
      : Boolean(entry.application.terminate);
    outcomes.push({ accepted, force, identity: key });
  });
  return outcomes;
}

function captureBaseline(outputPath, bundleIdentifiers) {
  const evidence = readApplicationEvidence(bundleIdentifiers);
  if (evidence.readbackError) {
    throw new Error(`Application baseline readback failed: ${evidence.readbackError}`);
  }
  writeJSON(outputPath, {
    schemaVersion: 1,
    bundleIdentifiers,
    capturedApplications: evidence.activeApplications,
  });
  return `Captured ${evidence.activeApplications.length} application baseline identities.`;
}

function terminatePostRequestApplications(
  baselinePath,
  evidencePath,
  targetBundleIdentifier,
  targetBundlePath,
  workflowPaths
) {
  const baseline = readJSON(baselinePath);
  if (baseline.schemaVersion !== 1 || !Array.isArray(baseline.capturedApplications)) {
    throw new Error("Application baseline has an unsupported schema.");
  }
  const expectedApplications = expectedApplicationsFromResolvedWorkflows(
    targetBundleIdentifier,
    targetBundlePath,
    workflowPaths
  );
  const evidence = {
    schemaVersion: 1,
    verdict: "failed",
    baselineIdentityCount: baseline.capturedApplications.length,
    expectedApplications,
    initialActiveApplications: [],
    gracefulRequests: [],
    gracefulWaitError: null,
    forceRequests: [],
    forceWaitError: null,
    finalActiveApplications: [],
    finalReadbackError: null,
    notificationGeneration: 0,
    lastNotification: "none",
    observerCancelled: false,
  };
  let observation = null;
  let failure = null;
  try {
    observation = startApplicationExitObservation(
      baseline.capturedApplications,
      expectedApplications
    );
    evidence.initialActiveApplications =
      observation.initialEvidence.activeApplications;
    if (observation.initialEvidence.readbackError) {
      throw new Error(
        `Initial application readback failed: ${observation.initialEvidence.readbackError}`
      );
    }
    evidence.gracefulRequests = requestApplicationExit(
      observation.initialEvidence.activeApplications,
      false
    );
    try {
      waitForApplicationExit(observation, {
        monotonicNow: monotonicUptime,
        readEvidence: () => readPostBaselineEvidence(
          observation.state,
          expectedApplications
        ),
        waitForChange: waitForWorkspaceChange,
        watchdogSeconds: applicationTerminationGraceSeconds,
      });
    } catch (error) {
      evidence.gracefulWaitError = String(error.message || error);
    }

    let finalEvidence = readPostBaselineEvidence(
      observation.state,
      expectedApplications
    );
    if (!applicationExitIsSatisfied(finalEvidence)) {
      evidence.forceRequests = requestApplicationExit(
        finalEvidence.activeApplications,
        true
      );
      try {
        waitForApplicationExit(observation, {
          monotonicNow: monotonicUptime,
          readEvidence: () => readPostBaselineEvidence(
            observation.state,
            expectedApplications
          ),
          waitForChange: waitForWorkspaceChange,
          watchdogSeconds: applicationForceTerminationWatchdogSeconds,
        });
      } catch (error) {
        evidence.forceWaitError = String(error.message || error);
      }
      finalEvidence = readPostBaselineEvidence(
        observation.state,
        expectedApplications
      );
    }
    evidence.finalActiveApplications = finalEvidence.activeApplications;
    evidence.finalReadbackError = finalEvidence.readbackError;
    if (!applicationExitIsSatisfied(finalEvidence)) {
      throw new Error([
        "Independent application cleanup did not reach exact absence.",
        "unmetCondition=postRequestApplicationsAbsent",
        `lastObservation=${formatApplicationExitEvidence(finalEvidence)}`,
        `lastNotification=${observation.state.lastNotification}`,
      ].join("\n"));
    }
    evidence.verdict = "absent";
  } catch (error) {
    failure = error;
    evidence.error = String(error.message || error);
  } finally {
    if (observation) {
      evidence.notificationGeneration = observation.state.generation;
      evidence.lastNotification = observation.state.lastNotification;
      observation.cancel();
      evidence.observerCancelled = observation.state.cancelled;
    }
    writeJSON(evidencePath, evidence);
  }
  if (failure) {
    throw failure;
  }
  return `Independent application cleanup reached exact absence.`;
}

function run(arguments) {
  if (arguments.length < 3) {
    throw new Error("Expected capture or terminate lifecycle arguments.");
  }
  const operation = arguments[0];
  if (operation === "capture") {
    return captureBaseline(arguments[1], arguments.slice(2));
  }
  if (operation === "terminate") {
    if (arguments.length < 5) {
      throw new Error("Terminate requires baseline, evidence, target bundle, and target path.");
    }
    return terminatePostRequestApplications(
      arguments[1],
      arguments[2],
      arguments[3],
      arguments[4],
      arguments.slice(5)
    );
  }
  throw new Error(`Unknown lifecycle operation: ${operation}`);
}
