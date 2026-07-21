#!/usr/bin/env node

const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fileSystem = require("node:fs");
const operatingSystem = require("node:os");
const path = require("node:path");

const uninstaller = require("./uninstall-flowtab.js");

const temporaryRoot = fileSystem.mkdtempSync(
  path.join(operatingSystem.tmpdir(), "flowtab-uninstaller-")
);

try {
  const userHomeDirectory = path.join(temporaryRoot, "user-home");
  const applicationSupportDirectory = path.join(
    userHomeDirectory,
    "Library",
    "Application Support"
  );
  const neighboringDirectory = path.join(applicationSupportDirectory, "NeighborApp");
  const neighboringMarker = path.join(neighboringDirectory, "keep.txt");

  const cleanupPaths = uninstaller.makeCleanupPaths({
    userHomeDirectory,
    applicationSupportDirectory,
  });

  assert.equal(
    cleanupPaths.logsDirectory,
    path.join(applicationSupportDirectory, "FlowTab", "logs")
  );

  fileSystem.mkdirSync(cleanupPaths.logsDirectory, { recursive: true });
  fileSystem.mkdirSync(neighboringDirectory, { recursive: true });
  fileSystem.writeFileSync(path.join(cleanupPaths.logsDirectory, "runtime.log"), "private log");
  fileSystem.writeFileSync(neighboringMarker, "keep");

  childProcess.execFileSync(
    "/bin/sh",
    ["-c", uninstaller.makeLogsCleanupCommand(cleanupPaths)],
    { stdio: "pipe" }
  );

  assert.equal(fileSystem.existsSync(cleanupPaths.logsDirectory), false);
  assert.equal(fileSystem.readFileSync(neighboringMarker, "utf8"), "keep");
} finally {
  fileSystem.rmSync(temporaryRoot, { recursive: true, force: true });
}

console.log("Uninstaller removes only FlowTab logs within the user Application Support boundary.");
