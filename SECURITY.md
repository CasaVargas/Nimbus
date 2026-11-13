# Security Policy

## Reporting a vulnerability

Please do not report security problems through public issues, pull requests
or discussions.

Use GitHub's private vulnerability reporting instead: open the repository's
**Security** tab and choose **Report a vulnerability**. That creates a private
advisory that only the maintainers can see. Include the Nimbus version, the
macOS version, the rclone version, the cloud provider involved if any, and
steps to reproduce.

You should get an acknowledgement within a week. Nimbus is maintained by a
single developer, so fixes may take longer than a large project's would; you
will be kept informed in the advisory thread. Once a fix ships, the advisory
is published and you are credited unless you ask not to be.

## Scope

In scope:

- The Nimbus app (`Nimbus/Nimbus/`)
- The File Provider extension (`Nimbus/FileProviderExtension/`)
- RcloneKit, the Swift client for the rclone RC API (`RcloneKit/`)
- The build and packaging scripts under `scripts/`

Out of scope:

- rclone itself. Nimbus spawns the rclone binary installed on your Mac and
  never modifies it. Report rclone vulnerabilities upstream at
  https://github.com/rclone/rclone/security.
- The frozen Tauri sources under `legacy/tauri/`. They are not built, not
  shipped and not maintained.
- Issues in cloud providers' own services.

## How Nimbus talks to the network

Nimbus starts `rclone rcd` bound to `127.0.0.1` on a local port (5572 by
default), and both the app and the File Provider extension talk to that daemon
over loopback HTTP. Since 1.2.2 the daemon requires a username and password
that Nimbus generates at random on every launch and hands to rclone through
its environment (never its command line), and it sends no CORS headers, so
neither other apps nor web pages can use it. Earlier versions ran it without
authentication (GHSA-c784-cjq9-53gf). All traffic to cloud
providers is made by rclone. Nimbus itself makes two other kinds of request,
each only after you ask for it:

- the rclone download offered on first launch (rclone.org and github.com,
  checked against rclone's published checksums);
- update checks through [Sparkle](https://sparkle-project.org). They are off
  until you turn on "Check for updates automatically" or choose Check for
  Updates. A check is one HTTPS request for the appcast attached to the
  latest GitHub release; no system profile is sent. An update is installed
  only if its EdDSA signature matches the key built into the app; the
  signature is checked before the download is opened.

There is no crash reporting and no analytics. If you find that claim to be
false, that is a bug worth reporting here.

## Supported versions

Only the latest release receives security fixes. There are no long-term
support branches.
