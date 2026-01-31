# Development Methodology for Claude Code

## Project Context

**ALWAYS read these files before starting work:**
- **[ProjectGoal.md](ProjectGoal.md)** - Understand the end goal and current status
- **[DevLog.md](DevLog.md)** - Development logging methodology and structure

These provide essential context about what we're building and how to track progress.

## Test-First Development (NON-NEGOTIABLE)

1. **Write the test FIRST** - Before writing ANY implementation code
2. **Run the test** - Verify it fails for the right reason
3. **Implement minimal code** - Just enough to pass the test
4. **Run the test again** - Verify it passes
5. **Only then move forward** - Never skip to the next function without passing tests

## When Encountering Bugs

**STOP. DO NOT JUMP TO CONCLUSIONS.**

Use the 5-Whys technique:
1. Write a diagnostic test that reproduces the bug
2. Ask "Why did this fail?" - Form hypothesis
3. Write a test to verify the hypothesis
4. Run the test to confirm or refute
5. Repeat until you reach the root cause

**Never assume you know the cause without a test proving it.**

## Development Logging (IMPERATIVE)

**ALWAYS maintain `devlog.json` throughout development.**

See **[DevLog.md](DevLog.md)** for complete methodology including:
- Hierarchical structure (Feature → Problem → Solution)
- **Nested problems** (rabbit holes can go 10+ levels deep)
- Timestamps and git integration requirements
- When to check for loss of high-level focus
- How to maintain cohesion with ProjectGoal.md

**Key points:**
- Log every test, every compile, every code change
- Reference git commits for all changes
- Nest problems under solutions when implementation reveals new issues
- Check depth regularly - 5+ levels means review the hierarchy
- Use devlog to verify alignment with high-level goals

## Aggressive Code Hygiene

When a solution doesn't work or leads to a dead end:

1. **DELETE IT IMMEDIATELY** - Don't leave commented-out code
2. **Delete the tests** - Remove tests for removed functionality
3. **Delete supporting code** - Remove any infrastructure built for the failed approach
4. **Start fresh** - Go back to last known-good state

**Dead code is worse than no code. Remove it aggressively.**

## Diagnostic Testing

When debugging:
- Write small, focused tests that isolate the problem
- Test one thing at a time
- Build up from simple to complex
- Each test must prove or disprove ONE hypothesis

## Before Writing More Code

Ask yourself:
1. Did I write a test for the last function?
2. Does the test pass?
3. Did I run `zig build test` successfully?
4. Have I cleaned up any failed attempts?
5. Is the devlog up to date?
6. Am I still aligned with the goals in ProjectGoal.md?

**If any answer is "no", STOP and fix it before proceeding.**

## Remember

- Tests are documentation of correct behavior
- Tests prevent regression
- Tests guide implementation
- Tests prove fixes
- Untested code is broken code
- **The devlog tracks your problem-solving journey**
- **Check ProjectGoal.md regularly to maintain focus**

**When in doubt, write a test.**
