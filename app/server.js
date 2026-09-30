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
const { SQSClient, SendMessageCommand, ReceiveMessageCommand, DeleteMessageCommand } = require('@aws-sdk/client-sqs');

// SQS 클라이언트 초기화 (AWS 서울 리전 고정)
const sqsClient = new SQSClient({ region: 'ap-northeast-2' });

// sticky sesstion
const os = require('os');

// 🚀 [한 번의 배포 자동화] 테라폼 아웃풋이 파이프라인을 통해 주입할 환경변수 맵핑
const BID_QUEUE_URL = process.env.BID_QUEUE_URL;
if (!BID_QUEUE_URL) console.warn('BID_QUEUE_URL 미설정 - 입찰 큐 비활성화');         
          // 실시간 입찰 전용 큐 URL
const AUCTION_CLOSE_QUEUE_URL = process.env.AUCTION_CLOSE_QUEUE_URL; // 경매 정산 종료 전용 큐 URL
// 런타임 크래시 방지 및 인프라 주입 상태 자가 진단 로그
if (!BID_QUEUE_URL || !AUCTION_CLOSE_QUEUE_URL) {
  console.error('🚨 [환경변수 경고] SQS FIFO 큐 URL이 로드되지 않았습니다. 인프라 배포 상태를 확인하세요.');
}

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
  methods: ['GET', 'POST', 'HEAD', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'x-aws-waf-token'],
  exposedHeaders: ['Server', 'x-envoy-upstream-service-time', 'x-amzn-waf-action']
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

// 💡 기존 DB 체크와 새로운 지역(Region) 판별 로직을 하나로 합침!
app.get('/health', async (req, res) => {
  // 애저(싱가폴)인지 AWS(서울)인지 환경변수로 판단
  const isAzure = !!process.env.CONTAINER_APP_NAME; 
  const currentRegion = isAzure ? 'singapore' : 'seoul';

  try {
    await db.ping();
    res.status(200).json({ 
      status: 'ok', 
      database: 'connected',
      region: currentRegion // 👈 JSON에 지역 정보 추가!
    });
  } catch (error) {
    res.status(503).json({ 
      status: 'error', 
      database: 'disconnected',
      region: currentRegion 
    });
  }
});


app.get('/debug/instance', (req, res) => {
  res.json({
    hostname: os.hostname(),
    pid: process.pid,
    time: new Date().toISOString(),
    cookie: req.headers.cookie || null,
    remoteAddress: req.ip
  });
});

// 🚨 주의: 프론트엔드 화면을 띄워주는 이 코드는 무조건 맨 밑에 있어야 합니다!
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

// 입찰 (SQS로 메시지 전송)
  socket.on('place_bid', async ({ auctionId, amount, token }) => {
    try {
      // 1. JWT 및 Cognito 인증 로직 (완벽 복구!)
      let decoded;
      const jwt = require('jsonwebtoken');
      try {
        decoded = jwt.verify(token, JWT_SECRET);
      } catch {
        // Cognito 토큰 검증 시도
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

      // 2. 최소한의 1차 검증 (DB 조회)
      const auction = await db.get('SELECT * FROM auctions WHERE id = ?', [auctionId]);
      if (!auction) return socket.emit('bid_error', { message: '경매를 찾을 수 없습니다.' });
      if (auction.status !== 'active') return socket.emit('bid_error', { message: '진행 중인 경매가 아닙니다.' });
      if (amount <= auction.current_price) return socket.emit('bid_error', { message: '현재가보다 높은 금액을 입력해주세요.' });

      const user = await db.get('SELECT * FROM users WHERE id = ?', [decoded.userId]);
      if (!user) return socket.emit('bid_error', { message: '사용자를 찾을 수 없습니다.' });
      if (user.balance < amount) return socket.emit('bid_error', { message: '잔액이 부족합니다.' });

      // 3. DB 업데이트 대신 SQS 입찰 전용 큐로 요청 전송!
      const messageBody = JSON.stringify({
        auctionId,
        userId: decoded.userId,
        username: user.username,
        amount
      });

      await sqsClient.send(new SendMessageCommand({
        QueueUrl: BID_QUEUE_URL,
        MessageBody: messageBody,
        MessageGroupId: `auction_${auctionId}`, // 같은 경매는 무조건 줄 세움
        MessageDeduplicationId: `bid_${auctionId}_${decoded.userId}_${Date.now()}`
      }));

    } catch (e) {
      console.error(e);
      socket.emit('bid_error', { message: '인증 오류 또는 입찰 요청 처리 중 오류가 발생했습니다. 다시 시도해주세요.' });
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

// SQS 입찰 큐 처리 워커 (Consumer)
async function processBidQueue() {
  if (!BID_QUEUE_URL) return;
  try {
    const data = await sqsClient.send(new ReceiveMessageCommand({
      QueueUrl: BID_QUEUE_URL,
      MaxNumberOfMessages: 1,
      WaitTimeSeconds: 5
    }));

    if (data.Messages && data.Messages.length > 0) {
      const message = data.Messages[0];
      const bidData = JSON.parse(message.Body);
      const { auctionId, userId, username, amount } = bidData;

      // [수정] 기존 db.get() + db.run() 개별 호출 → db.transaction()으로 교체
      let updatedAuction = null;
      let accepted = false;

      await db.transaction(async (tx) => {
        // [수정] FOR UPDATE: 이 row를 잡고 있는 동안 다른 트랜잭션 수정 불가
        const auction = await tx.get(
          'SELECT * FROM auctions WHERE id = ? FOR UPDATE',
          [auctionId]
        );

        if (!auction) return;

        // [수정] min_bid_increment 반영 (기존: amount > current_price 단순 비교)
        const minAmount = Number(auction.current_price) + Number(auction.min_bid_increment || 0);

        if (auction.status === 'active' && Number(amount) >= minAmount) {
          await tx.run(
            'UPDATE auctions SET current_price = ?, current_winner_id = ? WHERE id = ?',
            [amount, userId, auctionId]
          );
          await tx.run(
            'INSERT INTO bids (auction_id, user_id, amount) VALUES (?, ?, ?)',
            [auctionId, userId, amount]
          );
          updatedAuction = await tx.get('SELECT * FROM auctions WHERE id = ?', [auctionId]);
          accepted = true;
        }
      }); // [수정] 여기서 commit (실패 시 자동 rollback)

      // [수정] io.emit()은 트랜잭션 commit 완료 후에만 실행
      if (accepted && updatedAuction) {
        io.to(`auction_${auctionId}`).emit('bid_update', {
          auction: updatedAuction,
          lastBid: { username, amount, timestamp: new Date().toISOString() }
        });
      }

      await sqsClient.send(new DeleteMessageCommand({
        QueueUrl: BID_QUEUE_URL,
        ReceiptHandle: message.ReceiptHandle
      }));
    }
  } catch (error) {
    console.error('입찰 큐 처리 중 오류:', error);
  } finally {
    setTimeout(processBidQueue, 100);
  }
}



async function startServer() {
  try {
    await db.initializeDatabase();
    redisAdapterConnection = await configureRedisAdapter(io);
    server.listen(PORT, () => console.log(`✅ 서버 실행: http://localhost:${PORT}`));
    processBidQueue();
  } catch (error) {
    console.error('❌ 서버 초기화 실패:', error);
    await redisAdapterConnection.close();
    process.exit(1);
  }
}



module.exports = { io };
startServer();
