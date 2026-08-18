const appDisplayName = "Flow Tab";
const appProcessName = "FlowTab";
const appBundleName = "Flow Tab.app";
const appInstallPath = `/Applications/${appBundleName}`;
const bundleID = "io.github.potato-dumplings.flowtab";
const applicationExitWatchdogSeconds = 10;
const workspaceObserverClassName = "FlowTabUninstallWorkspaceObserver";

let activeApplicationExitObservation = null;

function normalizedDirectoryPath(value, label) {
  const path = String(value || "").replace(/\/+$/, "");
  if (!path.startsWith("/")) {
    throw new Error(`${label} must be an absolute path.`);
  }
  return path || "/";
}

function appendPathComponent(directory, component) {
  return directory === "/" ? `/${component}` : `${directory}/${component}`;
}

function makeCleanupPaths({ userHomeDirectory, applicationSupportDirectory }) {
  const home = normalizedDirectoryPath(userHomeDirectory, "User home directory");
  const applicationSupport = normalizedDirectoryPath(
    applicationSupportDirectory,
    "User Application Support directory"
  );
  const flowTabSupportDirectory = appendPathComponent(applicationSupport, "FlowTab");
  const logsDirectory = appendPathComponent(flowTabSupportDirectory, "logs");

  if (!logsDirectory.startsWith(`${applicationSupport}/`)) {
    throw new Error("FlowTab logs must resolve within the user Application Support directory.");
  }

  return {
    preferencesFile: appendPathComponent(
      appendPathComponent(home, "Library/Preferences"),
      `${bundleID}.plist`
    ),
    logsDirectory,
  };
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\"'\"'`)}'`;
}

function makeLogsCleanupCommand(cleanupPaths) {
  return `/bin/rm -rf ${shellQuote(cleanupPaths.logsDirectory)}`;
}

function makeUserDataCleanupCommand(cleanupPaths) {
  return [
    `/usr/bin/defaults delete ${shellQuote(bundleID)} >/dev/null 2>&1 || true`,
    `/bin/rm -f ${shellQuote(cleanupPaths.preferencesFile)}`,
    makeLogsCleanupCommand(cleanupPaths),
  ].join("; ");
}

function makeProcessAbsenceGuardCommand(processName) {
  const quotedProcessName = shellQuote(processName);
  return [
    `process_name=${quotedProcessName}`,
    'if process_ids=$(/usr/bin/pgrep -x "${process_name}" 2>&1); then',
    '  echo "Installed app removal requires process absence." >&2',
    '  echo "unmetCondition=processAbsent processName=${process_name}" >&2',
    '  echo "processIdentifiers=${process_ids}" >&2',
    '  for process_id in ${process_ids}; do',
    '    /bin/ps -p "${process_id}" -o pid=,ppid=,state=,lstart=,command= >&2',
    "  done",
    "  exit 1",
    "else",
    "  process_status=$?",
    '  if [ "${process_status}" -ne 1 ]; then',
    '    echo "Process absence readback failed." >&2',
    '    echo "unmetCondition=processAbsent processName=${process_name}" >&2',
    '    echo "readbackError=pgrep status=${process_status} output=${process_ids}" >&2',
    "    exit 1",
    "  fi",
    "fi",
  ].join("\n");
}

function makeApplicationExitObservationState(applicationBundleID) {
  return {
    bundleIdentifier: applicationBundleID,
    cancelled: false,
    generation: 0,
    lastNotification: "none",
    observedProcessIdentities: Object.create(null),
  };
}

function recordApplicationTermination(state, record) {
  if (
    state.cancelled
    || record.bundleIdentifier !== state.bundleIdentifier
  ) {
    return false;
  }

  const processIdentity = [
    record.processIdentifier,
    record.launchDate,
    record.executablePath,
  ].join("|");
  if (state.observedProcessIdentities[processIdentity]) {
    return false;
  }

  state.observedProcessIdentities[processIdentity] = true;
  state.generation += 1;
  state.lastNotification = [
    `bundleIdentifier=${record.bundleIdentifier}`,
    `pid=${record.processIdentifier}`,
    `launchDate=${record.launchDate}`,
    `executable=${record.executablePath}`,
  ].join(" ");
  return true;
}

function applicationExitIsSatisfied(evidence) {
  return !evidence.readbackError && evidence.activeApplications.length === 0;
}

function formatApplicationExitEvidence(evidence) {
  if (evidence.readbackError) {
    return `readbackError=${evidence.readbackError}`;
  }
  if (evidence.activeApplications.length === 0) {
    return "activeApplications=[]";
  }
  return `activeApplications=[${evidence.activeApplications.join(" | ")}]`;
}

function waitForApplicationExit(observation, dependencies) {
  if (observation.state.cancelled) {
    throw new Error("Application-exit observation was cancelled.");
  }

  let lastEvidence = dependencies.readEvidence();
  if (applicationExitIsSatisfied(lastEvidence)) {
    return lastEvidence;
  }

  const startedAt = dependencies.monotonicNow();
  const deadline = startedAt + dependencies.watchdogSeconds;

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
        "Timed out waiting for application process absence.",
        `unmetCondition=applicationAbsent bundleIdentifier=${observation.state.bundleIdentifier}`,
        `watchdogSeconds=${dependencies.watchdogSeconds}`,
        `lastObservation=${formatApplicationExitEvidence(lastEvidence)}`,
        `lastNotification=${observation.state.lastNotification}`,
      ].join("\n"));
    }
  }
}

function withApplicationExitObservation(startObservation, triggerExit, waitForExit) {
  const observation = startObservation();
  try {
    triggerExit();
    return waitForExit(observation);
  } finally {
    observation.cancel();
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    applicationExitWatchdogSeconds,
    applicationExitIsSatisfied,
    formatApplicationExitEvidence,
    makeCleanupPaths,
    makeApplicationExitObservationState,
    makeLogsCleanupCommand,
    makeProcessAbsenceGuardCommand,
    makeUserDataCleanupCommand,
    recordApplicationTermination,
    waitForApplicationExit,
    withApplicationExitObservation,
  };
}

if (typeof ObjC !== "undefined") {
  ObjC.import("AppKit");
  ObjC.import("CoreFoundation");
}

function unwrapObjectiveCValue(value, fallback) {
  if (!value || (typeof value.isNil === "function" && value.isNil())) {
    return fallback;
  }
  const unwrapped = ObjC.unwrap(value);
  return unwrapped === null || unwrapped === undefined
    ? fallback
    : String(unwrapped);
}

function runningApplicationRecord(application) {
  return {
    bundleIdentifier: unwrapObjectiveCValue(application.bundleIdentifier, "<unknown>"),
    executablePath: unwrapObjectiveCValue(application.executableURL.path, "<unknown>"),
    launchDate: unwrapObjectiveCValue(application.launchDate.description, "<unknown>"),
    processIdentifier: Number(application.processIdentifier),
    terminated: Boolean(application.terminated),
  };
}

function formatRunningApplicationRecord(record) {
  return [
    `bundleIdentifier=${record.bundleIdentifier}`,
    `pid=${record.processIdentifier}`,
    `terminated=${record.terminated}`,
    `launchDate=${record.launchDate}`,
    `executable=${record.executablePath}`,
  ].join(" ");
}

function readRunningApplicationEvidence(applicationBundleID) {
  try {
    const applications = $.NSRunningApplication
      .runningApplicationsWithBundleIdentifier(applicationBundleID);
    const activeApplications = [];
    for (let index = 0; index < Number(applications.count); index += 1) {
      const record = runningApplicationRecord(applications.objectAtIndex(index));
      if (!record.terminated) {
        activeApplications.push(formatRunningApplicationRecord(record));
      }
    }
    return {
      activeApplications,
      readbackError: null,
    };
  } catch (error) {
    return {
      activeApplications: [],
      readbackError: String(error.message || error),
    };
  }
}

function recordWorkspaceTerminationNotification(notification) {
  const state = activeApplicationExitObservation;
  if (!state || state.cancelled) {
    return;
  }

  try {
    const application = notification.userInfo.objectForKey(
      $.NSWorkspaceApplicationKey
    );
    if (application.isNil()) {
      return;
    }
    if (recordApplicationTermination(
      state,
      runningApplicationRecord(application)
    )) {
      const runLoop = $.CFRunLoopGetMain();
      $.CFRunLoopStop(runLoop);
      $.CFRunLoopWakeUp(runLoop);
    }
  } catch (error) {
    state.lastNotification = `readbackError=${String(error.message || error)}`;
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

function startWorkspaceApplicationExitObservation(applicationBundleID) {
  if (activeApplicationExitObservation) {
    throw new Error("An application-exit observation is already active.");
  }

  ensureWorkspaceObserverClass();
  const state = makeApplicationExitObservationState(applicationBundleID);
  const observer = $[workspaceObserverClassName].alloc.init;
  const notificationCenter = $.NSWorkspace.sharedWorkspace.notificationCenter;
  notificationCenter.addObserverSelectorNameObject(
    observer,
    $.NSSelectorFromString("workspaceDidTerminateApplication:"),
    $.NSWorkspaceDidTerminateApplicationNotification,
    $()
  );
  activeApplicationExitObservation = state;

  let cancelled = false;
  return {
    initialEvidence: readRunningApplicationEvidence(applicationBundleID),
    state,
    cancel() {
      if (cancelled) {
        return;
      }
      cancelled = true;
      state.cancelled = true;
      notificationCenter.removeObserver(observer);
      if (activeApplicationExitObservation === state) {
        activeApplicationExitObservation = null;
      }
    },
  };
}

function monotonicUptime() {
  return Number($.NSProcessInfo.processInfo.systemUptime);
}

function waitForWorkspaceTerminationChange(observation, deadline) {
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

function waitForWorkspaceApplicationExit(observation) {
  return waitForApplicationExit(observation, {
    monotonicNow: monotonicUptime,
    readEvidence: () => readRunningApplicationEvidence(
      observation.state.bundleIdentifier
    ),
    waitForChange: waitForWorkspaceTerminationChange,
    watchdogSeconds: applicationExitWatchdogSeconds,
  });
}

function requestFlowTabExit(app) {
  try {
    const flowTab = Application(appDisplayName);
    if (flowTab.running()) {
      flowTab.quit();
    }
  } catch (_) {
  }

  try {
    app.doShellScript(
      `/usr/bin/pkill -x ${shellQuote(appProcessName)} >/dev/null 2>&1 || true`
    );
  } catch (_) {
  }
}

function resolvedUserApplicationSupportDirectory() {
  const urls = $.NSFileManager.defaultManager.URLsForDirectoryInDomains(
    $.NSApplicationSupportDirectory,
    $.NSUserDomainMask
  );
  const url = urls.firstObject;
  if (!url) {
    throw new Error("Unable to resolve the user Application Support directory.");
  }
  return ObjC.unwrap(url.standardizedURL.path);
}

function isChineseLocale() {
  const localeIdentifier = ObjC.unwrap($.NSLocale.currentLocale.localeIdentifier);
  return localeIdentifier.startsWith("zh");
}

function localizedText(chineseText, englishText) {
  return isChineseLocale() ? chineseText : englishText;
}

function shellFlag(app, testCommand) {
  return app.doShellScript(`${testCommand} && printf 1 || printf 0`) === "1";
}

function run() {
  const app = Application.currentApplication();
  app.includeStandardAdditions = true;

  const cleanupPaths = makeCleanupPaths({
    userHomeDirectory: ObjC.unwrap($.NSHomeDirectory()),
    applicationSupportDirectory: resolvedUserApplicationSupportDirectory(),
  });

  const dialogTitle = localizedText("卸载 Flow Tab", "Uninstall Flow Tab");
  const cancelButtonText = localizedText("取消", "Cancel");
  const confirmButtonText = localizedText("卸载", "Uninstall");
  const completionButtonText = localizedText("完成", "Done");
  const confirmMessage = localizedText(
    "这会退出 Flow Tab，并从“应用程序”中删除它，同时重置辅助功能、屏幕录制权限记录并清理本地偏好设置与日志。是否继续？",
    "This will quit Flow Tab, remove it from Applications, reset Accessibility and Screen Recording permissions, and clear local preferences and logs. Continue?"
  );
  const successDetails = localizedText(
    "已重置辅助功能和屏幕录制权限记录，并清理本地偏好设置与日志（如果存在）。",
    "Accessibility and Screen Recording permissions were reset, and local preferences and logs were cleared if present."
  );
  const missingAppDetails = localizedText(
    "/Applications 中没有找到 Flow Tab.app，但其余清理步骤已经完成。",
    "No Flow Tab.app was found in /Applications, but the remaining cleanup steps still completed."
  );

  const appWasInstalled = shellFlag(app, `/bin/test -d ${shellQuote(appInstallPath)}`);

  try {
    app.displayDialog(confirmMessage, {
      withTitle: dialogTitle,
      buttons: [cancelButtonText, confirmButtonText],
      defaultButton: confirmButtonText,
      cancelButton: cancelButtonText,
      withIcon: "caution",
    });
  } catch (error) {
    if (error.errorNumber === -128) {
      $.exit(0);
    }
    throw error;
  }

  try {
    withApplicationExitObservation(
      () => startWorkspaceApplicationExitObservation(bundleID),
      () => requestFlowTabExit(app),
      (observation) => {
        waitForWorkspaceApplicationExit(observation);
        app.doShellScript(makeUserDataCleanupCommand(cleanupPaths));

        const privilegedCleanupCommand = [
          makeProcessAbsenceGuardCommand(appProcessName),
          `/bin/rm -rf ${shellQuote(appInstallPath)}`,
          `/usr/bin/tccutil reset Accessibility ${shellQuote(bundleID)} >/dev/null 2>&1 || true`,
          `/usr/bin/tccutil reset ScreenCapture ${shellQuote(bundleID)} >/dev/null 2>&1 || true`,
        ].join("\n");
        app.doShellScript(privilegedCleanupCommand, {
          administratorPrivileges: true,
        });
      }
    );
  } catch (error) {
    if (error.errorNumber === -128) {
      $.exit(0);
    }

    app.displayDialog(`${localizedText("卸载失败：", "Uninstall failed: ")}${error.message}`, {
      withTitle: dialogTitle,
      buttons: [completionButtonText],
      defaultButton: completionButtonText,
      withIcon: "caution",
    });
    $.exit(1);
  }

  let completionMessage = successDetails;
  if (!appWasInstalled) {
    completionMessage = `${missingAppDetails}\n\n${successDetails}`;
  }

  app.displayDialog(completionMessage, {
    withTitle: dialogTitle,
    buttons: [completionButtonText],
    defaultButton: completionButtonText,
  });
}
