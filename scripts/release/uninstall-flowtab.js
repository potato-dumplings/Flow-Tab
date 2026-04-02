ObjC.import("Foundation");

const app = Application.currentApplication();
app.includeStandardAdditions = true;

const appDisplayName = "Flow Tab";
const appProcessName = "FlowTab";
const appBundleName = "Flow Tab.app";
const appInstallPath = `/Applications/${appBundleName}`;
const bundleID = "io.github.potato-dumplings.flowtab";
const preferencesPath = `${ObjC.unwrap($.NSHomeDirectory())}/Library/Preferences/${bundleID}.plist`;

function isChineseLocale() {
  const localeIdentifier = ObjC.unwrap($.NSLocale.currentLocale.localeIdentifier);
  return localeIdentifier.startsWith("zh");
}

function localizedText(chineseText, englishText) {
  return isChineseLocale() ? chineseText : englishText;
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\"'\"'`)}'`;
}

function shellFlag(testCommand) {
  return app.doShellScript(`${testCommand} && printf 1 || printf 0`) === "1";
}

const dialogTitle = localizedText("卸载 Flow Tab", "Uninstall Flow Tab");
const cancelButtonText = localizedText("取消", "Cancel");
const confirmButtonText = localizedText("卸载", "Uninstall");
const completionButtonText = localizedText("完成", "Done");
const confirmMessage = localizedText(
  "这会退出 Flow Tab，并从“应用程序”中删除它，同时重置辅助功能、屏幕录制权限记录并清理本地偏好设置。是否继续？",
  "This will quit Flow Tab, remove it from Applications, reset Accessibility and Screen Recording permissions, and clear local preferences. Continue?"
);
const successDetails = localizedText(
  "已重置辅助功能和屏幕录制权限记录，并清理本地偏好设置（如果存在）。",
  "Accessibility and Screen Recording permissions were reset, and local preferences were cleared if present."
);
const missingAppDetails = localizedText(
  "/Applications 中没有找到 Flow Tab.app，但其余清理步骤已经完成。",
  "No Flow Tab.app was found in /Applications, but the remaining cleanup steps still completed."
);

const appWasInstalled = shellFlag(`/bin/test -d ${shellQuote(appInstallPath)}`);

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
  const flowTab = Application(appDisplayName);
  if (flowTab.running()) {
    flowTab.quit();
  }
} catch (_) {
}

try {
  app.doShellScript(`/usr/bin/pkill -x ${shellQuote(appProcessName)} >/dev/null 2>&1 || true`);
} catch (_) {
}

delay(1);

const cleanupCommand = [
  `/bin/rm -rf ${shellQuote(appInstallPath)}`,
  `/usr/bin/tccutil reset Accessibility ${shellQuote(bundleID)} >/dev/null 2>&1 || true`,
  `/usr/bin/tccutil reset ScreenCapture ${shellQuote(bundleID)} >/dev/null 2>&1 || true`,
  `/usr/bin/defaults delete ${shellQuote(bundleID)} >/dev/null 2>&1 || true`,
  `/bin/rm -f ${shellQuote(preferencesPath)}`,
].join("; ");

try {
  app.doShellScript(cleanupCommand, {
    administratorPrivileges: true,
  });
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
