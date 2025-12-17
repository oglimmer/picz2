import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function getGitHash() {
  try {
    return execSync("git rev-parse --short HEAD", {
      stdio: ["ignore", "pipe", "ignore"],
    })
      .toString()
      .trim();
  } catch {
    return "unknown";
  }
}

function getGitBranch() {
  try {
    return execSync("git rev-parse --abbrev-ref HEAD", {
      stdio: ["ignore", "pipe", "ignore"],
    })
      .toString()
      .trim();
  } catch {
    return "unknown";
  }
}

function getPackageVersion() {
  if (process.env.npm_package_version) return process.env.npm_package_version;
  try {
    const pkgPath = path.join(__dirname, "..", "package.json");
    const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
    return pkg.version || "0.0.0";
  } catch {
    return "0.0.0";
  }
}

const buildInfo = {
  version: getPackageVersion(),
  gitHash: getGitHash(),
  gitBranch: getGitBranch(),
  buildDate: new Date().toISOString(),
  nodeVersion: process.version,
};

const publicDir = path.join(__dirname, "..", "public");
const outputPath = path.join(publicDir, "build-info.json");
fs.mkdirSync(publicDir, { recursive: true });
fs.writeFileSync(outputPath, JSON.stringify(buildInfo, null, 2));
console.log("Build info generated at", outputPath, buildInfo);
