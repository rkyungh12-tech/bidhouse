require('dotenv').config();
const express = require('express');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');
const path = require('path');
const db = require('./models/database');
const authRoutes = require('./routes/auth');
const auctionRoutes = require('./routes/auctions');
const { configureRedisAdapter } = require('./infra/redisAdapter');
const JWT_SECRET = process.env.JWT_SECRET;
const { scheduleExpiredAuctions, processAuctionCloseQueue } = require('./infra/auctionScheduler');

if (!JWT_SECRET) throw new Error('JWT_SECRET environment variable is required.');

const app = express();
const server = http.createServer(app);

const FRONTEND_ORIGINS = (process.env.FRONTEND_ORIGIN || 'https://www.bidhouse.cloud')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

function allowFrontendOrigin(origin, callback) {
  // Requests without an Origin header include health checks and server-to-server calls.
  if (!origin || FRONTEND_ORIGINS.includes(origin)) return callback(null, true);
  return callback(new Error('Not allowed by CORS'));
}

const io = new Server(server, {
  cors: {
    origin: allowFrontendOrigin,
    methods: ['GET', 'POST'],
    credentials: true
  }
});

// 👇 이렇게 exposedHeaders 옵션을 추가해 주세요!
app.use(cors({ 
  origin: allowFrontendOrigin, 
  credentials: true,
  methods: ['GET', 'POST', 'HEAD', 'DELETE'],
  exposedHeaders: ['Server', 'x-envoy-upstream-service-time'] // 🚀 프론트엔드에서 읽을 수 있게 허락!
}));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

app.use('/api/auth', authRoutes);
app.use('/api/auctions', auctionRoutes);

// 👇 여기에 추가하세요!
app.get('/api/region', (req, res) => {
  res.json({ region: process.env.APP_REGION || 'unknown' });
});

app.get('/health', async (req, res) => {
  try {
    await db.ping();
    res.status(200).json({ status: 'ok', database: 'connected' });
  } catch (error) {
    res.status(503).json({ status: 'error', database: 'disconnected' });
  }
});

app.get('*', (req, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));

const chatCooldown = {}; // { socketId: lastMessageTime }
// ── Socket.IO ──────────────────────────────────────────────
io.on('connection', (socket) => {

  // 경매 방 입장
  socket.on('join_auction', async (auctionId) => {
    socket.join(`auction_${auctionId}`);
    try {
      const auction = await db.get('SELECT * FROM auctions WHERE id = ?', [auctionId]);
      if (auction) socket.emit('auction_state', auction);
    } catch (error) {
      console.error('경매 상태 조회 오류:', error);
    }
  });

  // 입찰
  socket.on('place_bid', async ({ auctionId, amount, token }) => {
  try {
    let decoded;
    const jwt = require('jsonwebtoken');
    try {
      decoded = jwt.verify(token, JWT_SECRET);
    } catch {
      const { CognitoJwtVerifier } = require('aws-jwt-verify');
      const verifier = CognitoJwtVerifier.create({
        userPoolId: process.env.COGNITO_USER_POOL_ID,
        tokenUse: 'id',
        clientId: process.env.COGNITO_CLIENT_ID,
      });
      const payload = await verifier.verify(token);
      decoded = {
        userId: payload['custom:userId'] || payload.sub,
        username: payload['cognito:username'] || payload.email,
        role: payload['custom:role'] || 'user'
      };
    }

    const auction = await db.get('SELECT * FROM auctions WHERE id = ?', [auctionId]);
    if (!auction) return socket.emit('bid_error', { message: '경매를 찾을 수 없습니다.' });
    if (auction.status !== 'active') return socket.emit('bid_error', { message: '진행 중인 경매가 아닙니다.' });
    if (amount <= auction.current_price) return socket.emit('bid_error', { message: `현재가(${auction.current_price.toLocaleString()}원)보다 높은 금액을 입력해주세요.` });

    const user = await db.get('SELECT * FROM users WHERE id = ?', [decoded.userId]);
    if (user.balance < amount) return socket.emit('bid_error', { message: `잔액이 부족합니다. (보유: ${user.balance.toLocaleString()}원)` });
    if (user.balance < auction.start_price) return socket.emit('bid_error', { message: '잔액이 시작가보다 적어 참여할 수 없습니다.' });

    await db.run('UPDATE auctions SET current_price = ?, current_winner_id = ? WHERE id = ?', [amount, decoded.userId, auctionId]);
    await db.run('INSERT INTO bids (auction_id, user_id, amount) VALUES (?, ?, ?)', [auctionId, decoded.userId, amount]);

    const updatedAuction = await db.get('SELECT * FROM auctions WHERE id = ?', [auctionId]);
    io.to(`auction_${auctionId}`).emit('bid_update', {
      auction: updatedAuction,
      lastBid: { username: user.username, amount, timestamp: new Date().toISOString() }
    });
  } catch (e) {
    socket.emit('bid_error', { message: '인증 오류: 다시 로그인해주세요.' });
  }
});

  // 랜덤 채팅
  // ── 도배 방지용 타임스탬프 저장소 ──
  // socket마다 마지막 메시지 보낸 시각 기록
  

  // 랜덤 채팅
  socket.on('chat_message', async ({ message, token }) => {
    // 도배 방지: 같은 소켓에서 3초 안에 또 보내면 차단
    const now = Date.now();
    const lastTime = chatCooldown[socket.id] || 0;
    if (now - lastTime < 3000) {
      return socket.emit('chat_error', { message: '메시지를 너무 빠르게 보내고 있습니다. 3초 후 다시 시도해주세요.' });
    }
    chatCooldown[socket.id] = now;
    try {
      let username = '익명';
      if (token) {
        const jwt = require('jsonwebtoken');
        const decoded = jwt.verify(token, JWT_SECRET);
        username = decoded.username;
      }
      if (!message || message.trim().length === 0) return;
      if (message.length > 200) return socket.emit('chat_error', { message: '메시지가 너무 깁니다.' });

      const trimmed = message.trim();
      await db.run('INSERT INTO chat_messages (username, message) VALUES (?, ?)', [username, trimmed]);

      io.emit('chat_message', {
        username,
        message: trimmed,
        timestamp: new Date().toISOString()
      });
    } catch (e) {
      const trimmed = message?.trim();
      if (trimmed) {
        await db.run('INSERT INTO chat_messages (username, message) VALUES (?, ?)', ['익명', trimmed]);
        io.emit('chat_message', { username: '익명', message: trimmed, timestamp: new Date().toISOString() });
      }
    }
  });

  // 채팅 최근 메시지 요청
  socket.on('get_chat_history', async () => {
    try {
      const messages = (await db.all('SELECT * FROM chat_messages ORDER BY created_at DESC LIMIT 50')).reverse();
      socket.emit('chat_history', messages);
    } catch (error) {
      console.error('채팅 기록 조회 오류:', error);
    }
  });

  socket.on('disconnect', () => {});
});




// 채팅 30분마다 자동 초기화
setInterval(async () => {
  try {
    // DB에서 30분 이상 된 메시지 삭제
    await db.run('DELETE FROM chat_messages WHERE created_at <= DATE_SUB(UTC_TIMESTAMP(), INTERVAL 30 MINUTE)');
    // 모든 접속자에게 채팅 초기화 알림
    io.emit('chat_cleared', { message: '채팅이 초기화되었습니다.' });
    console.log('채팅 자동 초기화 완료');
  } catch (error) {
    console.error('채팅 자동 초기화 오류:', error);
  }
}, 30 * 60 * 1000); // 30분

app.use((error, req, res, next) => {
  console.error(error);
  if (res.headersSent) return next(error);
  res.status(500).json({ message: '서버 오류가 발생했습니다.' });
});

const PORT = process.env.PORT || 3000;

let redisAdapterConnection = { close: async () => {} };

async function shutdown(signal) {
  console.log(`\n🛑 ${signal} 수신: 서버 종료를 시작합니다.`);
  server.close(async () => {
    await redisAdapterConnection.close();
    process.exit(0);
  });
}

process.once('SIGTERM', () => shutdown('SIGTERM'));
process.once('SIGINT', () => shutdown('SIGINT'));

// Producer: 10초마다 만료 경매 SQS enqueue
setInterval(() => scheduleExpiredAuctions(), 10000);
// Consumer: 5초마다 SQS에서 꺼내 처리
setInterval(() => processAuctionCloseQueue(io), 5000);

async function startServer() {
  try {
    await db.initializeDatabase();
    redisAdapterConnection = await configureRedisAdapter(io);
    server.listen(PORT, () => console.log(`✅ 서버 실행: http://localhost:${PORT}`));
  } catch (error) {
    console.error('❌ 서버 초기화 실패:', error);
    await redisAdapterConnection.close();
    process.exit(1);
  }
}

module.exports = { io };
startServer();
