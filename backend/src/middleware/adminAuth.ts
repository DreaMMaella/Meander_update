import { Response, NextFunction } from 'express';
import { AuthRequest } from './auth';
import pool from '../config/database'; // Импортируем подключение к БД

const adminAuth = async (req: AuthRequest, res: Response, next: NextFunction) => {
  // 1. Проверяем, что пользователь вообще авторизован (authMiddleware отработал)
  if (!req.user || !req.user.id) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    // 2. Делаем запрос в БД, чтобы узнать АКТУАЛЬНУЮ роль
    // Не доверяем тому, что записано в токене, так как данные могли устареть
    const result = await pool.query(
        'SELECT role FROM profiles WHERE id = $1', 
        [req.user.id]
    );

    if (result.rows.length === 0) {
        return res.status(401).json({ error: 'User not found in DB' });
    }

    const currentRole = result.rows[0].role;

    // 3. Проверяем роль
    if (currentRole !== 'admin') {
      return res.status(403).json({ error: 'Access denied. Admins only.' });
    }

    // Если всё ок — пропускаем дальше
    next();

  } catch (error) {
      console.error("Admin Check Error:", error);
      return res.status(500).json({ error: "Server error checking admin rights" });
  }
};

export default adminAuth;