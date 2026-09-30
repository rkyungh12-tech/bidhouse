const mysql = require('mysql2/promise');

exports.handler = async (event) => {
  console.log('🚨 서울 장애 감지 — Azure MySQL을 Master로 승격 시작');

  const azConn = await mysql.createConnection({
    host: process.env.AZ_MYSQL_HOST,
    user: process.env.AZ_MYSQL_USER,
    password: process.env.AZ_MYSQL_PASS,
    database: 'auction',
    ssl: { rejectUnauthorized: false }
  });

  try {
    // 1. 기존 복제 연결 끊기 (더 이상 서울 RDS를 따라가지 않음)
    console.log('1️⃣ 기존 복제 연결 해제 중...');
    try {
      await azConn.query(`CALL mysql.az_replication_stop();`);
    } catch (e) {
      console.warn('⚠️ replication_stop 실패 (이미 중지된 상태일 수 있음):', e.message);
    }

    try {
      await azConn.query(`CALL mysql.az_replication_remove_master();`);
    } catch (e) {
      console.warn('⚠️ remove_master 실패 (이미 제거된 상태일 수 있음):', e.message);
    }

    // 2. Read-Only 해제 → 쓰기 가능한 Master로 전환
    console.log('2️⃣ Read-Only 해제 중...');
    await azConn.query(`SET GLOBAL read_only = OFF;`);
    await azConn.query(`SET GLOBAL super_read_only = OFF;`);

    // 3. 현재 상태 확인
    const [readOnlyStatus] = await azConn.query(`SHOW VARIABLES LIKE 'read_only';`);
    console.log('✅ 현재 read_only 상태:', readOnlyStatus[0].Value);

    console.log('🎉 Azure MySQL 승격 완료 — 이제 쓰기 가능한 Master입니다');

    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'Azure MySQL 승격 완료',
        read_only: readOnlyStatus[0].Value
      })
    };

  } catch (err) {
    console.error('❌ 승격 실패:', err);
    throw err;
  } finally {
    await azConn.end();
  }
};