## Why

The skill description contains angle-bracket placeholders (`<ids>`, `<id>`). Skill validators reject angle brackets and some marketplaces drop the skill, and the golden-skill-updater scanner flags it. The scout-versus-extractor finding is already covered by `sweep-jq-extract` and is left out here.

## What Changes

- Rewrite the front-matter description so the trigger phrases say "sweep sessions" followed by the session ids, and "backfill clogs for a session id", with no angle brackets.
- Leave the body untouched, including the scout prompt and step list, which `sweep-jq-extract` replaces.

## Impact

- Affected file: `skills/clog-sweep-sessions/SKILL.md` front matter only.
- Land after or alongside `sweep-jq-extract` so the two edits to the same file do not conflict; the description line is not edited by that change.
