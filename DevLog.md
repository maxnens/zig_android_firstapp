# Development Log Methodology

**ALWAYS maintain a development log in `devlog.json` using this structure and rules.**

## Structure

```
Feature (top level - user's request)
  ├─ Problem 1 (discovered issue)
  │   ├─ Test 1 (action that revealed the problem)
  │   ├─ Test 2 (diagnostic test)
  │   └─ Solution
  │       ├─ Changes (code modifications with file references)
  │       └─ Problem 1.1 (NEW problem discovered while implementing solution)
  │           ├─ Test (diagnostic test for nested problem)
  │           └─ Solution
  │               └─ Problem 1.1.1 (even deeper rabbit hole)
  │                   └─ ... (can go 10+ levels deep)
  ├─ Problem 2
  │   └─ ...
  └─ Verification (final tests proving feature works)
```

## Nested Problems: The Rabbit Hole

**CRITICAL**: Problems can (and often will) be nested under Solutions.

When implementing a solution, you frequently discover new problems. This creates a "rabbit hole" hierarchy where:
- Problem → Solution → New Problem → New Solution → Even Newer Problem → ...
- **10+ levels of nesting is not uncommon and is EXPECTED**
- Each level down represents going deeper "into the weeds"

### Why This Matters

The depth of nesting serves as:
1. **Depth indicator**: How far into the weeds are we?
2. **Context reminder**: What high-level problem were we trying to solve?
3. **Sanity check**: Have we lost cohesion with the original goal?

### When to Pop Back Up

If you find yourself 5+ levels deep:
1. **STOP** and review the hierarchy
2. **Ask**: Are we still solving the original problem?
3. **Check**: Have we diverged from the high-level goal? (See ProjectGoal.md)
4. **Consider**: Is there a simpler approach at a higher level?
5. **Document**: Add a note in the deepest problem about the depth and context

Use the devlog itself to track if we've maintained cohesion with high-level goals.

## Rules

1. **Add timestamps to EVERY entry** using ISO 8601 format (YYYY-MM-DDTHH:MM:SSZ)
2. **Every change MUST reference a git commit** - use "pending" only for uncommitted work
3. **Features have**: `started` and `completed` timestamps, `commits` array, and `status` ("in_progress" or "resolved")
4. **Problems have**: `discovered` and `resolved` timestamps, `commit` field, and `status`
5. **Every test run, compile attempt, or diagnostic action** gets a timestamped entry
6. **Test failures** become sub-nodes under the problem they reveal
7. **Code changes** reference files and line numbers - NEVER include actual code
8. **Each change includes**: `commit` hash and a `note` with "git show <commit>:<file>" for viewing
9. **When tests pass** and problem is resolved, mark status as "resolved" with resolution timestamp and commit
10. **Order entries chronologically** by timestamp - this creates an audit trail
11. **NEW: Nest problems under solutions** when implementation reveals new issues

## When to Log

- **Before starting**: Create feature entry with "in_progress" status
- **Every compilation**: Log with timestamp, result (success/failure), errors
- **Every test run**: Log with timestamp, action, result
- **When writing code**: Log change with timestamp, file, description, line numbers
- **When problem resolved**: Update problem status to "resolved" with timestamp
- **When new problem discovered during solution**: Add nested problem node
- **Feature complete**: Update feature status to "resolved" with completion timestamp
- **Going deep**: Add depth/context notes when 5+ levels nested

## What to Record

- **Diagnostic insights**: 5-Whys analysis, hypotheses formed/tested
- **Build/compile results**: Success or specific error messages
- **Test results**: Pass/fail and what was learned
- **Code modifications**: File paths, line ranges, brief description, **commit hash**, git show reference
- **Git commits**: Commit hash and timestamp when feature/fix is committed
- **Rabbit hole depth**: Notes about nesting depth and whether we've lost sight of high-level goals

## Git Integration (CRITICAL)

**Every change must be traceable to a commit for posterity:**
- Add `commit: "<hash>"` to every change entry
- Add `commits: ["<hash1>", "<hash2>"]` array to feature level
- Include `note: "View at: git show <commit>:<file>"` so future readers can see the exact code
- Use `commit: "pending"` only for uncommitted work-in-progress
- When committing, update all "pending" references to the actual commit hash

**Why this matters:**
- File/line references mean nothing without commit context (files change over time)
- `git show <commit>:<file>` lets anyone view the exact file state being discussed
- Creates a complete audit trail linking problems → solutions → code → commits
- Makes the devlog useful months/years later when investigating why decisions were made

## Example: Nested Problem Structure

```json
{
  "name": "Implement market data retrieval",
  "problems": [
    {
      "name": "TWS API integration needed",
      "solution": {
        "description": "Add TWS API to build system",
        "problems": [
          {
            "name": "Protobuf version incompatibility",
            "solution": {
              "description": "Try building with system protobuf",
              "problems": [
                {
                  "name": "v33 vs v3.12 incompatible APIs",
                  "solution": {
                    "description": "Investigate building TWS protobuf from source",
                    "problems": [
                      {
                        "name": "protoc version mismatch",
                        "notes": "DEPTH CHECK: 4 levels deep. Original goal: market data. Current: compiler versioning. Still on track? Applied 5-Whys: Do we need full API now? No. Simplified to socket-only."
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  ]
}
```

## Maintaining Cohesion

**Every 5 levels deep, ask:**
1. What was the original feature we're implementing?
2. What was the top-level problem we're solving?
3. Have we diverged from the goal in ProjectGoal.md?
4. Is there a simpler approach at a higher level?
5. Should we document this rabbit hole and backtrack?

**Document your depth check** in the devlog at that level.

## Purpose

This creates a complete, timestamped history of problem-solving that documents:
- What was tried and when
- Why decisions were made
- How problems were diagnosed
- What worked and what didn't
- **Where in git history each change exists**
- **How deep the rabbit holes went**
- **Whether we maintained focus on the high-level goal**
