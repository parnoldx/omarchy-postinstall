#!/usr/bin/env python3
import subprocess
import unittest
from pathlib import Path

BRIDGE = Path(__file__).resolve().parents[1] / "vault-bridge"


class VaultBridgeSelftest(unittest.TestCase):
    def test_crypto_roundtrip(self):
        proc = subprocess.run(
            ["python3", str(BRIDGE), "selftest"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("selftest ok", proc.stdout)


if __name__ == "__main__":
    unittest.main()
