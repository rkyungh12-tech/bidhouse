const mysql = require('mysql2/promise');
const { BlobServiceClient } = require('@azure/storage-blob');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');


exports.handler = async (event) => {

  


  console.log('🔄 서울 복구 감지 — 역동기화 및 복제 재연결 시작');

  const rdsConn = await mysql.createConnection({
    host: process.env.RDS_HOST,
    user: process.env.RDS_USER,
    password: process.env.RDS_PASS,
    database: 'auction',
    ssl: false
  });

  const azConn = await mysql.createConnection({
    host: process.env.AZ_MYSQL_HOST,
    user: process.env.AZ_MYSQL_USER,
    password: process.env.AZ_MYSQL_PASS,
    database: 'auction',
    ssl: { rejectUnauthorized: false }
  });

  try {
    // 0. 쓰기 중단 (freeze) — 역동기화 중 데이터 충돌 방지
    console.log('0️⃣ 쓰기 중단 — Azure MySQL을 Read-Only로 전환');
    try {
      await azConn.query(`SET GLOBAL read_only = ON;`);
      } catch (e) {
        console.warn('⚠️ read_only 설정 실패, 계속 진행:', e.message);
      }
      try {
        await azConn.query(`SET GLOBAL super_read_only = ON;`);
      } catch (e) {
        console.warn('⚠️ super_read_only 설정 실패, 계속 진행:', e.message);
      }
    console.log('✅ Azure MySQL Read-Only 전환 완료');

    // 1. 페일오버 중 싱가폴에서 쌓인 users 동기화
    const [users] = await azConn.query('SELECT * FROM users');
    for (const row of users) {
      await rdsConn.query(
        `INSERT INTO users (id, username, password, email, role, balance, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           balance = VALUES(balance)`,
        [row.id, row.username, row.password, row.email,
         row.role, row.balance, row.created_at]
      );
    }
    console.log(`✅ users 동기화 완료: ${users.length}건`);

    // 2. auctions 동기화
    const [auctions] = await azConn.query('SELECT * FROM auctions');
    for (const row of auctions) {
      await rdsConn.query(
        `INSERT INTO auctions
           (id, title, description, start_price, current_price,
            current_winner_id, min_bid_increment, user_id, category,
            status, end_time, image_url, created_at, closing_queued)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           current_price     = VALUES(current_price),
           current_winner_id = VALUES(current_winner_id),
           status            = VALUES(status),
           closing_queued    = VALUES(closing_queued)`,
        [row.id, row.title, row.description, row.start_price,
         row.current_price, row.current_winner_id, row.min_bid_increment,
         row.user_id, row.category, row.status, row.end_time,
         row.image_url, row.created_at, row.closing_queued]
      );
    }
    console.log(`✅ auctions 동기화 완료: ${auctions.length}건`);

    // 3. bids 동기화 (중복 무시)
    const [bids] = await azConn.query('SELECT * FROM bids');
    for (const row of bids) {
      await rdsConn.query(
        `INSERT IGNORE INTO bids (id, auction_id, user_id, amount, created_at)
         VALUES (?, ?, ?, ?, ?)`,
        [row.id, row.auction_id, row.user_id, row.amount, row.created_at]
      );
    }
    console.log(`✅ bids 동기화 완료: ${bids.length}건`);

    // 4. balance_history 동기화
    const [history] = await azConn.query('SELECT * FROM balance_history');
    for (const row of history) {
      await rdsConn.query(
        `INSERT IGNORE INTO balance_history
           (id, user_id, amount, type, description, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [row.id, row.user_id, row.amount, row.type,
         row.description, row.created_at]
      );
    }
    console.log(`✅ balance_history 동기화 완료: ${history.length}건`);

    // 5. Azure MySQL 복제 재연결 (서울 RDS를 다시 소스로)
    await azConn.query(`CALL mysql.az_replication_stop();`);
    await azConn.query(`CALL mysql.az_replication_remove_master();`);

    // binlog 위치 새로 잡기
    const [masterStatus] = await rdsConn.query('SHOW MASTER STATUS');
    const binlogFile = masterStatus[0].File;
    const binlogPos  = masterStatus[0].Position;

    await azConn.query(
      `CALL mysql.az_replication_change_master(?, 'repl_user', ?, 3306, ?, ?, '');`,
      [process.env.RDS_HOST, process.env.REPL_PASS, binlogFile, binlogPos]
    );
    await azConn.query(`CALL mysql.az_replication_start();`);

    await new Promise(r => setTimeout(r, 10000));
    const [slaveRows] = await azConn.query('SHOW SLAVE STATUS');
    const slave = slaveRows[0];
    console.log('복제 상태:', {
      io: slave?.Slave_IO_Running,
      sql: slave?.Slave_SQL_Running,
      lastIoErr: slave?.Last_IO_Error,
      lastSqlErr: slave?.Last_SQL_Error
    });
    if (slave?.Slave_IO_Running !== 'Yes' || slave?.Slave_SQL_Running !== 'Yes') {
      throw new Error(`복제 재연결 실패: IO=${slave?.Slave_IO_Running}, SQL=${slave?.Slave_SQL_Running}`);
    }

    // 5-1. Azure Blob → S3 이미지 역동기화
    
    const { StorageSharedKeyCredential } = require('@azure/storage-blob');
    const azAccount = process.env.AZ_STORAGE_ACCOUNT_NAME;
    const azKey     = process.env.AZ_STORAGE_ACCOUNT_KEY;
    const azCredential = new StorageSharedKeyCredential(azAccount, azKey);
    const blobService = new BlobServiceClient(
      `https://${azAccount}.blob.core.windows.net`,
      azCredential
    );
    const s3 = new S3Client({ region: 'ap-northeast-2' });
    const containerClient = blobService.getContainerClient('uploads');

    for await (const blob of containerClient.listBlobsFlat()) {
    const blobClient = containerClient.getBlobClient(blob.name);
    const download = await blobClient.download();
    const chunks = [];
    for await (const chunk of download.readableStreamBody) chunks.push(chunk);
    const buffer = Buffer.concat(chunks);
    await s3.send(new PutObjectCommand({
        Bucket: process.env.S3_IMAGES_BUCKET,
        Key: blob.name,
        Body: buffer,
        ContentType: blob.properties.contentType
    }));
    console.log(`✅ Blob→S3 복사: ${blob.name}`);
    }
    console.log('✅ 이미지 역동기화 완료');

    return { statusCode: 200, body: '역동기화 및 복제 재연결 완료' };

  } catch (err) {
    console.error('❌ 역동기화 실패:', err);
    throw err;
  } finally {
    await rdsConn.end();
    await azConn.end();
  }
};
