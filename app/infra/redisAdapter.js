const { createClient } = require('redis');
const { createAdapter } = require('@socket.io/redis-adapter');

function isEnabled(value) {
  return String(value || '').toLowerCase() === 'true';
}

function requireEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} environment variable is required when Redis is enabled.`);
  return value;
}

/**
 * Connect Socket.IO to the Redis Pub/Sub backend.
 *
 * Local development remains backward compatible: Redis is disabled unless
 * REDIS_ENABLED=true. In ECS, REDIS_ENABLED is injected as true so a broken
 * Redis configuration fails the deployment instead of silently running with
 * isolated in-memory Socket.IO adapters.
 */
async function configureRedisAdapter(io) {
  if (!isEnabled(process.env.REDIS_ENABLED)) {
    console.log('ℹ️ Socket.IO Redis Adapter disabled; using the in-memory adapter.');
    return { close: async () => {} };
  }

  const host = requireEnv('REDIS_HOST');
  const password = requireEnv('REDIS_AUTH_TOKEN');
  const port = Number(process.env.REDIS_PORT || 6379);
  const tls = isEnabled(process.env.REDIS_TLS);

  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    throw new Error(`Invalid REDIS_PORT: ${process.env.REDIS_PORT}`);
  }

  const socket = {
    host,
    port,
    tls,
    reconnectStrategy(retries) {
      return Math.min(retries * 100, 3000);
    }
  };

  const pubClient = createClient({ socket, password });
  const subClient = pubClient.duplicate();

  pubClient.on('error', (error) => console.error('❌ Redis Pub Client 오류:', error));
  subClient.on('error', (error) => console.error('❌ Redis Sub Client 오류:', error));

  await Promise.all([pubClient.connect(), subClient.connect()]);
  io.adapter(createAdapter(pubClient, subClient));

  console.log(`✅ Socket.IO Redis Adapter 연결 완료: ${host}:${port} (TLS=${tls})`);

  return {
    async close() {
      await Promise.allSettled([
        pubClient.isOpen ? pubClient.quit() : Promise.resolve(),
        subClient.isOpen ? subClient.quit() : Promise.resolve()
      ]);
    }
  };
}

module.exports = { configureRedisAdapter };
