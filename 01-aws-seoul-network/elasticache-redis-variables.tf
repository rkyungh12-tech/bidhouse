variable "socketio_redis_node_type" {
  description = "ElastiCache Redis OSS node type for Socket.IO Pub/Sub"
  type        = string
  default     = "cache.t4g.micro"
}
