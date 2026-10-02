# Security Policy

Margin handles your notes and, for cloud backends, access tokens. If you find a
vulnerability, please report it privately so it can be fixed before it's public.

## Reporting a vulnerability

- **Please do not open a public issue or pull request for security problems.**
- Use GitHub's **private vulnerability reporting** for this repository:
  the **Security** tab → **Report a vulnerability**. This opens a private advisory
  visible only to you and the maintainer.

When reporting, include what you can: affected version, platform, steps to
reproduce, and the impact as you see it.

## What to expect

This is a solo-maintained side project, so there is **no guaranteed response
time** — but security reports are taken seriously and prioritized over feature
work. You'll get an acknowledgement, a discussion of the fix, and credit in the
release notes if you'd like it.

## Supported versions

Only the **latest release** is supported. Fixes ship in a new release rather than
being backported.

## Good to know

- Secrets (WebDAV passwords, OneDrive tokens) are stored in the **OS keystore**,
  never in the notes folder or the repository.
- Margin runs no code from notes, has no plugin system, and is not an IDE — the
  attack surface is deliberately small.
