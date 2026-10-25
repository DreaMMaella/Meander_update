# Инструкция по переписыванию истории для исправления авторства DreaMMaella

## Проблема

В репозитории `IILLUMINATION/meander-public` коммит `93b0818` от DreaMMaella имеет неправильный email `noreply@github.com`, из-за чего GitHub засчитывает его как "web-flow" вместо реального контрибьютора.

## Решение

Нужно переписать историю, заменив email на правильный: `273341448+DreaMMaella@users.noreply.github.com`

## Предупреждение ⚠️

- Это изменит SHA последних двух коммитов в main
- У репозитория есть 2 форка - их владельцам нужно будет сделать rebase
- Все открытые PR на базе старого main нужно будет обновить

## Шаги

### Вариант 1: Автоматический (рекомендуется)

Я подготовил скрипты для автоматического выполнения всех шагов:

**Linux/Mac:**
```bash
cd /path/to/meander-public
chmod +x rewrite_history.sh
./rewrite_history.sh
```

**Windows (PowerShell):**
```powershell
cd C:\path\to\meander-public
.\rewrite_history.ps1
```

Скрипт:
1. Создаст backup тег для возможности отката
2. Пересоздаст коммит 93b0818 с правильным email
3. Пересоздаст merge commit b58a892
4. Покажет сравнение старой и новой истории
5. Запросит подтверждение перед force-push
6. Выполнит безопасный force-push с `--force-with-lease`

### Вариант 2: Ручной

Если предпочитаете делать вручную:

```bash
# 1. Клонировать репозиторий (если ещё не клонирован)
git clone git@github.com:IILLUMINATION/meander-public.git
cd meander-public

# 2. Создать backup
git tag backup-before-rewrite-$(date +%Y%m%d-%H%M%S)

# 3. Checkout базовый коммит
git checkout 91e383acef5b9d7fbe5c281cd0b988d2ba4dfea2

# 4. Cherry-pick и исправление коммита
git cherry-pick 93b0818b8190a3898d9bb674d274cdc43627a999
export GIT_COMMITTER_NAME='DreaMMaella'
export GIT_COMMITTER_EMAIL='273341448+DreaMMaella@users.noreply.github.com'
git commit --amend --author="DreaMMaella <273341448+DreaMMaella@users.noreply.github.com>" --no-edit

# Запомнить новый SHA
NEW_COMMIT=$(git rev-parse HEAD)

# 5. Вернуться на базовый коммит
git checkout 91e383acef5b9d7fbe5c281cd0b988d2ba4dfea2

# 6. Создать merge commit
export GIT_COMMITTER_NAME='Иллюминат'
export GIT_COMMITTER_EMAIL='IILLUMINAT@outlook.com'
export GIT_AUTHOR_NAME='Иллюминат'
export GIT_AUTHOR_EMAIL='IILLUMINAT@outlook.com'
git merge --no-ff $NEW_COMMIT -m "Merge pull request #1 from DreaMMaella/feature/iillumination-updates

feat: добавлены новые функции от IILLUMINATION"

# 7. Проверить результат
git log HEAD --format="%H - %an <%ae> - %s" -3

# 8. Force-push (с защитой)
git push origin HEAD:main --force-with-lease=main:b58a8923e54931e6f44508eddea8da8369c968a9
```

## Результат

После выполнения:
- Старый коммит `93b0818` будет заменён на новый с правильным email
- Старый merge `b58a892` будет заменён на новый
- DreaMMaella появится в контрибьюторах вместо web-flow
- Backup тег позволит откатить изменения при необходимости

## Откат (если что-то пошло не так)

```bash
# Если нужно вернуться к старому состоянию
git push origin backup-before-rewrite-YYYYMMDD-HHMMSS:main --force
```

## После force-push

Нужно уведомить владельцев форков о необходимости обновления:

```bash
# Для владельцев форков
git fetch upstream
git rebase --onto upstream/main b58a892 your-branch
```

## Проверка

После выполнения проверьте контрибьюторов:
- GitHub API: https://api.github.com/repos/IILLUMINATION/meander-public/contributors
- Страница контрибьюторов: https://github.com/IILLUMINATION/meander-public/graphs/contributors

DreaMMaella должен появиться в списке с 1 коммитом, web-flow должен исчезнуть.

## Контакты

Если возникнут вопросы - пишите в Issues или напрямую.
