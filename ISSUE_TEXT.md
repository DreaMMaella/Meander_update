# 🐛 DreaMMaella не отображается в контрибьюторах (показывается web-flow)

## Проблема

В контрибьюторах репозитория `IILLUMINATION/meander-public` пользователь @DreaMMaella не отображается, вместо него показывается "web-flow" с 1 коммитом.

**Причина:** Коммит `93b0818` от DreaMMaella имеет неправильный email `noreply@github.com`, который GitHub не может привязать к аккаунту.

**GitHub API подтверждает:**
```
https://api.github.com/repos/IILLUMINATION/meander-public/contributors
```
Показывает:
- IILLUMINATION: 5 коммитов ✅
- web-flow: 1 коммит ❌ (должен быть DreaMMaella)

## Решение

Я подготовил **автоматические скрипты и подробные инструкции** для исправления:

📁 Все необходимые файлы находятся здесь:
**https://github.com/DreaMMaella/Meander_update/tree/main**

### Файлы:
1. **`SUMMARY.md`** - краткая сводка (начни с этого!)
2. **`REWRITE_INSTRUCTIONS.md`** - подробная пошаговая инструкция
3. **`rewrite_history.sh`** - готовый скрипт для Linux/Mac
4. **`rewrite_history.ps1`** - готовый скрипт для Windows
5. **`new_commits_info.txt`** - информация о новых коммитах

## Что нужно сделать

**Быстрый старт (Linux/Mac):**
```bash
cd /path/to/meander-public
curl -O https://raw.githubusercontent.com/DreaMMaella/Meander_update/main/rewrite_history.sh
chmod +x rewrite_history.sh
./rewrite_history.sh
```

**Быстрый старт (Windows PowerShell):**
```powershell
cd C:\path\to\meander-public
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/DreaMMaella/Meander_update/main/rewrite_history.ps1" -OutFile "rewrite_history.ps1"
.\rewrite_history.ps1
```

Скрипт:
- ✅ Автоматически создаст backup
- ✅ Исправит email в коммите 93b0818
- ✅ Пересоздаст merge commit b58a892
- ✅ Покажет diff до/после
- ✅ Запросит подтверждение перед push
- ✅ Выполнит безопасный force-push с `--force-with-lease`

## Результат

После выполнения:
- ✅ DreaMMaella появится в контрибьюторах
- ✅ "web-flow" исчезнет
- ✅ История останется чистой

## Безопасность

- Backup создаётся автоматически (можно откатить)
- Используется `--force-with-lease` (безопаснее обычного force)
- Можно сначала посмотреть diff, потом решить

## Для форков

После force-push владельцам 2 форков нужно будет обновиться:
```bash
git fetch upstream
git rebase --onto upstream/main b58a892 your-branch
```

---

**P.S.** Я со своей стороны уже всё подготовил. Force-push может выполнить только владелец репозитория (IILLUMINATION), так как нужны права на запись в main.

Спасибо! 🙏
