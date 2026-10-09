import { execFileSync } from "node:child_process";

const TYPES = "feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert";
const BRANCH_RE = new RegExp(
    `^(${TYPES})/(?:([a-z]+)-)?(\\d+)-([a-z0-9]+(?:-[a-z0-9]+)*)$`,
);
const HEADER_RE = new RegExp(`^(${TYPES})(?:\\(([a-z]+)\\))?!?: .+ #(\\d+)$`);
const CLOSES_RE = /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)/gi;

const { BRANCH, PR_TITLE, PR_BODY = "", BASE_SHA, HEAD_SHA } = process.env;
const errors = [];

const branch = BRANCH_RE.exec(BRANCH ?? "");
if (!branch) {
    errors.push(
        `Branch "${BRANCH}" must match <type>/<optional_scope>-<issue_number>-<description> (e.g. feat/qs-12-add-toggle).`,
    );
}
const issue = branch?.[3];

const title = HEADER_RE.exec(PR_TITLE ?? "");
if (!title) {
    errors.push(
        `PR title "${PR_TITLE}" must match <type>(<optional_scope>): <message> #<issue_number>.`,
    );
} else if (issue && title[3] !== issue) {
    errors.push(
        `PR title issue #${title[3]} does not match branch issue #${issue}.`,
    );
}

if (issue) {
    const closes = [...PR_BODY.matchAll(CLOSES_RE)].map((m) => m[1]);
    if (!closes.includes(issue)) {
        errors.push(
            `PR description must contain "Closes #${issue}" (issue from the branch name).`,
        );
    }
    if (closes.some((n) => n !== issue)) {
        errors.push(`PR description closes an issue other than #${issue}.`);
    }

    const subjects = execFileSync(
        "git",
        ["log", "--no-merges", "--format=%s", `${BASE_SHA}..${HEAD_SHA}`],
        { encoding: "utf8" },
    )
        .split("\n")
        .filter(Boolean);
    for (const subject of subjects) {
        const m = HEADER_RE.exec(subject);
        if (m && m[3] !== issue) {
            errors.push(
                `Commit "${subject}" references #${m[3]}, expected #${issue}.`,
            );
        }
    }
}

if (errors.length) {
    for (const e of errors) console.error(`::error::${e}`);
    process.exit(1);
}
console.log(`PR checks passed (issue #${issue}).`);
