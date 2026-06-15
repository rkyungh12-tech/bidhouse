const { CognitoJwtVerifier } = require('aws-jwt-verify');
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET;
const COGNITO_USER_POOL_ID = process.env.COGNITO_USER_POOL_ID;
const COGNITO_CLIENT_ID = process.env.COGNITO_CLIENT_ID;

if (!JWT_SECRET) throw new Error('JWT_SECRET environment variable is required.');

// Cognito JWT 검증기 (환경변수 있을 때만 초기화)
const cognitoVerifier = COGNITO_USER_POOL_ID && COGNITO_CLIENT_ID
  ? CognitoJwtVerifier.create({
      userPoolId: COGNITO_USER_POOL_ID,
      tokenUse: 'id',
      clientId: COGNITO_CLIENT_ID,
    })
  : null;

async function authenticateToken(req, res, next) {
  const token = (req.headers['authorization'] || '').split(' ')[1];
  if (!token) return res.status(401).json({ message: '로그인이 필요합니다.' });

  // 1. Cognito 토큰 시도
  if (cognitoVerifier) {
    try {
      const payload = await cognitoVerifier.verify(token);
      req.user = {
        userId: payload['custom:userId'] || payload.sub,
        username: payload['cognito:username'] || payload.email,
        role: payload['custom:role'] || 'user',
        sub: payload.sub,
        isCognito: true
      };
      return next();
    } catch (_) {
      // Cognito 검증 실패 시 자체 JWT로 fallback
    }
  }

  // 2. 자체 JWT fallback
  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) return res.status(403).json({ message: '토큰이 만료되었습니다.' });
    req.user = user;
    next();
  });
}

function requireAdmin(req, res, next) {
  if (req.user?.role !== 'admin') return res.status(403).json({ message: '관리자만 접근 가능합니다.' });
  next();
}

module.exports = { authenticateToken, requireAdmin };