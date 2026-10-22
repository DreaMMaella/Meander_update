import pool from '../config/database';
import { awardAchievement } from './achievements';

const checkUserAchievements = async (userId: string) => {
    try {
        // publisher_debut — first published quest
        const pubRes = await pool.query(
            "SELECT COUNT(*) FROM quests WHERE author_id = $1 AND status = 'published'",
            [userId]
        );
        if (parseInt(pubRes.rows[0].count) >= 1) {
            await awardAchievement(userId, 'publisher_debut');
        }

        // generous — 20 likes given
        const likesRes = await pool.query(
            'SELECT COUNT(*) FROM quest_votes WHERE user_id = $1 AND is_like = TRUE',
            [userId]
        );
        if (parseInt(likesRes.rows[0].count) >= 20) {
            await awardAchievement(userId, 'generous');
        }

        // first_step — at least 1 download
        const dlRes = await pool.query(
            'SELECT COUNT(*) FROM quest_downloads WHERE user_id = $1',
            [userId]
        );
        const dlCount = parseInt(dlRes.rows[0].count);
        if (dlCount >= 1) {
            await awardAchievement(userId, 'first_step');
        }

        // bookworm — 10 downloads
        if (dlCount >= 10) {
            await awardAchievement(userId, 'bookworm');
        }

        // library_keeper — 50 downloads
        if (dlCount >= 50) {
            await awardAchievement(userId, 'library_keeper');
        }

        // critic_bronze — at least 1 review
        const reviewRes = await pool.query(
            'SELECT COUNT(*) FROM reviews WHERE author_id = $1',
            [userId]
        );
        if (parseInt(reviewRes.rows[0].count) >= 1) {
            await awardAchievement(userId, 'critic_bronze');
        }
    } catch (e) {
        console.error(`Error checking achievements for user ${userId}:`, e);
    }
};

export const startAchievementChecker = (intervalMs: number = 10 * 60 * 1000) => {
    console.log(`🏆 Achievement checker started (every ${intervalMs / 60000} min)`);

    setInterval(async () => {
        try {
            const usersRes = await pool.query('SELECT id FROM profiles');
            const userIds: string[] = usersRes.rows.map((r: { id: string }) => r.id);

            for (const userId of userIds) {
                await checkUserAchievements(userId);
            }

            console.log(`✅ Achievement check completed for ${userIds.length} users`);
        } catch (e) {
            console.error('Error in achievement checker cycle:', e);
        }
    }, intervalMs);
};
