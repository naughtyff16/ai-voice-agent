# Coding Standards

## General Rules

Code should optimize for readability.

Future engineers should understand code without extensive comments.

---

## SOLID Principles

Always follow:

- Single Responsibility
- Open Closed
- Liskov
- Interface Segregation
- Dependency Inversion

---

## DRY

Avoid duplicated logic.

Extract reusable components.

---

## KISS

Prefer simple maintainable solutions.

Avoid unnecessary complexity.

---

## Naming

Use descriptive names.

Examples:

Good

CallRecordingService

CampaignScheduler

ConversationMemoryService

Bad

Helper

Manager

Util

Temp

---

## Functions

Functions should:

- Have one responsibility
- Be small
- Be testable
- Be deterministic

---

## Classes

Avoid God classes.

Keep responsibilities focused.

---

## Error Handling

Never swallow exceptions.

Use structured exceptions.

Return meaningful errors.

---

## Logging

Use structured logging.

Never use print().

Never log secrets.

---

## Configuration

Configuration must come from environment variables.

Never hardcode credentials.

---

## Testing

Every feature requires:

- Unit Tests
- Integration Tests
- Contract Tests

Critical workflows require E2E tests.

---

## Documentation

Public APIs require documentation.

Complex algorithms require design notes.

---

## Pull Requests

Every PR must include:

- Tests
- Documentation updates
- Migration notes
- Changelog when needed
