const { SQSClient, SendMessageCommand, ReceiveMessageCommand, DeleteMessageCommand } = require('@aws-sdk/client-sqs');
const db = require('../models/database');

const sqs = new SQSClient({ region: process.env.AWS_REGION || 'ap-northeast-2' });
const QUEUE_URL = process.env.AUCTION_CLOSE_QUEUE_URL;

async function scheduleExpiredAuctions() {
  if (!QUEUE_URL) {
    console.warn('AUCTION_CLOSE_QUEUE_URL 미설정 - 스케줄러 비활성화');
    return;
  }

  try {
    const now = db.toMySqlDateTime(new Date());
    const expired = await db.all(
      "SELECT id FROM auctions WHERE status = 'active' AND end_time <= ? AND closing_queued = 0",
      [now]
    );

    for (const { id } of expired) {
      await sqs.send(new SendMessageCommand({
        QueueUrl: QUEUE_URL,
        MessageBody: JSON.stringify({ auctionId: id }),
        MessageGroupId: `auction-close-${id}`,
        MessageDeduplicationId: `auction-close-${id}-${Date.now()}`
      }));

      await db.run('UPDATE auctions SET closing_queued = 1 WHERE id = ?', [id]);
    }
  } catch (err) {
    console.error('경매 종료 스케줄러 오류:', err);
  }
}

async function processAuctionCloseQueue(io) {
  if (!QUEUE_URL) return;

  try {
    const result = await sqs.send(new ReceiveMessageCommand({
      QueueUrl: QUEUE_URL,
      MaxNumberOfMessages: 10,
      WaitTimeSeconds: 5,
      VisibilityTimeout: 60
    }));

    if (!result.Messages?.length) return;

    for (const msg of result.Messages) {
      const { auctionId } = JSON.parse(msg.Body);

      try {
        await closeAuction(auctionId, io);

        await sqs.send(new DeleteMessageCommand({
          QueueUrl: QUEUE_URL,
          ReceiptHandle: msg.ReceiptHandle
        }));
      } catch (err) {
        console.error(`경매 ${auctionId} 종료 처리 오류:`, err);
      }
    }
  } catch (err) {
    console.error('SQS Consumer 오류:', err);
  }
}

async function closeAuction(auctionId, io) {
  let ended = false;

  await db.transaction(async (tx) => {
    const auction = await tx.get(
      'SELECT * FROM auctions WHERE id = ? FOR UPDATE',
      [auctionId]
    );
    if (!auction || auction.status !== 'active') return;

    await tx.run("UPDATE auctions SET status = 'ended' WHERE id = ?", [auctionId]);

    if (auction.current_winner_id) {
      const winner = await tx.get(
        'SELECT * FROM users WHERE id = ? FOR UPDATE',
        [auction.current_winner_id]
      );
      if (winner && Number(winner.balance) >= Number(auction.current_price)) {
        await tx.run(
          'UPDATE users SET balance = balance - ? WHERE id = ?',
          [auction.current_price, auction.current_winner_id]
        );
        await tx.run(
          'INSERT INTO balance_history (user_id, amount, type, description) VALUES (?, ?, ?, ?)',
          [auction.current_winner_id, -auction.current_price, 'deduct', `경매 낙찰: ${auction.title}`]
        );
        await tx.run(
          'INSERT INTO notifications (user_id, message, is_read) VALUES (?, ?, 0)',
          [auction.current_winner_id,
            `🎉 "${auction.title}" 경매에서 ${Number(auction.current_price).toLocaleString()}원에 낙찰되었습니다!`]
        );
      } else {
        await tx.run("UPDATE auctions SET current_winner_id = NULL WHERE id = ?", [auctionId]);
      }
    }

    ended = true;
  });

  // commit 이후에 Socket.IO 알림
  if (ended) {
    io.to(`auction_${auctionId}`).emit('auction_ended', { auctionId });
  }
}

module.exports = { scheduleExpiredAuctions, processAuctionCloseQueue, closeAuction };