export default {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "scope-enum": [
      2,
      "always",
      ["qs", "stt", "scripts", "tools", "docs", "config", "ci", "deps"]
    ],
    "subject-case": [0]
  }
};
