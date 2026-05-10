# Security Policy

LayerLens runs locally and only talks to your keyboard via Apple's
IOHIDManager APIs — there's no server-side attack surface. Most security
issues will fall into one of:

- An untrusted-input bug in keymap or HID-payload parsing
- A flaw in the Sparkle auto-update flow (signature bypass, downgrade)
- A privilege-escalation issue around HID device access

## Reporting a vulnerability

**Please do not open a public issue.** Use GitHub's private vulnerability
reporting to file an advisory directly:

> [github.com/FireBall1725/LayerLens/security/advisories/new](https://github.com/FireBall1725/LayerLens/security/advisories/new)

I aim to:
- Acknowledge new reports within 72 hours
- Ship a fix within 14 days for severe issues, or coordinate a longer
  timeline if the fix is non-trivial

Coordinated disclosure is appreciated. Credit will be given in the
release notes; let me know if you'd prefer to stay anonymous.

## Supported versions

Only the latest released version is supported. Backports to older
versions aren't planned.

## Out of scope

- Bugs in LayerLens's *appearance* or UX. File those as regular issues.
- The bundled `firmware/layerlens_notify` C module runs on the keyboard,
  not the host — there's no remote attack surface. Memory-safety bugs
  in that module should still be reported here.
