const express = require('express');
const router = express.Router();

const path = require('path');
const db = require('../models/database');
const { authenticateToken, requireAdmin } = require('../middleware/auth');
const asyncHandler = require('../utils/asyncHandler');

const multer = require('multer');
const multerS3 = require('multer-s3');
const { S3Client } = require('@aws-sdk/client-s3');

const s3Client = new S3Client({ region: process.env.AWS_REGION || 'ap-northeast-2' });
const S3_IMAGES_BUCKET = process.env.S3_IMAGES_BUCKET;
const CLOUDFRONT_IMAGES_BASE_URL = process.env.CLOUDFRONT_IMAGES_BASE_URL;

const { BlobServiceClient } = require('@azure/storage-blob');

const AZ_STORAGE_CONNECTION_STRING = process.env.AZ_STORAGE_CONNECTION_STRING;

const storage = S3_IMAGES_BUCKET
  ? multerS3({
      s3: s3Client,
      bucket: S3_IMAGES_BUCKET,
      contentType: multerS3.AUTO_CONTENT_TYPE,
      key: (req, file, cb) => cb(null, `images/${Date.now()}-${file.originalname}`)
    })
  : AZ_STORAGE_CONNECTION_STRING
    ? multer.memoryStorage()  // Azure용 메모리에 임시 저장
    : multer.diskStorage({
        destination: (req, file, cb) => cb(null, path.join(__dirname, '..', 'uploads')),
        filename: (req, file, cb) => cb(null, Date.now() + '-' + file.originalname)
      });

const upload = multer({ storage });

// 목록
router.get('/', asyncHandler(async (req, res) => {
 const { status = 'active', page = 1, limit = 12, category } = req.query;
 const offset = (Number(page) - 1) * Number(limit);

  // category 필터 여부에 따라 쿼리 분기
  let auctions, total;
  if (category && category !== 'all') {
    auctions = await db.all(`
      SELECT a.*, u.username as seller_name,
      (SELECT COUNT(*) FROM bids WHERE auction_id = a.id) as bid_count
      FROM auctions a LEFT JOIN users u ON a.user_id = u.id
      WHERE a.status = ? AND a.category = ? ORDER BY a.end_time ASC LIMIT ? OFFSET ?
    `, [status, category, Number(limit), offset]);
    total = (await db.get('SELECT COUNT(*) as cnt FROM auctions WHERE status = ? AND category = ?', [status, category])).cnt;
  } else {
    auctions = await db.all(`
      SELECT a.*, u.username as seller_name,
      (SELECT COUNT(*) FROM bids WHERE auction_id = a.id) as bid_count
      FROM auctions a LEFT JOIN users u ON a.user_id = u.id
      WHERE a.status = ? ORDER BY a.end_time ASC LIMIT ? OFFSET ?
    `, [status, Number(limit), offset]);
    total = (await db.get('SELECT COUNT(*) as cnt FROM auctions WHERE status = ?', [status])).cnt;
  }
  res.json({ auctions, total });
}));

// 관리자 전체 목록, ORDER BY a.created_at DESC에서 ORDER BY a.id DESC로 교체
router.get('/admin/all', authenticateToken, requireAdmin, asyncHandler(async (req, res) => {
  const auctions = await db.all(`
    SELECT a.*, u.username as seller_name,
    (SELECT COUNT(*) FROM bids WHERE auction_id = a.id) as bid_count
    FROM auctions a LEFT JOIN users u ON a.user_id = u.id
    ORDER BY a.id DESC
  `);
  res.json({ auctions });
}));

// 상세
router.get('/:id', asyncHandler(async (req, res) => {
  const auction = await db.get(`
    SELECT a.*, u.username as seller_name, w.username as winner_name,
    (SELECT COUNT(*) FROM bids WHERE auction_id = a.id) as bid_count
    FROM auctions a
    LEFT JOIN users u ON a.user_id = u.id
    LEFT JOIN users w ON a.current_winner_id = w.id
    WHERE a.id = ?
  `, [req.params.id]);
  if (!auction) return res.status(404).json({ message: '경매를 찾을 수 없습니다.' });
  const bids = await db.all(`
    SELECT b.amount, b.created_at, u.username FROM bids b
    JOIN users u ON b.user_id = u.id
    WHERE b.auction_id = ? ORDER BY b.created_at DESC LIMIT 20
  `, [req.params.id]);
  res.json({ ...auction, bids });
}));

router.post('/', authenticateToken, requireAdmin, upload.single('image'), asyncHandler(async (req, res) => {
  const { title, description, start_price, end_time, min_bid_increment, image_url: bodyImageUrl, category } = req.body;
  if (!title || !start_price || !end_time) return res.status(400).json({ message: '필수 항목을 입력해주세요.' });

  let image_url = bodyImageUrl || null;

  if (req.file) {
    if (S3_IMAGES_BUCKET) {
      const s3Key = req.file.key;
      if (CLOUDFRONT_IMAGES_BASE_URL) {
        const filename = s3Key.replace(/^images\//, '');
        image_url = `${CLOUDFRONT_IMAGES_BASE_URL}/${filename}`;
      } else {
        image_url = req.file.location; // fallback
      }
    } else if (AZ_STORAGE_CONNECTION_STRING) {
      // 싱가폴: Azure Blob 직접 업로드
      const blobService = BlobServiceClient.fromConnectionString(AZ_STORAGE_CONNECTION_STRING);
      const containerClient = blobService.getContainerClient('uploads');
      const blobName = `${Date.now()}-${req.file.originalname}`;  // uploads/ 중복 제거
      const blockBlobClient = containerClient.getBlockBlobClient(blobName);
      await blockBlobClient.upload(req.file.buffer, req.file.size, {
        blobHTTPHeaders: { blobContentType: req.file.mimetype }
      });
      image_url = blockBlobClient.url;
    } else {
      // 로컬
      image_url = `/uploads/${req.file.filename}`;
    }
  }

  const result = await db.run(`
    INSERT INTO auctions (title, description, image_url, start_price, current_price, min_bid_increment, end_time, user_id, category)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `, [title, description, image_url, Number(start_price), Number(start_price), Number(min_bid_increment) || 1000, db.toMySqlDateTime(end_time), req.user.userId, category || 'etc']);
  res.json({ message: '경매 등록 완료!', auctionId: result.insertId });
}));

// 조기 종료 (admin만)
router.post('/:id/end', authenticateToken, requireAdmin, asyncHandler(async (req, res) => {
  const auction = await db.get('SELECT * FROM auctions WHERE id = ?', [req.params.id]);
  if (!auction) return res.status(404).json({ message: '경매를 찾을 수 없습니다.' });
  if (auction.status !== 'active') return res.status(400).json({ message: '이미 종료된 경매입니다.' });

  const { closeAuction } = require('../infra/auctionScheduler');
  await closeAuction(req.params.id, require('../server').io);
  res.json({ message: '경매가 조기 종료되었습니다.' });
}));



// 삭제 (admin만)
router.delete('/:id', authenticateToken, requireAdmin, asyncHandler(async (req, res) => {
  await db.run('DELETE FROM bids WHERE auction_id = ?', [req.params.id]);
  await db.run('DELETE FROM auctions WHERE id = ?', [req.params.id]);
  res.json({ message: '경매가 삭제되었습니다.' });
}));

module.exports = router;
