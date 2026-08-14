import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SHOP_SKILL = REPO_ROOT / "skills" / "shop" / "SKILL.md"
BROWSER_FALLBACK = (
    REPO_ROOT / "skills" / "shop" / "references" / "browser-fallback.md"
)


class ShopBrowserFallbackContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.skill = SHOP_SKILL.read_text(encoding="utf-8")
        cls.fallback = BROWSER_FALLBACK.read_text(encoding="utf-8")

    def test_skill_routes_dynamic_cards_to_browser_fallback(self) -> None:
        self.assertIn("references/browser-fallback.md", self.skill)
        self.assertIn("выбора региона", self.skill)
        self.assertIn("выполнения JavaScript", self.skill)

    def test_search_remains_the_discovery_layer(self) -> None:
        self.assertIn("Не заменять им веб-поиск по всему каталогу", self.fallback)
        self.assertIn("1–2 финальных карточек", self.fallback)

    def test_verified_price_requires_visible_exact_variant(self) -> None:
        self.assertIn(
            "браузер одновременно показывает точный выбранный вариант и его цену",
            self.fallback,
        )
        for required_field in (
            "модель",
            "состояние",
            "память",
            "цвет",
            "SIM-версию",
            "комплект",
            "продавца",
        ):
            self.assertIn(required_field, self.fallback)

    def test_fallback_does_not_bypass_protections_or_mutate_purchase_state(self) -> None:
        self.assertIn("При CAPTCHA или запросе входа остановиться", self.fallback)
        self.assertIn("не обходить защиту", self.fallback)
        self.assertIn("Не добавлять товар в корзину", self.fallback)
        self.assertIn("не переходить к оформлению", self.fallback)

    def test_fallback_uses_isolated_local_chrome_without_claude_account(self) -> None:
        self.assertIn("browser_probe.mjs", self.fallback)
        self.assertIn("не требует claude.ai", self.fallback)
        self.assertIn("Chrome DevTools Protocol", self.fallback)
        self.assertIn("отдельный временный профиль", self.fallback)
        self.assertNotIn("claude --chrome", self.fallback)

    def test_unresolved_condition_or_marketplace_seller_cannot_be_recommended(self) -> None:
        self.assertIn("карточку с неподтверждённым состоянием", self.skill)
        self.assertIn("без установленного конкретного продавца", self.skill)
        self.assertIn("только в ограничениях поиска", self.skill)
        self.assertIn("наличие и регион либо написать «не подтверждено»", self.skill)


if __name__ == "__main__":
    unittest.main()
