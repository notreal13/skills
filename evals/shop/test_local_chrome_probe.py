import json
import os
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PROBE = REPO_ROOT / "skills" / "shop" / "scripts" / "browser_probe.mjs"
FIXTURE = Path(__file__).parent / "fixtures" / "dynamic_product.html"


class ShopLocalChromeProbeContract(unittest.TestCase):
    def test_probe_has_no_external_javascript_dependencies(self) -> None:
        source = PROBE.read_text(encoding="utf-8")

        self.assertIn('from "node:child_process"', source)
        self.assertIn("--remote-debugging-port=0", source)
        self.assertIn("shop-chrome-", source)
        self.assertNotIn('from "playwright"', source)
        self.assertNotIn('from "puppeteer"', source)


@unittest.skipUnless(
    os.environ.get("SHOP_CHROME_EVAL") == "1",
    "set SHOP_CHROME_EVAL=1 to run Chrome against a local dynamic fixture",
)
class ShopLocalChromeProbeIntegration(unittest.TestCase):
    def test_clicks_variants_and_reads_javascript_price(self) -> None:
        completed = subprocess.run(
            [
                "node",
                str(PROBE),
                "--url",
                FIXTURE.resolve().as_uri(),
                "--click",
                "Чёрный",
                "--click",
                "128 ГБ",
                "--wait-ms",
                "100",
            ],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads(completed.stdout)
        self.assertTrue(result["ok"])
        self.assertTrue(result["isolatedProfile"])
        self.assertFalse(result["challenge"])
        self.assertFalse(result["blocked"])
        self.assertTrue(all(action["found"] for action in result["actions"]))
        self.assertIn("Чёрный, 128 ГБ", result["visibleText"])
        self.assertIn("82 600 ₽", result["prices"])


if __name__ == "__main__":
    unittest.main()
