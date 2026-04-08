# Show a Ticket's Lifecycle Timeline

Render a human-readable timeline of everything that's happened to a ticket. Useful when you come back to a project after time away and need to remember what state things are in.

## Input
Argument: `{ID}` (e.g. `TKT-005`)

If no argument given: show the timeline for every ticket that is NOT `shipped` or `closed` (the active set).

## Steps

1. **Read `.claude/ticket-config.md`** to find the tickets directory.

2. **Read the ticket file**. Parse:
   - Frontmatter: id, title, type, status, priority, branch, created, updated
   - Delegation Log section (if present)
   - Which sections have content (Investigation, Proposed Solution, Implementation Plan, Files Changed, Test Report, Verification Checklist, Peer Review *)

3. **Reconstruct the lifecycle** from these signals. A ticket's history is:
   - Created → status was `open`
   - Investigation filled → an investigate phase ran (Claude Code locally OR delegated)
   - Status went `proposed` → investigation accepted
   - Branch field set → either `/ticket-approve` or `/ticket-delegate ... implement` ran
   - Files Changed filled → implementation done
   - Verification Checklist filled → review done
   - Status `shipped` → ticket shipped

   Use the Delegation Log entries (if present) to attribute phases to specific tools/models/timestamps.

4. **Render the timeline** as a checklist with timestamps and attributions where known:

   ```
   TKT-005: Redesign project picker dropdown
     Status: delegated      Branch: ticket/tkt-005-redesign-project-picker
     Type: enhancement      Priority: medium
     Created: 2026-04-05    Updated: 2026-04-07

     Lifecycle:
       ✓ created                                                2026-04-05
       ✓ investigated (Claude Code)                             2026-04-05
       ✓ verified-investigate (Gemini via Copilot)              2026-04-06
           → 3 issues raised, all addressed in v2
       ✓ investigated v2 (Claude Code, revised)                 2026-04-06
       ✓ approved → branch created                              2026-04-06
       → delegated (implement) — awaiting Gemini                2026-04-07
       ⋯ collect pending
       ⋯ review pending
       ⋯ ship pending

     Next action:
       Run /run-brief in Copilot Chat (with Gemini) on:
         tickets/TKT-005.implement.brief.md
       Then come back and run: /ticket-collect TKT-005
   ```

5. **For the active-set view** (no argument), render a one-line-per-ticket summary instead:

   ```
   Active tickets in this project:
     TKT-003  delegated     verify-implement (Gemini reviewing)
     TKT-005  delegated     implement (Gemini implementing)
     TKT-007  proposed      ready for /ticket-approve
     TKT-008  open          ready for /ticket-investigate

   Run /ticket-status {ID} for the full timeline of any ticket.
   ```

## Rules
- This command is read-only. It does not modify the ticket file or any other state.
- If the ticket has no Delegation Log, infer phases from which sections are filled in (best-effort timeline without timestamps).
- Always show the "Next action" line — it's the most important part for someone returning cold.
- Be terse. The point is to reorient quickly, not to read paragraphs.
