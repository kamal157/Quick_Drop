# Security Policy

## Trust model

Quick_Drop is a local, single-user macOS agent. It runs **unsandboxed** and with
the full privileges of the user who launches it. Understand the following before
installing or distributing it.

### Code execution by design

- **`script` destinations execute arbitrary code.** When you drop files on a
  `script` destination, Quick_Drop runs the file at `path` (falling back to
  `/bin/sh path …`), passing the dropped file paths as arguments. A plain click
  on a script destination runs it with no arguments.
- **`app` and `share` destinations invoke `/usr/bin/open`** with user-supplied
  paths and the dropped files.

This is intentional — it is a launcher — but it means a destination is only as
trustworthy as the path it points at.

### Configuration is user-writable plaintext

Destinations are stored unencrypted at:

```
~/Library/Application Support/Quick_Drop/destinations.json
```

Any process running as your user can edit this file. Because `script`
destinations execute their `path`, **anything that can write `destinations.json`
can achieve code execution under your account the next time you click or drop
onto the affected entry.** Treat write access to this file as equivalent to
running code as you.

### Recommendations

- Only add `script` destinations that point at code you wrote or trust.
- Do not run Quick_Drop builds from untrusted sources. The provided `build.sh`
  ad-hoc signs the app; it is not notarized.
- If you redistribute a build, sign and notarize it yourself.

## Reporting a vulnerability

Open a GitHub issue, or for sensitive reports use private vulnerability
reporting on the repository. Please include reproduction steps and the macOS
version you observed the issue on.
