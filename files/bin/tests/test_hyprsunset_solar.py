#!/usr/bin/env python3
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "hyprsunset-solar"


class HyprsunsetSolar(unittest.TestCase):
    def test_writes_sunrise_sunset_profiles(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            loc = tmp_path / "weather.json"
            conf = tmp_path / "hyprsunset.conf"
            loc.write_text(
                '{"name":"Hamburg","latitude":53.55073,"longitude":9.99302}\n',
                encoding="utf-8",
            )
            env = os.environ.copy()
            env["HYPRSUNSET_CONF"] = str(conf)
            env["OMARCHY_WEATHER_LOCATION"] = str(loc)
            env["HYPRSUNSET_SOLAR_UNIT_DIR"] = str(tmp_path)
            env["HYPRSUNSET_SOLAR_SKIP_DAEMON"] = "1"
            proc = subprocess.run(
                [str(SCRIPT)],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr or proc.stdout)
            text = conf.read_text(encoding="utf-8")
            self.assertRegex(text, r"temperature = 6500\n\s*identity = true")
            self.assertIn("temperature = 4000", text)
            self.assertRegex(text, r"time = \d{2}:\d{2}")
            self.assertIn("off ", proc.stdout)
            self.assertIn("on ", proc.stdout)
            self.assertFalse(
                (tmp_path / "hyprsunset-solar-sunrise.timer").exists(),
                "SKIP_DAEMON must not write systemd units",
            )

    def test_apply_and_resume_hooks_exist(self):
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("hyprctl hyprsunset reset", text)
        self.assertIn("nightlight refresh", text)
        self.assertIn("watch-resume)", text)
        self.assertIn("PrepareForSleep", text)


if __name__ == "__main__":
    unittest.main()
