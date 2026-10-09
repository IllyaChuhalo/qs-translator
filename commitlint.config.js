export default {
    extends: ["@commitlint/config-conventional"],
    plugins: [
        {
            rules: {
                "issue-ref-required": ({ subject }) => [
                    /\s#\d+$/.test(subject ?? ""),
                    "subject must end with an issue number, e.g. `feat(qs): add toggle #12`",
                ],
            },
        },
    ],
    rules: {
        "scope-enum": [
            2,
            "always",
            ["qs", "stt", "scripts", "tools", "docs", "config", "ci", "deps"],
        ],
        "subject-case": [0],
        "issue-ref-required": [2, "always"],
    },
};
