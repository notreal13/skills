import json
import os
import re
import subprocess
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PROBE = REPO_ROOT / "skills" / "shop" / "scripts" / "browser_probe.mjs"
CASE_PATH = Path(__file__).parent / "cases" / "iphone_dynamic_browser.json"


@unittest.skipUnless(
    os.environ.get("SHOP_CHROME_LIVE_EVAL") == "1",
    "set SHOP_CHROME_LIVE_EVAL=1 to run local Chrome against live shop cards",
)
class ShopIPhoneDynamicBrowserEval(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.case = json.loads(CASE_PATH.read_text(encoding="utf-8"))

    def run_probe(self, store: str) -> dict:
        probe = next(item for item in self.case["browser_probes"] if item["store"] == store)
        command = [
            "node",
            str(PROBE),
            "--url",
            probe["url"],
            "--wait-ms",
            "3500",
            "--text-limit",
            "12000",
        ]
        for click in probe["clicks"]:
            command.extend(["--click", click])
        completed = subprocess.run(
            command,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            timeout=90,
            check=False,
        )
        output = completed.stdout or completed.stderr
        self.assertTrue(output, "browser probe returned no JSON")
        return json.loads(output)

    def test_fixed_reads_price_after_exact_variant_selection(self) -> None:
        result = self.run_probe("Fixed.one")

        self.assertTrue(result["ok"], result)
        self.assertFalse(result["challenge"])
        self.assertFalse(result["blocked"])
        self.assertTrue(all(action["found"] for action in result["actions"]))
        selected_price = re.search(r"Очистить\s+(\d[\d\s]+₽)", result["visibleText"])
        self.assertIsNotNone(selected_price, result)
        self.assertIn(selected_price.group(1).replace("\u00a0", " "), result["prices"])
        selected = " ".join(control["text"] for control in result["selectedControls"])
        self.assertIn("Чёрный", selected)
        self.assertIn("128 Гб", selected)

    def test_dns_403_is_never_reported_as_a_verified_price(self) -> None:
        result = self.run_probe("DNS")

        if result["blocked"]:
            self.assertFalse(result["ok"])
            self.assertEqual(result["prices"], [])
        else:
            self.assertTrue(result["ok"], result)
            self.assertIn("iPhone 16 Plus", result["visibleText"])
            self.assertTrue(result["prices"], result)


if __name__ == "__main__":
    unittest.main()
