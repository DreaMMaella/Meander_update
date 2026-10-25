#!/bin/bash
# Скрипт для переписывания истории репозитория IILLUMINATION/meander-public
# Исправляет email DreaMMaella с noreply@github.com на правильный 273341448+DreaMMaella@users.noreply.github.com

set -e

echo "=== Начало переписывания истории ==="

# 1. Создать backup тег
BACKUP_TAG="backup-before-rewrite-$(date +%Y%m%d-%H%M%S)"
git tag "$BACKUP_TAG"
echo "✓ Создан backup тег: $BACKUP_TAG"

# 2. Checkout базовый коммит
git checkout 91e383acef5b9d7fbe5c281cd0b988d2ba4dfea2
echo "✓ Checkout базового коммита 91e383a"

# 3. Cherry-pick и исправление коммита 93b0818
git cherry-pick 93b0818b8190a3898d9bb674d274cdc43627a999

export GIT_COMMITTER_NAME='DreaMMaella'
export GIT_COMMITTER_EMAIL='273341448+DreaMMaella@users.noreply.github.com'

git commit --amend --author="DreaMMaella <273341448+DreaMMaella@users.noreply.github.com>" --no-edit

NEW_COMMIT=$(git rev-parse HEAD)
echo "✓ Создан исправленный коммит: $NEW_COMMIT"

# 4. Вернуться на базовый коммит для создания merge
git checkout 91e383acef5b9d7fbe5c281cd0b988d2ba4dfea2

# 5. Создать merge commit
export GIT_COMMITTER_NAME='Иллюминат'
export GIT_COMMITTER_EMAIL='IILLUMINAT@outlook.com'
export GIT_AUTHOR_NAME='Иллюминат'
export GIT_AUTHOR_EMAIL='IILLUMINAT@outlook.com'

git merge --no-ff "$NEW_COMMIT" -m "Merge pull request #1 from DreaMMaella/feature/iillumination-updates

feat: добавлены новые функции от IILLUMINATION"

NEW_MERGE=$(git rev-parse HEAD)
echo "✓ Создан новый merge commit: $NEW_MERGE"

# 6. Показать разницу
echo ""
echo "=== Сравнение старой и новой истории ==="
echo "Старый merge commit: b58a892 (будет заменён)"
echo "Новый merge commit:  $NEW_MERGE"
echo ""
echo "Старая история:"
git log b58a8923e54931e6f44508eddea8da8369c968a9 --format="%H - %an <%ae> - %s" -2
echo ""
echo "Новая история:"
git log HEAD --format="%H - %an <%ae> - %s" -2
echo ""

# 7. Спросить подтверждение
read -p "Выполнить force-push в main? (yes/no): " CONFIRM

if [ "$CONFIRM" = "yes" ]; then
    echo "Выполняю force-push..."
    git push origin HEAD:main --force-with-lease=main:b58a8923e54931e6f44508eddea8da8369c968a9
    echo "✓ Force-push выполнен успешно!"
    echo ""
    echo "=== История успешно переписана! ==="
    echo "DreaMMaella теперь будет в контрибьюторах с правильным email."
    echo ""
    echo "Backup тег: $BACKUP_TAG"
    echo "Чтобы откатить изменения (если что-то пошло не так):"
    echo "  git push origin $BACKUP_TAG:main --force"
else
    echo "Отменено."
    echo "Для отката на текущее состояние:"
    echo "  git checkout main"
    echo "Backup тег сохранён: $BACKUP_TAG"
fi
