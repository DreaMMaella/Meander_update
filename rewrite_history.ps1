# Скрипт для переписывания истории репозитория IILLUMINATION/meander-public
# Исправляет email DreaMMaella с noreply@github.com на правильный 273341448+DreaMMaella@users.noreply.github.com

$ErrorActionPreference = "Stop"

Write-Host "=== Начало переписывания истории ===" -ForegroundColor Green

# 1. Создать backup тег
$backupTag = "backup-before-rewrite-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
git tag $backupTag
Write-Host "✓ Создан backup тег: $backupTag" -ForegroundColor Green

# 2. Checkout базовый коммит
git checkout 91e383acef5b9d7fbe5c281cd0b988d2ba4dfea2
Write-Host "✓ Checkout базового коммита 91e383a" -ForegroundColor Green

# 3. Cherry-pick и исправление коммита 93b0818
git cherry-pick 93b0818b8190a3898d9bb674d274cdc43627a999

$env:GIT_COMMITTER_NAME = 'DreaMMaella'
$env:GIT_COMMITTER_EMAIL = '273341448+DreaMMaella@users.noreply.github.com'

git commit --amend --author="DreaMMaella <273341448+DreaMMaella@users.noreply.github.com>" --no-edit

$newCommit = git rev-parse HEAD
Write-Host "✓ Создан исправленный коммит: $newCommit" -ForegroundColor Green

# 4. Вернуться на базовый коммит для создания merge
git checkout 91e383acef5b9d7fbe5c281cd0b988d2ba4dfea2

# 5. Создать merge commit
$env:GIT_COMMITTER_NAME = 'Иллюминат'
$env:GIT_COMMITTER_EMAIL = 'IILLUMINAT@outlook.com'
$env:GIT_AUTHOR_NAME = 'Иллюминат'
$env:GIT_AUTHOR_EMAIL = 'IILLUMINAT@outlook.com'

git merge --no-ff $newCommit -m "Merge pull request #1 from DreaMMaella/feature/iillumination-updates`n`nfeat: добавлены новые функции от IILLUMINATION"

$newMerge = git rev-parse HEAD
Write-Host "✓ Создан новый merge commit: $newMerge" -ForegroundColor Green

# 6. Показать разницу
Write-Host ""
Write-Host "=== Сравнение старой и новой истории ===" -ForegroundColor Cyan
Write-Host "Старый merge commit: b58a892 (будет заменён)"
Write-Host "Новый merge commit:  $newMerge"
Write-Host ""
Write-Host "Старая история:" -ForegroundColor Yellow
git log b58a8923e54931e6f44508eddea8da8369c968a9 --format="%H - %an <%ae> - %s" -2
Write-Host ""
Write-Host "Новая история:" -ForegroundColor Green
git log HEAD --format="%H - %an <%ae> - %s" -2
Write-Host ""

# 7. Спросить подтверждение
$confirm = Read-Host "Выполнить force-push в main? (yes/no)"

if ($confirm -eq "yes") {
    Write-Host "Выполняю force-push..." -ForegroundColor Yellow
    git push origin HEAD:main --force-with-lease=main:b58a8923e54931e6f44508eddea8da8369c968a9
    Write-Host "✓ Force-push выполнен успешно!" -ForegroundColor Green
    Write-Host ""
    Write-Host "=== История успешно переписана! ===" -ForegroundColor Green
    Write-Host "DreaMMaella теперь будет в контрибьюторах с правильным email."
    Write-Host ""
    Write-Host "Backup тег: $backupTag" -ForegroundColor Cyan
    Write-Host "Чтобы откатить изменения (если что-то пошло не так):"
    Write-Host "  git push origin ${backupTag}:main --force" -ForegroundColor Yellow
} else {
    Write-Host "Отменено." -ForegroundColor Red
    Write-Host "Для отката на текущее состояние:"
    Write-Host "  git checkout main"
    Write-Host "Backup тег сохранён: $backupTag" -ForegroundColor Cyan
}
