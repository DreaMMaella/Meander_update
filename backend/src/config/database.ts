import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

// Создаем пул соединений с базой данных
// Ограничиваем max connections, чтобы не перегрузить сервер при спаме
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10, // Максимум 10 одновременных подключений (важно для 1GB RAM)
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Проверяем соединение при запуске
pool.connect((err, client, release) => {
  if (err) {
    return console.error('❌ Error acquiring client', err.stack);
  }
  console.log('🐘 Connected to PostgreSQL database!');
  release();
});

export default pool;