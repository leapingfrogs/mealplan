// Conventional Commits, as read by release-please to pick versions and write
// the changelog. Used by `just lint-commits` and CI.
export default {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "type-enum": [
      2,
      "always",
      ["feat", "fix", "perf", "refactor", "docs", "test", "build", "ci", "chore", "style", "revert"],
    ],
    // Only the header and footers matter to release-please; Dependabot bodies
    // quote release notes with long lines and URLs.
    "body-max-line-length": [0],
    "footer-max-line-length": [0],
  },
};
