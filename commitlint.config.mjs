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
  },
};
