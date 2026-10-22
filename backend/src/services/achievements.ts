// backend/src/services/achievements.ts

import pool from '../config/database';

export const awardAchievement = async (userId: string, achievementId: string) => {
    try {
        const result = await pool.query(
            `INSERT INTO user_achievements (user_id, achievement_id) 
             VALUES ($1, $2) 
             ON CONFLICT (user_id, achievement_id) DO NOTHING
             RETURNING *`,
            [userId, achievementId]
        );

        if (result.rows.length > 0) {
            console.log(`🏆 Achievement unlocked for ${userId}: ${achievementId}`);
            return true;
        }
        return false; 
    } catch (e) {
        console.error(`Error awarding achievement ${achievementId}:`, e);
        return false;
    }
};