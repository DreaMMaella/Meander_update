import { Server as SocketIOServer, Socket } from 'socket.io';
import { Server as HttpServer } from 'http';
import jwt from 'jsonwebtoken';

let io: SocketIOServer | null = null;

export const initSocket = (server: HttpServer): SocketIOServer => {
  io = new SocketIOServer(server, {
    cors: {
      origin: '*', // Adjust for production if needed, matching express cors
      methods: ['GET', 'POST'],
    },
  });

  io.use((socket, next) => {
    const token = socket.handshake.auth?.token || socket.handshake.query?.token;
    if (!token) {
      return next(new Error('Authentication error: No token provided'));
    }
    // Без секрета проверять подпись нечем. Фоллбэк 'fallback_secret' означал,
    // что при пустом JWT_SECRET любой, кто знает это слово, получает сокет
    // любого пользователя.
    const jwtSecret = process.env.JWT_SECRET;
    if (!jwtSecret) {
      console.error('[socket] JWT_SECRET is not set — realtime is disabled');
      return next(new Error('Authentication error: Server is not configured'));
    }

    try {
      const decoded = jwt.verify(token, jwtSecret, { algorithms: ['HS256'] }) as { id: string };
      socket.data.userId = decoded.id;
      next();
    } catch (err) {
      next(new Error('Authentication error: Invalid token'));
    }
  });

  io.on('connection', (socket: Socket) => {
    const userId = socket.data.userId;
    console.log(`[Socket] User connected: ${userId}`);

    // Join personal room for personal notifications
    socket.join(`user_${userId}`);

    socket.on('join_post', (postId: string) => {
      if (postId && typeof postId === 'string') {
        socket.join(`post_${postId}`);
        console.log(`[Socket] User ${userId} joined post_${postId}`);
      }
    });

    socket.on('leave_post', (postId: string) => {
      if (postId && typeof postId === 'string') {
        socket.leave(`post_${postId}`);
        console.log(`[Socket] User ${userId} left post_${postId}`);
      }
    });

    socket.on('disconnect', () => {
      console.log(`[Socket] User disconnected: ${userId}`);
    });
  });

  return io;
};

export const getIO = (): SocketIOServer => {
  if (!io) {
    throw new Error('Socket.io not initialized!');
  }
  return io;
};
