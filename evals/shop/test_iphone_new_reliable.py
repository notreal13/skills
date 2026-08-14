import json
import os
import unittest
from pathlib import Path

from runner import run_case


CASE_PATH = Path(__file__).parent / "cases" / "iphone_new_reliable.json"


@unittest.skipUnless(
    os.environ.get("SHOP_LIVE_EVAL") == "1",
    "set SHOP_LIVE_EVAL=1 to run the live Codex and web-search eval",
)
class ShopIPhoneLiveEval(unittest.TestCase):
    def test_recommends_only_new_iphone_from_reliable_seller(self) -> None:
        result = run_case(CASE_PATH)

        self.assertTrue(
            result["verdict"]["passed"],
            json.dumps(result, ensure_ascii=False, indent=2),
        )


if __name__ == "__main__":
    unittest.main()
