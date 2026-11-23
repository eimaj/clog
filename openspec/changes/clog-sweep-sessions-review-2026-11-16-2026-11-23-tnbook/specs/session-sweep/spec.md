## ADDED Requirements

### Requirement: Skill description is validator-safe

The `clog-sweep-sessions` front-matter description SHALL contain no angle brackets, and SHALL still name its trigger phrases.

#### Scenario: Validator reads the description

- **WHEN** a skill validator or the golden-skill-updater scanner reads the front-matter description
- **THEN** it finds no angle-bracket characters
- **AND** the description still mentions "sweep sessions", "clog sweep these sessions" and "backfill clogs for a session id"
