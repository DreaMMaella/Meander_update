import {
    scanText,
    verdict,
    interestScore,
    qualityScore,
    type RuleSeverity,
} from './content_rules';

interface ModerationResult {
    approved: boolean;
    reason: string;
    isHardReject: boolean;
    qualityScore: number;
    /** Спорный текст, который правила не вправе отклонять сами — очередь ручной проверки. */
    needsReview: boolean;
    severity: RuleSeverity;
}

export const moderateQuestContent = async (title: string, description: string, contentSample: string): Promise<ModerationResult> => {
    const totalTextLen = (title + description + contentSample).length;
    if (totalTextLen < 50) {
        return {
            approved: false,
            isHardReject: true,
            reason: "Слишком мало контента. Квест должен содержать сюжет.",
            qualityScore: 0,
            needsReview: false,
            severity: 'medium'
        };
    }

    // Название, описание и текст игры проверяются каждый по своим правилам:
    // мат в витрине запрещён, внутри игры допустим.
    const hits = [
        ...scanText(title, 'title'),
        ...scanText(description, 'description'),
        // Игровой текст сканируем целиком, но с потолком: публикация не должна
        // зависеть от размера архива.
        ...scanText(contentSample.slice(0, 200_000), 'body'),
    ];
    const v = verdict(hits);

    return {
        approved: v.approved,
        isHardReject: v.isHardReject,
        reason: v.reason,
        qualityScore: qualityScore(title, description, contentSample),
        needsReview: v.needsReview,
        severity: v.severity
    };
};

export const moderateGameScript = async (scriptContent: string): Promise<ModerationResult> => {
    const forbidden = ["window.", "document.", "eval(", "XMLHttpRequest", "fetch("];
    for (const word of forbidden) {
        if (scriptContent.includes(word)) {
            return {
                approved: false, isHardReject: true, reason: `Запрещенный код: ${word}`,
                qualityScore: 0, needsReview: false, severity: 'high'
            };
        }
    }
    return {
        approved: true, isHardReject: false, reason: "Код безопасен",
        qualityScore: 100, needsReview: false, severity: 'low'
    };
};

export const moderateReview = async (text: string, allowAds: boolean = false): Promise<{
    approved: boolean;
    reason: string;
    severity: RuleSeverity;
    needsReview?: boolean;
}> => {
    if (!text || text.trim().length < 2) {
        return { approved: false, reason: "Отзыв слишком короткий", severity: 'low' };
    }

    const v = verdict(scanText(text, 'review', { allowAds }));
    // Отзыв не отклоняем из-за формальностей: спорное отдаём людям.
    return {
        approved: !v.isHardReject,
        reason: v.reason,
        severity: v.severity,
        needsReview: v.needsReview
    };
};

export const moderateWallPost = async (text: string, mediaUrls: string[] = []): Promise<{
    approved: boolean;
    reason: string;
    severity: RuleSeverity;
    interest_score: number;
    needsReview?: boolean;
}> => {
    if ((!text || text.trim().length < 2) && mediaUrls.length === 0) {
        return { approved: false, reason: "Пост слишком короткий", severity: 'low', interest_score: 0 };
    }

    // Только запрещёнка и спам-формы снимают пост; оффтоп — живёт.
    const v = verdict(scanText(text, 'post'));
    return {
        approved: !v.isHardReject,
        reason: v.reason,
        severity: v.severity,
        interest_score: interestScore(text, mediaUrls.length),
        needsReview: v.needsReview
    };
};
