# skills

Личные agent-скиллы, управляются через [Skills CLI](https://skills.sh/).

| Скилл | Что делает |
|---|---|
| `shop` | подбор и сравнение товаров на российских маркетплейсах (/shop) |
| `mac-check` | проверка здоровья, чистка и обслуживание macOS (/mac-check + еженедельный launchd) |
| `ventana-benchmark-gx` | обучение и ответы по иммуностейнеру VENTANA BenchMark GX |

## Установка (глобально)

```bash
npx skills add notreal13/skills -g -y
```

## Профиль покупателя для shop

Скилл `/shop` работает без профиля, но с ним удобнее: подставляются город, размер обуви и другие предпочтения. Скопируй шаблон и заполни под себя:

```bash
cp ~/.claude/skills/shop/profile.example.md ~/.claude/skills/shop/profile.md
```

## Лицензия

MIT — см. [LICENSE](LICENSE).
