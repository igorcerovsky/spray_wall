# Boulder Specification v1

## 1. Scope
This specification defines a local-first boulder workflow for SprayWall:

1. Create and edit boulders from existing hold positions.
2. Save boulders as drafts or established entries.
3. Display a selected boulder on the wall with group-specific highlighting.

## 2. Terminology

1. Use `boulder` in UI and code.
2. Existing `route` data is not migrated into boulders.

## 3. Boulder Structure
A boulder is a set of existing holds partitioned into disjoint groups:

1. `start` holds: 1 to 2 holds when established.
2. `holds`: arbitrary count, arbitrary order.
3. `footholds`: arbitrary count.
4. `top` holds: at least one hold when established.

Rules:

1. A hold may appear in only one group within the same boulder.
2. A hold may be reused across different boulders.

## 4. Boulder Data Model
Each boulder stores:

1. `boulderID` (unique integer id).
2. `name` (text).
3. `status` (`draft` or `established`).
4. `startHoldIDs` ([Int]).
5. `holdIDs` ([Int]).
6. `footholdIDs` ([Int]).
7. `topHoldIDs` ([Int]).
8. `grade` (optional text).
9. `setter` (optional text).
10. `tags` (optional text field, comma-separated in v1).
11. `notes` (optional text).
12. `createdAt`.
13. `updatedAt`.

## 5. Validation

### 5.1 Draft Save
Draft save allows unfinished content but still enforces structural integrity:

1. IDs are unique inside each group.
2. No hold exists in multiple groups of the same boulder.

### 5.2 Establish Save
To mark a boulder as established, all must pass:

1. Name is non-empty.
2. Start holds count is 1 or 2.
3. Top holds count is at least 1.
4. All referenced hold IDs exist in the hold database.
5. No cross-group overlap.

If validation fails, the boulder remains draft.

## 6. Boulder UI

### 6.1 Holds Tab

1. Holds tab is for hold position + id only.
2. Dot symbol is used for hold positioning in this stage.

### 6.2 Boulder Tab
Boulder tab provides:

1. Boulder database list (local SwiftData).
2. Create/delete boulder.
3. Open boulder editor.
4. Status badges (`draft`, `established`).

### 6.3 Boulder Editor

1. Wall preview shows all existing holds.
2. Holds in the active boulder are highlighted by group:
   - Start: green square.
   - Hold: blue circle.
   - Top: red square.
   - Foothold: yellow diamond.
3. Non-member holds are shown dimmed.
4. Two assignment interaction modes are supported:
   - Role-first: choose group tool, then click holds.
   - Click-first: click hold, then choose group action.
5. Existing hold properties can be opened from selected hold for editing.

## 7. Storage and Sync

1. Persistence is local-only in v1 (SwiftData).
2. Cloud/server sync is out of scope for v1.

## 8. Acceptance Criteria

1. User can create a boulder using only existing holds.
2. User can save unfinished boulder as draft.
3. User can establish only if validation passes.
4. Selected boulder displays correct color/symbol mapping on wall.
5. Boulder records persist across app restarts.
