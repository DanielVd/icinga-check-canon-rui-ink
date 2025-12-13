# icinga-check-canon-rui-ink

Icinga/Nagios Bash plugin to monitor Canon printer ink levels via the Canon Remote UI (RUI).

The plugin implements the full session-based authentication flow used by Canon printers
(`sendpw.cgi → SBID → index.html`) and retrieves ink information from
`prninfo_data.cgi`, returning standard **OK / WARNING / CRITICAL / UNKNOWN**
states compatible with Icinga and Nagios.

---

## Features

- Pure Bash plugin (no Python, no Perl)
- Uses Canon Remote UI (RUI) internal endpoints
- Handles session-based authentication (SCID + SBID)
- Nagios/Icinga compliant output and exit codes
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
|--------|-------------|
| `NAMAE` | Canon password hash captured from the web UI |

### Optional variables

| Variable | Default | Description |
|--------|---------|-------------|
| `BASE` | `https://printer.example.local` | Canon Remote UI base URL |
| `IDTYPE` | `2` | Canon authentication type |

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
```
[OK] Black:40%(OK) Color:30%(OK)
```

**WARNING**
```
[WARNING] Black:10%(LOW) Color:30%(OK)
```

**CRITICAL**
```
[CRITICAL] Black:0%(EMPTY) Color:20%(LOW)
```

**UNKNOWN**
```
[UNKNOWN] login step sendpw.cgi failed
```

On UNKNOWN, the script prints the full authentication and request flow
to help troubleshooting.

---

## Exit codes

| Code | Meaning |
|----|--------|
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

---

## TL;DR – How these values were obtained

Canon printers do not expose ink levels via SNMP or simple REST APIs.

By inspecting the Canon Remote UI with browser developer tools:

1. The web interface periodically calls:
   ```
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
