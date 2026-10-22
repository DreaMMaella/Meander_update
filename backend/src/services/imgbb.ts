import fs from 'fs/promises'; // Используем promises версию
import FormData from 'form-data';
import axios from 'axios';
import dotenv from 'dotenv';

dotenv.config();

const IMGBB_API_KEY = process.env.IMGBB_KEY;

export const uploadToImgbb = async (filePath: string): Promise<string> => {
    if (!IMGBB_API_KEY) {
        throw new Error("IMGBB_KEY is missing in .env");
    }

    try {
        // 1. АСИНХРОННОЕ чтение файла (не блокирует сервер)
        const imageBuffer = await fs.readFile(filePath);
        const base64Image = imageBuffer.toString('base64');

        // 2. Формируем данные
        const formData = new FormData();
        formData.append('image', base64Image);

        // 3. Отправляем запрос
        const response = await axios.post('https://api.imgbb.com/1/upload', formData, {
            params: {
                key: IMGBB_API_KEY,
            },
            headers: {
                ...formData.getHeaders(),
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            },
            maxBodyLength: Infinity,
            maxContentLength: Infinity,
        });

        if (response.data && response.data.data && response.data.data.url) {
            console.log("✅ Image uploaded to ImgBB:", response.data.data.url);
            return response.data.data.url;
        } else {
            console.error("ImgBB Response:", response.data);
            throw new Error("ImgBB response missing URL");
        }

    } catch (error: any) {
        console.error("❌ ImgBB Upload Error:", error.response?.data || error.message);
        throw new Error("Failed to upload image to ImgBB");
    }
};