output "socketio_redis_primary_endpoint" {
  description = "Primary endpoint for the Socket.IO Redis OSS adapter"
  value       = aws_elasticache_replication_group.socketio_redis.primary_endpoint_address
}

output "socketio_redis_reader_endpoint" {
  description = "Reader endpoint for operational inspection; Socket.IO adapter should use the primary endpoint"
  value       = aws_elasticache_replication_group.socketio_redis.reader_endpoint_address
}

output "socketio_redis_port" {
  description = "Redis OSS port"
  value       = aws_elasticache_replication_group.socketio_redis.port
}

output "socketio_redis_auth_secret_arn" {
  description = "Secrets Manager ARN that stores REDIS_AUTH_TOKEN"
  value       = aws_secretsmanager_secret.socketio_redis_auth.arn
}
