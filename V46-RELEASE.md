Friday v46 - preserve observed search labels in planner recovery

Fixes a concrete recovery-scope bug exposed while investigating the v45 YouTube search phone report: a Search control with generic resource ID could be recognized by recovery, then lose its Search content description when the action target was built, causing the outer scope gate to reject it. Recovery now retains every nonempty observed target field and checks the generated action against the same goal scope before returning it. Protected or ambiguous targets remain blocked. No permission/scope/confidence gate is relaxed.

212 automated Flutter tests pass; analyze has no errors (existing lint warnings). Existing local Qwen0.5B .task engine/model and all v45 functionality retained. Exact failed model target was not supplied by the phone screenshot, so this is a source-confirmed defect fix, not a claim to have reproduced every phone step. Retest the same YouTube search and share Last decision if it still stops.

Real-device workflows remain unverified. Music Play/Next media routing still needs the user's app/queue/direct-session access choice. Screenshot preview is not model vision. No full screen-control completion claim.
