# icinga-check-canon-rui-ink

[![Latest Release](https://img.shields.io/github/v/release/DanielVd/icinga-check-canon-rui-ink)](https://github.com/DanielVd/icinga-check-canon-rui-ink/releases/latest)
![Python](https://img.shields.io/badge/python-3.10%2B-blue)

Icinga/Nagios plugin to check Canon device ink/toner levels via Remote UI endpoints.

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Options](#options)
- [Exit Codes](#exit-codes)
- [Troubleshooting](#troubleshooting)
- [Security Notes](#security-notes)

## Features

- Queries Canon device status pages
- Reports per-color consumable levels
- Returns monitoring-friendly status and perf data

## Requirements

- Python 3.10+
- Network access to Canon device Remote UI

## Installation

```bash
git clone https://github.com/DanielVd/icinga-check-canon-rui-ink.git
cd icinga-check-canon-rui-ink
```

## Quick Start

```bash
python3 check_canon_rui_ink.py --host <printer-host> --warning 20 --critical 10
```

## Options

```bash
python3 check_canon_rui_ink.py --help
```

## Exit Codes

- `0` OK
- `1` WARNING
- `2` CRITICAL
- `3` UNKNOWN

## Troubleshooting

- Connection error: verify host/IP and network route
- Parsing error: firmware/UI page may differ, inspect fetched HTML

## Security Notes

- Prefer read-only monitoring network path
- Avoid exposing printer UI outside trusted network
