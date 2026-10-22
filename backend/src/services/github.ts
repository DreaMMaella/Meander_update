import { Octokit } from 'octokit';
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';

dotenv.config();

const octokit = new Octokit({
  auth: process.env.GITHUB_TOKEN,
});

const OWNER = process.env.GITHUB_OWNER!;
const REPO = process.env.GITHUB_REPO!;

/**
 * Создает или обновляет релиз для конкретного квеста.
 * Возвращает release_id.
 */
async function getOrCreateQuestRelease(questId: string, questTitle: string, version: string) {
    // Убираем спецсимволы из названия тега
    const tagName = `quest-${questId.replace(/[^a-zA-Z0-9-_]/g, '')}`;
    const releaseName = `${questTitle} (v${version})`;

    try {
        const release = await octokit.rest.repos.getReleaseByTag({
            owner: OWNER,
            repo: REPO,
            tag: tagName,
        });
        
        // Обновляем имя релиза
        await octokit.rest.repos.updateRelease({
            owner: OWNER,
            repo: REPO,
            release_id: release.data.id,
            name: releaseName,
            body: `Files for quest: ${questTitle}\nID: ${questId}`,
        });

        return release.data.id;
    } catch (e: any) {
        if (e.status === 404) {
            console.log(`Creating new release for quest: ${questTitle}`);
            const newRelease = await octokit.rest.repos.createRelease({
                owner: OWNER,
                repo: REPO,
                tag_name: tagName,
                name: releaseName,
                body: `Files for quest: ${questTitle}\nID: ${questId}`,
                draft: false,
                prerelease: false,
            });
            return newRelease.data.id;
        }
        throw e;
    }
}

/**
 * Загружает файл в релиз квеста.
 * Гарантирует уникальное имя и очищает старые версии.
 */
export const uploadToQuestRelease = async (
    questId: string, 
    questTitle: string, 
    version: string,
    filePath: string, 
    baseFileName: string
): Promise<string> => {
  try {
    const releaseId = await getOrCreateQuestRelease(questId, questTitle, version);
    const fileData = fs.readFileSync(filePath);
    
    const ext = path.extname(baseFileName);
    const nameWithoutExt = path.basename(baseFileName, ext); // например "cover" или "screenshot_1"
    
    // Генерируем уникальное имя с timestamp, чтобы избежать already_exists
    const uniqueFileName = `${nameWithoutExt}_${Date.now()}${ext}`;

    // 1. Очистка старых файлов (не блокирует поток, но ждем завершения для надежности)
    try {
        const assets = await octokit.rest.repos.listReleaseAssets({
            owner: OWNER,
            repo: REPO,
            release_id: releaseId,
        });

        // Ищем файлы, которые начинаются так же (например, старые версии этого скриншота)
        // Исправлена ошибка типов: (a: any)
        const oldAssets = assets.data.filter((a: any) => a.name.startsWith(nameWithoutExt) && a.name.endsWith(ext));
        
        // Удаляем старые файлы параллельно и ЖДЕМ завершения
        if (oldAssets.length > 0) {
            console.log(`Cleaning up ${oldAssets.length} old assets for ${nameWithoutExt}...`);
            // Исправлены ошибки типов: (asset: any) и (err: any)
            await Promise.all(oldAssets.map((asset: any) => 
                octokit.rest.repos.deleteReleaseAsset({
                    owner: OWNER,
                    repo: REPO,
                    asset_id: asset.id
                }).catch((err: any) => console.warn(`Failed to delete asset ${asset.name}:`, err.message))
            ));
        }
    } catch (cleanupError) {
        console.warn("Asset cleanup warning (non-critical):", cleanupError);
    }

    console.log(`Uploading ${uniqueFileName} to GitHub Release ${questId}...`);

    // 2. Загружаем новый файл
    const upload = await octokit.rest.repos.uploadReleaseAsset({
      owner: OWNER,
      repo: REPO,
      release_id: releaseId,
      name: uniqueFileName,
      data: fileData as unknown as string,
    });

    return upload.data.browser_download_url;

  } catch (error: any) {
    console.error('GitHub Upload Error Details:', error.response?.data || error.message);
    
    // Если всё-таки возникла коллизия имен (422 already_exists)
    if (error.status === 422 && error.response?.data?.code === 'already_exists') {
        console.log('File name collision detected. Retrying with new random name...');
        // Добавляем случайное число и пробуем снова
        const retryName = `${path.basename(baseFileName, path.extname(baseFileName))}_retry_${Math.floor(Math.random() * 10000)}${path.extname(baseFileName)}`;
        return uploadToQuestRelease(questId, questTitle, version, filePath, retryName);
    }

    throw new Error(`GitHub Upload Failed: ${error.message}`); 
  }
};