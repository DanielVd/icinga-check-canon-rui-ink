# icinga-check-canon-rui-ink

Icinga/Nagios Bash plugin to monitor Canon printer ink levels via the Canon Remote UI (RUI).

The plugin implements the full session-based authentication flow used by Canon printers
(`sendpw.cgi → SBID → index.html`) and retrieves ink information from
`prninfo_data.cgi`, returning standard **OK / WARNING / CRITICAL / UNKNOWN**
states compatible with Icinga and Nagios.

![Language](https://img.shields.io/github/languages/top/DanielVd/icinga-check-canon-rui-ink)
![License](https://img.shields.io/github/license/DanielVd/icinga-check-canon-rui-ink)
![Last commit](https://img.shields.io/github/last-commit/DanielVd/icinga-check-canon-rui-ink)
![Release](https://img.shields.io/github/v/release/DanielVd/icinga-check-canon-rui-ink)

---

## Setup

1. Ensure the requirements listed below are available on the host where the plugin will run.
2. Configure the plugin via the environment variables described in the Configuration section.
3. Run the script manually to verify output, then integrate it into Icinga/Nagios as needed.

---

## Features

- Pure Bash plugin (no Python, no Perl)
- Uses Canon Remote UI (RUI) internal endpoints
- Handles session-based authentication (SCID + SBID)
- Retries login when the printer web UI is still waking up
- Nagios/Icinga compliant output and exit codes
- Emits perfdata for ink levels (`color`, `black`, ...)
- Silent during normal operation
- Full debug output only on UNKNOWN
- Suitable for Icinga Director usage

---

## Requirements

- Bash 4+
- curl
- grep, sed, cut, head
- Network access to the printer RUI (HTTPS)

---

## Configuration

The plugin is configured via **environment variables**.

### Required variables

| Variable | Description |
| --- | --- |
| `NAMAE` | Canon password hash captured from the web UI |

### Optional variables

| Variable | Default | Description |
| --- | --- | --- |
| `BASE` | `https://printer.example.local` | Canon Remote UI base URL |
| `IDTYPE` | `2` | Canon authentication type |
| `LOGIN_RETRIES` | `3` | Retries login if `SBID` is not immediately available |
| `WAKEUP_DELAY_SECONDS` | `3` | Delay between wake-up/login retries |

### Example configuration

```bash
export BASE="https://printer.example.local"
export NAMAE="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
```

---

## Usage

### Manual execution

```bash
./check_canon_rui_ink.sh
```

### Example outputs

**OK**
```text
[OK] Black:40% Color:30% | black=40%;;;0;100 color=30%;;;0;100
```

**WARNING**
```text
[WARNING] Black:10% Color:30% | black=10%;;;0;100 color=30%;;;0;100
```

**CRITICAL**
```text
[CRITICAL] Black:0% Color:20% | black=0%;;;0;100 color=20%;;;0;100
```

**UNKNOWN**
```text
[UNKNOWN] login step sendpw.cgi failed
```

On UNKNOWN, the script prints the full authentication and request flow
to help troubleshooting. Sensitive values such as `NAMAE` are redacted from debug output.

---

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | OK |
| 1 | WARNING |
| 2 | CRITICAL |
| 3 | UNKNOWN |

---

## Icinga / Nagios integration

Recommended approaches:

- Wrap the script and export `NAMAE` inside the wrapper
- Or define `NAMAE` in:
  - `/etc/default/icinga2`
  - `/etc/sysconfig/icinga2`

Avoid passing credentials via command arguments.

### Example wrapper

```bash
#!/usr/bin/env bash
export BASE="https://printer.example.local"
export NAMAE="<redacted>"
exec /opt/scripts/check_canon_rui_ink.sh
```

### Perfdata

When the printer returns numeric levels, the plugin emits perfdata per cartridge:

```text
color=0%;;;0;100 black=20%;;;0;100
```

This works well with Icinga perfdata writers and Grafana dashboards backed by InfluxDB.

---

## TL;DR – How these values were obtained

Canon printers do not expose ink levels via SNMP or simple REST APIs.

By inspecting the Canon Remote UI with browser developer tools:

1. The web interface periodically calls:
   ```text
   /rui/prninfo_data.cgi
   ```
2. The response contains XML entries like:
   ```xml
   <INKREST0>0,6,0</INKREST0>
   ```
3. Canon JavaScript files (`model.js`, `view.js`) reveal the meaning:

   - First value: ink type index
   - Second value: ink level index (mapped to percentages)
   - Third value: ink status
     - `0` = OK
     - `1` = Low ink
     - `2` = Empty
     - `3` = Unknown / unsupported

4. Authentication is session-based:
   - Password is sent as a hashed value (`NAMAE`)
   - Canon sets a session cookie (`SCID`)
   - A session identifier (`SBID`) must be reused for all requests

This plugin reproduces that exact flow in a monitoring-safe way.

---

## Disclaimer

This project is not affiliated with Canon.

The implementation is based on reverse engineering of publicly exposed
Canon Remote UI endpoints. Use at your own risk.

---

## License

MIT
