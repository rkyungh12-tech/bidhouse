// ============================================================================
// 🏛️ [통합 마스터] app/models/database.js (오타 및 컬럼 누락 완벽 보수본)
// ============================================================================
const mysql = require('mysql2/promise');
const bcrypt = require('bcryptjs');

// Cloud DB connection pool. AWS uses Secrets Manager injection; Azure uses Key Vault references.
const useTls = String(process.env.DB_SSL || '').toLowerCase() === 'true';

const pool = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || 'auction',
  port: process.env.DB_PORT || 3306,
  waitForConnections: true,
  connectionLimit: parseInt(process.env.DB_POOL_LIMIT || '10'),
  queueLimit: 0,
  ssl: useTls ? { rejectUnauthorized: false  } : undefined
});

const db = {
  get: async (sql, params = []) => {
    const [rows] = await pool.query(sql, params);
    return rows[0] || null;
  },

  all: async (sql, params = []) => {
    const [rows] = await pool.query(sql, params);
    return rows;
  },

  run: async (sql, params = []) => {
    const [result] = await pool.query(sql, params);
    return {
      insertId: result.insertId,
      affectedRows: result.affectedRows,
      // Temporary aliases for older handlers during the migration.
      lastID: result.insertId,
      changes: result.affectedRows
    };
  },

  ping: async () => {
    await pool.query('SELECT 1');
  },

  toMySqlDateTime: (dateStr) => {
    if (!dateStr) return null;
    const date = new Date(dateStr);
    return date.toISOString().slice(0, 19).replace('T', ' ');
  },

  initializeDatabase: async () => {
    console.log('🏗️ 클라우드 데이터베이스(MySQL) 구조 확인 및 초기화 시작...');

    // 1) 회원 테이블 (email, role 컬럼 확실하게 주입)
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        password VARCHAR(255) NOT NULL,
        email VARCHAR(100) NULL,
        role VARCHAR(20) DEFAULT 'user',
        balance INT DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // 2) 경매 상품 테이블 (min_bid_increment, user_id, category 컬럼 확실하게 주입)
    await pool.query(`
      CREATE TABLE IF NOT EXISTS auctions (
        id INT AUTO_INCREMENT PRIMARY KEY,
        title VARCHAR(100) NOT NULL,
        description TEXT,
        start_price INT NOT NULL,
        current_price INT NOT NULL,
        current_winner_id INT NULL,
        min_bid_increment INT DEFAULT 1000,
        user_id INT NOT NULL,
        category VARCHAR(50) DEFAULT 'etc',
        status VARCHAR(20) DEFAULT 'active',
        end_time DATETIME NOT NULL,
        image_url VARCHAR(255) NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        closing_queued TINYINT(1) DEFAULT 0
      )
    `);

    // 3) 입찰 기록 테이블
    await pool.query(`
      CREATE TABLE IF NOT EXISTS bids (
        id INT AUTO_INCREMENT PRIMARY KEY,
        auction_id INT NOT NULL,
        user_id INT NOT NULL,
        amount INT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // 4) 채팅 메시지 테이블
    await pool.query(`
      CREATE TABLE IF NOT EXISTS chat_messages (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50) NOT NULL,
        message TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // 5) 낙찰 및 캐시 내역 추적 테이블
    await pool.query(`
      CREATE TABLE IF NOT EXISTS balance_history (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        amount INT NOT NULL,
        type VARCHAR(20) NOT NULL,
        description VARCHAR(255),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // 6) 알림 메시지 테이블
    await pool.query(`
      CREATE TABLE IF NOT EXISTS notifications (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        message TEXT NOT NULL,
        is_read TINYINT(1) DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    const adminPasswordHash = bcrypt.hashSync('admin!1234', 10);
    await pool.query(`
      INSERT INTO users (username, password, email, role, balance)
      VALUES ('admin', ?, 'admin@bidhouse.com', 'admin', 999999999)
      ON DUPLICATE KEY UPDATE
        password = VALUES(password),
        role = VALUES(role)
    `, [adminPasswordHash]);

    console.log('✅ 최고 관리자 계정 생성 및 전 구간 테이블 인프라 공사 대완공! (ID: admin / PW: admin!1234)');
    // closing_queued 컬럼 없으면 추가 (마이그레이션)
    await pool.query(`
      ALTER TABLE auctions
      ADD COLUMN IF NOT EXISTS closing_queued TINYINT(1) DEFAULT 0
    `).catch(() => {}); // 이미 있으면 무시
  } // 👈 initializeDatabase 비동기 함수 마감
}; // 👈 db 마스터 객체 완전 폐쇄

module.exports = db;