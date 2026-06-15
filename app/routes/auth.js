const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../models/database');
const { authenticateToken } = require('../middleware/auth');
const asyncHandler = require('../utils/asyncHandler');
const { CognitoIdentityProviderClient,
        SignUpCommand,
        InitiateAuthCommand,
        ConfirmSignUpCommand,
        ResendConfirmationCodeCommand } = require('@aws-sdk/client-cognito-identity-provider');  // ← 추가

const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET) throw new Error('JWT_SECRET environment variable is required.');

const COGNITO_CLIENT_ID = process.env.COGNITO_CLIENT_ID;
const COGNITO_REGION = process.env.AWS_REGION || 'ap-northeast-2';

const cognitoClient = COGNITO_CLIENT_ID
  ? new CognitoIdentityProviderClient({ region: COGNITO_REGION })
  : null;

router.post('/register', asyncHandler(async (req, res) => {
  const { username, password, email } = req.body;
  if (!username || !password) return res.status(400).json({ message: '아이디와 비밀번호를 입력해주세요.' });
  if (username.length < 4) return res.status(400).json({ message: '아이디는 4자 이상이어야 합니다.' });
  if (password.length < 12) return res.status(400).json({ message: '비밀번호는 12자 이상이어야 합니다.' });
  if (!/[A-Z]/.test(password)) return res.status(400).json({ message: '대문자를 포함해야 합니다.' });
  if (!/[a-z]/.test(password)) return res.status(400).json({ message: '소문자를 포함해야 합니다.' });
  if (!/[0-9]/.test(password)) return res.status(400).json({ message: '숫자를 포함해야 합니다.' });
  if (!/[^A-Za-z0-9]/.test(password)) return res.status(400).json({ message: '특수문자를 포함해야 합니다.' });
  if (!email) return res.status(400).json({ message: '이메일을 입력해주세요.' });

  if (await db.get('SELECT id FROM users WHERE username = ?', [username]))
    return res.status(409).json({ message: '이미 존재하는 아이디입니다.' });

  const hashed = bcrypt.hashSync(password, 10);
  const result = await db.run(
    'INSERT INTO users (username, password, email) VALUES (?, ?, ?)',
    [username, hashed, email]
  );

  // Cognito 연동
  if (cognitoClient) {
    try {
      await cognitoClient.send(new SignUpCommand({
        ClientId: COGNITO_CLIENT_ID,
        Username: email,
        Password: password,
        UserAttributes: [
          { Name: 'email', Value: email },
          { Name: 'preferred_username', Value: username },
          { Name: 'custom:userId', Value: String(result.insertId) },
          { Name: 'custom:role', Value: 'user' }
        ]
      }));
    } catch (cognitoErr) {
      console.warn('Cognito 회원가입 실패 (DB는 성공):', cognitoErr.message);
    }
  }

  res.json({ 
  message: '회원가입 완료! 이메일로 발송된 인증 코드를 입력해주세요.',
  requireConfirm: true,   // ← 프론트가 인증 화면으로 넘어갈 신호
  email: email            // ← 인증 화면에 이메일 자동 입력용
  });
}));

// 이메일 인증 코드 확인
router.post('/confirm', asyncHandler(async (req, res) => {
  const { email, code } = req.body;
  if (!email || !code) return res.status(400).json({ message: '이메일과 인증 코드를 입력해주세요.' });

  if (!cognitoClient) return res.status(400).json({ message: 'Cognito가 설정되지 않았습니다.' });

  try {
    await cognitoClient.send(new ConfirmSignUpCommand({
      ClientId: COGNITO_CLIENT_ID,
      Username: email,
      ConfirmationCode: code
    }));
    res.json({ message: '이메일 인증이 완료되었습니다. 로그인해주세요.' });
  } catch (err) {
    if (err.name === 'CodeMismatchException') return res.status(400).json({ message: '인증 코드가 올바르지 않습니다.' });
    if (err.name === 'ExpiredCodeException') return res.status(400).json({ message: '인증 코드가 만료되었습니다. 재전송해주세요.' });
    return res.status(400).json({ message: err.message });
  }
}));

// 인증 코드 재전송
router.post('/resend-code', asyncHandler(async (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ message: '이메일을 입력해주세요.' });

  if (!cognitoClient) return res.status(400).json({ message: 'Cognito가 설정되지 않았습니다.' });


  try {
    await cognitoClient.send(new ResendConfirmationCodeCommand({
      ClientId: COGNITO_CLIENT_ID,
      Username: email
    }));
    res.json({ message: '인증 코드를 재전송했습니다.' });
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
}));

router.post('/login', asyncHandler(async (req, res) => {
  const { username, password } = req.body;

  // Cognito 로그인 시도
  if (cognitoClient) {
    try {
      const user = await db.get('SELECT * FROM users WHERE username = ?', [username]);
      if (user && user.email) {
        const authResult = await cognitoClient.send(new InitiateAuthCommand({
          AuthFlow: 'USER_PASSWORD_AUTH',
          ClientId: COGNITO_CLIENT_ID,
          AuthParameters: {
            USERNAME: user.email,
            PASSWORD: password
          }
        }));

        const idToken = authResult.AuthenticationResult.IdToken;
        return res.json({
          token: idToken,
          username: user.username,
          userId: user.id,
          role: user.role
        });
      }
    } catch (cognitoErr) {
      console.warn('Cognito 로그인 실패, fallback:', cognitoErr.message);
    }
  }

  // fallback: 자체 JWT
  const user = await db.get('SELECT * FROM users WHERE username = ?', [username]);
  if (!user || !bcrypt.compareSync(password, user.password))
    return res.status(401).json({ message: '아이디 또는 비밀번호가 올바르지 않습니다.' });
  const token = jwt.sign(
    { userId: user.id, username: user.username, role: user.role },
    JWT_SECRET,
    { expiresIn: '24h' }
  );
  res.json({ token, username: user.username, userId: user.id, role: user.role });
}));

router.get('/me', authenticateToken, asyncHandler(async (req, res) => {
  const user = await db.get('SELECT id, username, email, balance, role, created_at FROM users WHERE id = ?', [req.user.userId]);
  if (!user) return res.status(404).json({ message: '유저 없음' });
  const myBids = await db.get('SELECT COUNT(DISTINCT auction_id) as cnt FROM bids WHERE user_id = ?', [req.user.userId]);
  const myWins = await db.get("SELECT COUNT(*) as cnt FROM auctions WHERE current_winner_id = ? AND status = 'ended'", [req.user.userId]);
  res.json({ ...user, bidCount: myBids.cnt, winCount: myWins.cnt });
}));

// 잔액 충전
router.post('/charge', authenticateToken, asyncHandler(async (req, res) => {
  const { amount } = req.body;
  if (!amount || amount <= 0 || amount > 10000000) return res.status(400).json({ message: '충전 금액이 올바르지 않습니다. (최대 1000만원)' });
  await db.run('UPDATE users SET balance = balance + ? WHERE id = ?', [amount, req.user.userId]);
  await db.run('INSERT INTO balance_history (user_id, amount, type, description) VALUES (?, ?, ?, ?)', [req.user.userId, amount, 'charge', '잔액 충전']);
  const updated = await db.get('SELECT balance FROM users WHERE id = ?', [req.user.userId]);
  res.json({ message: '충전 완료!', balance: updated.balance });
}));

// 잔액 내역
router.get('/balance-history', authenticateToken, asyncHandler(async (req, res) => {
  const history = await db.all('SELECT * FROM balance_history WHERE user_id = ? ORDER BY created_at DESC LIMIT 20', [req.user.userId]);
  res.json(history);
}));

// 내가 입찰 참여한 경매 목록
router.get('/my-bids', authenticateToken, asyncHandler(async (req, res) => {
  const auctions = await db.all(`
    SELECT DISTINCT a.*, u.username as seller_name, w.username as winner_name,
    (SELECT COUNT(*) FROM bids WHERE auction_id = a.id) as bid_count,
    (SELECT MAX(amount) FROM bids WHERE auction_id = a.id AND user_id = ?) as my_max_bid
    FROM auctions a
    JOIN bids b ON b.auction_id = a.id
    LEFT JOIN users u ON a.user_id = u.id
    LEFT JOIN users w ON a.current_winner_id = w.id
    WHERE b.user_id = ?
    ORDER BY a.end_time DESC
  `, [req.user.userId, req.user.userId]);
  res.json(auctions);
}));

// 내가 낙찰받은 경매 목록
router.get('/my-wins', authenticateToken, asyncHandler(async (req, res) => {
  const auctions = await db.all(`
    SELECT a.*, u.username as seller_name,
    (SELECT COUNT(*) FROM bids WHERE auction_id = a.id) as bid_count
    FROM auctions a
    LEFT JOIN users u ON a.user_id = u.id
    WHERE a.current_winner_id = ? AND a.status = 'ended'
    ORDER BY a.end_time DESC
  `, [req.user.userId]);
  res.json(auctions);
}));

// 내 알림 목록
router.get('/notifications', authenticateToken, asyncHandler(async (req, res) => {
  const notifications = await db.all(
    'SELECT * FROM notifications WHERE user_id = ? AND is_read = 0 ORDER BY created_at DESC',
    [req.user.userId]
  );
  res.json(notifications);
}));

// 알림 읽음 처리
router.post('/notifications/:id/read', authenticateToken, asyncHandler(async (req, res) => {
  await db.run('UPDATE notifications SET is_read = 1 WHERE id = ? AND user_id = ?', [req.params.id, req.user.userId]);
  res.json({ message: '확인 완료' });
}));



// 1. 게임 시작 API (시간 기록용 토큰 발급)
router.post('/game-start', authenticateToken, (req, res) => {
  // 현재 시간을 담은 게임 전용 토큰을 발급 (5분 지나면 만료됨)
  const gameToken = jwt.sign(
    { userId: req.user.userId, startTime: Date.now() },
    JWT_SECRET,
    { expiresIn: '5m' }
  );
  res.json({ gameToken });
});

// 2. 게임 보상 API (시간 및 점수 검증)
router.post('/game-reward', authenticateToken, asyncHandler(async (req, res) => {
  const { score, gameToken } = req.body;

  if (!gameToken) return res.status(400).json({ message: '정상적인 게임 플레이가 아닙니다.' });

  try {
    // 토큰 해독 및 시간 계산
    const decoded = jwt.verify(gameToken, JWT_SECRET);
    const elapsedSeconds = (Date.now() - decoded.startTime) / 1000;

    // 🚨 핵심 보안: 1초당 얻을 수 있는 최대 점수를 제한 (예: 1초에 최대 50점이라고 가정)
    const maxPossibleScore = elapsedSeconds * 50;

    // 점수가 0 이하거나, 플레이 시간 대비 점수가 말도 안 되게 높으면 차단!
    if (score <= 0 || score > maxPossibleScore) {
      return res.status(403).json({ message: '비정상적인 플레이가 감지되어 보상이 취소되었습니다.' });
    }

    // 보상 계산 (예: 10점당 1원 지급)
    const rewardAmount = Math.floor(score / 10) * 1;

    // DB 업데이트 및 기록
    await db.run('UPDATE users SET balance = balance + ? WHERE id = ?', [rewardAmount, req.user.userId]);
    await db.run('INSERT INTO balance_history (user_id, amount, type, description) VALUES (?, ?, ?, ?)', [req.user.userId, rewardAmount, 'game_reward', `블록 부수기 보상 (${score}점)`]);

    const updated = await db.get('SELECT balance FROM users WHERE id = ?', [req.user.userId]);
    res.json({ message: `${rewardAmount.toLocaleString()}원을 획득했습니다!`, balance: updated.balance });

  } catch (e) {
    return res.status(400).json({ message: '게임 시간이 초과되었거나 유효하지 않은 결과입니다.' });
  }

  
}));

module.exports = router;
