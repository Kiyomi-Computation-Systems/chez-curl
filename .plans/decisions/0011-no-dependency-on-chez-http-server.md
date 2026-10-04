# ADR-0011: chez-curl and chez-http-server do not depend on each other

- **Status:** Accepted
- **Date:** 2026-10-04
- **Scope:** chez-curl and its test lanes
- **Settles:** D5 (brief §10)
- **Related:** [ADR-0005](0005-node-test-origin.md) (chez-curl's test origin) · brief §3 ·
  chez-http-server decisions 0006 and 0017

## Context

The brief asked whether chez-http-server's black-box lane should use chez-curl. It would be
a good first consumer, but it would couple the two projects' schedules, so the brief
recommended no dependency before chez-curl's v0.1.0.

chez-http-server has since settled that lane. Its decision 0017 (2026-10-03, the owner's
call: "curl and vtest2") makes it curl scripts plus vtest2's `.vtc` scripts. It dropped hurl
"since it reads responses through libcurl, as curl does". chez-curl reads responses through
libcurl too.

Its decision 0006 answers an h2c preface with 505: chez-http-server speaks HTTP/1.x only.
ADR-0005 had already rejected a Chez server as chez-curl's test origin.

## Decision

- **chez-curl's tests never use chez-http-server.** chez-curl takes on no obligation to
  chez-http-server's lanes, before v0.1.0 or after.
- **chez-http-server's lane is its own decision (its 0017).** Any later link between the two
  is a new decision there, not here.
- **The two projects share no code** (brief §3).

### Rejected

- **An interop smoke test after v0.1.0.** As a test it would see nothing chez-http-server's
  curl lane does not already see, since both read through libcurl. And it would loosely tie
  the two projects' releases.
- **Depending now.** It couples the schedules, which the brief warned against.

## Consequences

- **chez-curl keeps its own release schedule.**
- **If chez-http-server later wants chez-curl in a lane,** it pins a chez-curl release and
  uses its public libraries, like any other consumer.
- **A program that uses both projects is still possible** as an example, outside both test
  suites.
