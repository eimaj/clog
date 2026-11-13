## ADDED Requirements

### Requirement: Resolve clog logs

The skill SHALL resolve the clog log file of every calendar day the session touched, from the day of the session transcript's first entry through today, and SHALL pass every resolved existing path to the scout. It SHALL NOT limit the scan to today's log file. A day with no log file SHALL be skipped.

#### Scenario: Session spans several days

- **WHEN** the session transcript has entries on 2026-11-06 and 2026-11-09 and a log file exists for each day in between
- **THEN** the scout is given every existing log from 20261106 to 20261109 and a state-changer from 11-06 is matched against the 11-06 log

#### Scenario: Single-day session

- **WHEN** the session transcript has entries only on today's date
- **THEN** only today's log is resolved, as before

#### Scenario: A touched day has no log

- **WHEN** a day inside the session's span has no log file
- **THEN** that day is skipped and the state-changers of that day are reported as missing entries
