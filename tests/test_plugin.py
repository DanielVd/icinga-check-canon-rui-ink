"""Offline end-to-end contract tests using a deterministic fake curl executable."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "check_canon_rui_ink.sh"

FAKE_CURL = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
from urllib.parse import urlsplit

args = sys.argv[1:]
scenario = os.environ.get("MOCK_SCENARIO", "ok")
log = Path(os.environ["MOCK_CAPTURE"])
with log.open("a", encoding="utf-8") as stream:
    stream.write(json.dumps(args) + "\n")

def option(name):
    return args[args.index(name) + 1]

url = args[-1]
path = urlsplit(url).path
headers = Path(option("-D"))
body = Path(option("-o"))
if "-c" in args:
    Path(option("-c")).write_text("cookie", encoding="utf-8")

if path == "/rui/sendpw.cgi":
    namae = next((arg[6:] for arg in args if arg.startswith("NAMAE@")), None)
    if not namae or Path(namae).read_text(encoding="utf-8") != "super-secret":
        sys.exit(40)
    if scenario == "login_http_error":
        sys.exit(22)
    response = (
        '<input type="hidden" name="SBID" value="session-secret">'
        if scenario != "login_missing_token" else "<html>no token</html>"
    )
elif path == "/rui/index.html":
    token = next((arg[5:] for arg in args if arg.startswith("SBID@")), None)
    if not token or Path(token).read_text(encoding="utf-8") != "session-secret":
        sys.exit(41)
    if scenario == "session_http_error":
        sys.exit(22)
    response = "<html>session established</html>"
elif path == "/rui/prninfo_data.cgi":
    if scenario == "ink_http_error":
        sys.exit(22)
    token = next((arg[5:] for arg in args if arg.startswith("SBID@")), None)
    if not token or Path(token).read_text(encoding="utf-8") != "session-secret":
        sys.exit(42)
    response = {
        "ok": "<INKREST0>0,6,0</INKREST0><INKREST1>1,2,0</INKREST1>",
        "warning": "<INKREST0>0,8,1</INKREST0><INKREST1>1,0,0</INKREST1>",
        "critical": "<INKREST0>0,8,1</INKREST0><INKREST1>1,10,2</INKREST1>",
        "unknown_ink": "<INKREST0>0,11,3</INKREST0>",
        "unreadable_ok": "<INKREST0>0,11,0</INKREST0>",
        "invalid_session": "<SES_ERR_URL>/login</SES_ERR_URL>",
        "missing": "<html>not a printer payload</html>",
        "malformed": "<INKREST0>0,6</INKREST0>",
        "mismatched": "<INKREST0>0,6,0</INKREST1>",
        "unknown_status": "<INKREST0>0,6,9</INKREST0>",
        "duplicate": "<INKREST0>0,6,0</INKREST0><INKREST1>0,4,0</INKREST1>",
        "other_color": "<INKREST3>3,5,0</INKREST3>",
    }.get(scenario, "<INKREST0>0,6,0</INKREST0>")
else:
    response = "<html>awake</html>"

headers.write_text("HTTP/1.1 200 OK\n", encoding="utf-8")
body.write_text(response, encoding="utf-8")
'''

class PluginTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.directory = Path(self.workspace.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.fake_curl = self.bin / "curl"
        self.fake_curl.write_text(FAKE_CURL, encoding="utf-8")
        self.fake_curl.chmod(0o755)
        self.log = self.directory / "requests.jsonl"

    def run_plugin(self, scenario="ok", **overrides):
        env = dict(os.environ)
        env.update({
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "BASE": "https://printer.example.test",
            "NAMAE": "super-secret",
            "LOGIN_RETRIES": "3",
            "WAKEUP_DELAY_SECONDS": "0",
            "MOCK_SCENARIO": scenario,
            "MOCK_CAPTURE": str(self.log),
            "TMPDIR": str(self.directory),
        })
        env.update(overrides)
        result = subprocess.run(
            ["bash", str(PLUGIN)], env=env, text=True,
            capture_output=True, timeout=10, check=False,
        )
        self.assertNotIn("super-secret", result.stdout + result.stderr)
        self.assertNotIn("session-secret", result.stdout + result.stderr)
        return result

    def requests(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_ok_and_perfdata(self):
        result = self.run_plugin()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "[OK] Color:40% Black:80% | color=40%;;;0;100 black=80%;;;0;100")

    def test_warning(self):
        result = self.run_plugin("warning")
        self.assertEqual(result.returncode, 1)
        self.assertIn("[WARNING] Color:20%", result.stdout)

    def test_critical_takes_precedence(self):
        result = self.run_plugin("critical")
        self.assertEqual(result.returncode, 2)
        self.assertIn("[CRITICAL]", result.stdout)

    def test_unknown_ink_is_warning_without_fake_perfdata(self):
        result = self.run_plugin("unknown_ink")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.strip(), "[WARNING] Color:?%")

    def test_missing_authentication(self):
        result = self.run_plugin(NAMAE="")
        self.assertEqual(result.returncode, 3)
        self.assertIn("NAMAE not set", result.stdout)

    def test_login_retries_without_exposing_response(self):
        result = self.run_plugin("login_missing_token")
        self.assertEqual(result.returncode, 3)
        self.assertEqual(sum("/rui/sendpw.cgi" in request[-1] for request in self.requests()), 3)

    def test_login_http_error(self):
        result = self.run_plugin("login_http_error")
        self.assertEqual(result.returncode, 3)

    def test_session_http_error(self):
        result = self.run_plugin("session_http_error")
        self.assertEqual(result.returncode, 3)

    def test_ink_http_error(self):
        result = self.run_plugin("ink_http_error")
        self.assertEqual(result.returncode, 3)

    def test_invalid_session(self):
        result = self.run_plugin("invalid_session")
        self.assertEqual(result.returncode, 3)
        self.assertIn("session expired", result.stdout)

    def test_missing_or_malformed_ink_data(self):
        for scenario in ("missing", "malformed", "mismatched", "unknown_status", "duplicate", "unreadable_ok"):
            with self.subTest(scenario=scenario):
                result = self.run_plugin(scenario)
                self.assertEqual(result.returncode, 3, result.stdout)

    def test_unknown_ink_type_has_unique_perfdata(self):
        result = self.run_plugin("other_color")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Ink3:50% | ink3=50%;;;0;100", result.stdout)

    def test_tls_verification_default_and_explicit_opt_out(self):
        self.run_plugin()
        self.assertFalse(any("--insecure" in request for request in self.requests()))
        self.log.unlink()
        self.run_plugin(CANON_INSECURE_TLS="1")
        self.assertTrue(any("--insecure" in request for request in self.requests()))

    def test_secret_never_appears_in_curl_argv(self):
        self.run_plugin()
        args = json.dumps(self.requests())
        self.assertNotIn("super-secret", args)
        self.assertNotIn("session-secret", args)
        self.assertIn("NAMAE@", args)
        self.assertIn("SBID@", args)

    def test_no_redirect_following(self):
        self.run_plugin()
        self.assertFalse(any("--location" in request or "-L" in request for request in self.requests()))

if __name__ == "__main__":
    unittest.main()
