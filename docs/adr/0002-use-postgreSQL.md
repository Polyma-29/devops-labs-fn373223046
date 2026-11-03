# 1. Use PostgreSQL Database

* Status: accepted
* Date: 2026-11-03

## Context and Problem Statement

The notes application needs a persistent database to store notes long-term and integrate with Docker Compose.

## Decision Outcome

Chosen option: "PostgreSQL", because it is reliable, open-source, and integrates seamlessly using Docker Compose with persistent volumes.

## Consequences

* Good: Data persists across container restarts using volume mounts.
* Good: Easily configured via environment variables.
* Bad: Requires container configuration overhead compared to embedded databases.