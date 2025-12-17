# Renovate Configuration Documentation

This document explains the Renovate configuration in `renovate.json` for automated dependency management.

## Base Configuration

### Extends
```json
"extends": [
  "config:recommended",
  ":enableVulnerabilityAlerts",
  ":dependencyDashboard",
  ":semanticCommits"
]
```

- **config:recommended** - Renovate's recommended base configuration with sensible defaults
- **:enableVulnerabilityAlerts** - Creates PRs immediately when security vulnerabilities are detected
- **:dependencyDashboard** - Creates a GitHub issue that provides an overview of all pending updates
- **:semanticCommits** - Uses conventional commit format (e.g., `chore(deps): update dependencies`)

## Scheduling & Rate Limits

```json
"timezone": "Europe/Berlin"
"schedule": ["before 5am on monday"]
"prHourlyLimit": 10
"prConcurrentLimit": 5
```

- Updates run before 5am on Mondays in Berlin timezone
- Maximum 10 PRs per hour to avoid overwhelming the repository
- Maximum 5 concurrent open PRs at any time

## Update Strategy

```json
"rebaseWhen": "behind-base-branch"
"separateMinorPatch": true
"rangeStrategy": "bump"
"automergeType": "branch"
```

- **rebaseWhen** - Rebases PRs when the base branch has moved ahead
- **separateMinorPatch** - Creates separate PRs for minor vs patch updates
- **rangeStrategy: bump** - Updates both the version range and the exact version
- **automergeType: branch** - Merges directly to the branch (no merge commits, maintains flat git history)

## Labels

```json
"labels": ["dependencies"]
```

- All Renovate PRs get the `dependencies` label for easy filtering

## Lock File Maintenance

```json
"lockFileMaintenance": {
  "enabled": true,
  "automerge": true,
  "schedule": ["before 5am on monday"]
}
```

Updates lock files (package-lock.json, pom.xml) even when no dependency versions change, ensuring lock files stay current with the latest resolved versions.

## Security Updates

```json
"vulnerabilityAlerts": {
  "enabled": true,
  "labels": ["security"],
  "automerge": true,
  "schedule": ["at any time"]
}
```

Security updates override the Monday schedule and can run at any time. They get an additional `security` label and are automatically merged after CI passes.

## Package Rules

### 1. Auto-merge Strategy by Update Type

```json
{
  "matchUpdateTypes": ["minor", "patch"],
  "matchDepTypes": ["dependencies"],
  "automerge": true
}
```
Minor and patch updates to production dependencies are automatically merged after CI passes.

```json
{
  "matchUpdateTypes": ["major"],
  "automerge": false
}
```
Major updates always require manual review (never auto-merged).

### 2. Maven Dependencies

```json
{
  "matchDatasources": ["maven"],
  "matchUpdateTypes": ["minor", "patch"],
  "groupName": "maven non-major dependencies"
}
```
Groups all non-major Maven dependency updates into a single PR to reduce PR noise.

### 3. NPM Dependencies

```json
{
  "matchManagers": ["npm"],
  "matchDepTypes": ["dependencies"],
  "matchUpdateTypes": ["minor", "patch"],
  "groupName": "npm production dependencies"
}
```
Groups non-major npm production dependencies together.

```json
{
  "matchManagers": ["npm"],
  "matchDepTypes": ["devDependencies"],
  "matchUpdateTypes": ["minor", "patch"],
  "groupName": "npm dev dependencies"
}
```
Groups npm dev dependencies separately from production dependencies.

### 4. Unstable (0.x) Packages

```json
{
  "matchCurrentVersion": "/^0\\./",
  "automerge": false,
  "groupName": "unstable (0.x) dependencies"
}
```
Packages with version < 1.0.0 are considered unstable and never auto-merged. They're grouped together for easier review.

### 5. GitHub Actions Security

```json
{
  "matchManagers": ["github-actions"],
  "pinDigests": true
}
```
Pins GitHub Actions to specific commit SHAs for security. This prevents supply chain attacks where action tags could be moved to malicious code.

### 6. Security Updates Priority

```json
{
  "matchUpdateTypes": ["patch"],
  "vulnerabilityAlerts": { "enabled": true },
  "automerge": true,
  "schedule": ["at any time"]
}
```
Security-related patch updates bypass the normal schedule and merge immediately after CI passes.

### 7. Spring Framework Grouping

```json
{
  "matchPackagePatterns": ["^org\\.springframework"],
  "matchDatasources": ["maven"],
  "groupName": "Spring Framework"
}
```
Groups all Spring Framework dependencies together since they should typically be updated in sync.

## Summary

This configuration prioritizes:
- **Security** - Immediate updates for vulnerabilities
- **Stability** - Manual review for major updates, auto-merge for minor/patch
- **Maintainability** - Grouped updates reduce PR noise
- **Clean history** - Branch automerge maintains flat git history
- **Visibility** - Dashboard and labels make tracking easy
