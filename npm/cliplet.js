#!/usr/bin/env node
"use strict";

const childProcess = require("node:child_process");
const fs = require("node:fs");
const https = require("node:https");
const os = require("node:os");
const path = require("node:path");

const repo = "IncredibleJ1021/cliplet";
const appName = "cliplet";
const installDir = process.env.CLIPLET_INSTALL_DIR || "/Applications";

function usage() {
  console.log(`Usage:
  cliplet-installer install      Download and install cliplet.app
  cliplet-installer uninstall    Remove cliplet.app from the install directory
  cliplet-installer open         Open the installed app

Environment:
  CLIPLET_VERSION=v0.3.0         Install a specific GitHub release tag
  CLIPLET_INSTALL_DIR=~/Apps     Install somewhere other than /Applications`);
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

function run(command, args, options = {}) {
  const result = childProcess.spawnSync(command, args, {
    stdio: "inherit",
    ...options
  });

  if (result.status !== 0) {
    process.exit(result.status || 1);
  }
}

function capture(command, args) {
  const result = childProcess.spawnSync(command, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"]
  });

  if (result.status !== 0) {
    process.exit(result.status || 1);
  }

  return result.stdout.trim();
}

function requireMacOS() {
  if (process.platform !== "darwin") {
    fail("cliplet is a macOS app. npm installation is only supported on macOS.");
  }
}

function latestTag() {
  if (process.env.CLIPLET_VERSION) {
    return process.env.CLIPLET_VERSION;
  }

  return new Promise((resolve, reject) => {
    const request = https.request(
      {
        hostname: "api.github.com",
        path: `/repos/${repo}/releases/latest`,
        headers: {
          "Accept": "application/vnd.github+json",
          "User-Agent": "cliplet-installer"
        }
      },
      response => {
        let body = "";

        response.on("data", chunk => {
          body += chunk;
        });

        response.on("end", () => {
          if (response.statusCode !== 200) {
            reject(new Error(`GitHub returned HTTP ${response.statusCode}`));
            return;
          }

          try {
            resolve(JSON.parse(body).tag_name);
          } catch (error) {
            reject(error);
          }
        });
      }
    );

    request.on("error", reject);
    request.end();
  });
}

function installTarget() {
  return path.join(installDir.replace(/^~(?=$|\/)/, os.homedir()), `${appName}.app`);
}

function canWriteDirectory(directory) {
  try {
    fs.accessSync(directory, fs.constants.W_OK);
    return true;
  } catch {
    return false;
  }
}

function removePath(target) {
  if (!fs.existsSync(target)) {
    return;
  }

  if (canWriteDirectory(path.dirname(target))) {
    run("rm", ["-rf", target]);
  } else {
    console.log(`Removing ${target} requires administrator privileges.`);
    run("sudo", ["rm", "-rf", target]);
  }
}

function copyApp(source, target) {
  removePath(target);

  if (canWriteDirectory(path.dirname(target))) {
    run("ditto", [source, target]);
  } else {
    console.log(`Installing to ${path.dirname(target)} requires administrator privileges.`);
    run("sudo", ["ditto", source, target]);
  }
}

async function install() {
  requireMacOS();

  if (!fs.existsSync(installDir.replace(/^~(?=$|\/)/, os.homedir()))) {
    fail(`Install directory does not exist: ${installDir}`);
  }

  const tag = await latestTag();
  const assetName = `cliplet-macOS-${tag}.zip`;
  const downloadURL = `https://github.com/${repo}/releases/download/${tag}/${assetName}`;
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "cliplet-npm-"));
  const zipPath = path.join(tempDir, assetName);
  const unzipDir = path.join(tempDir, "unzipped");

  try {
    fs.mkdirSync(unzipDir);
    console.log(`Downloading ${downloadURL}`);
    run("curl", ["-fL", downloadURL, "-o", zipPath]);
    run("unzip", ["-q", zipPath, "-d", unzipDir]);

    const appPath = capture("find", [unzipDir, "-maxdepth", "2", "-type", "d", "-name", `${appName}.app`, "-print", "-quit"]);
    if (!appPath) {
      fail(`Could not find ${appName}.app in downloaded archive.`);
    }

    const target = installTarget();
    copyApp(appPath, target);
    console.log(`Installed ${appName}.app to ${path.dirname(target)}`);
    console.log("If macOS blocks the first launch, open it once from Finder with Control-click > Open.");
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function uninstall() {
  requireMacOS();
  const target = installTarget();
  removePath(target);
  console.log(`Removed ${target}`);
}

function openApp() {
  requireMacOS();
  const target = installTarget();

  if (!fs.existsSync(target)) {
    fail(`Not installed: ${target}`);
  }

  run("open", [target]);
}

async function main() {
  const command = process.argv[2] || "install";

  switch (command) {
  case "install":
    await install();
    break;
  case "uninstall":
    uninstall();
    break;
  case "open":
    openApp();
    break;
  case "help":
  case "--help":
  case "-h":
    usage();
    break;
  default:
    usage();
    process.exit(1);
  }
}

main().catch(error => {
  fail(error.message);
});
