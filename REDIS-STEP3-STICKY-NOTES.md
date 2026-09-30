# Redis Adapter + ALB Sticky Session 적용 안내

## 적용 범위

이번 수정은 다음을 함께 반영합니다.

- ElastiCache Redis OSS Replication Group
- Private Subnet 2개 배치
- Redis 전용 Security Group
- TLS + AUTH Token
- Secrets Manager 저장
- ECS Task Definition 환경 변수와 Secret 주입
- Node.js `redis` Client
- Socket.IO `@socket.io/redis-adapter`
- ALB Target Group `lb_cookie` Stickiness
- 브라우저 Socket.IO `withCredentials: true`
- 서버 Socket.IO CORS `credentials: true`

## Sticky Session을 유지하는 이유

Redis Adapter는 여러 Socket.IO 서버 사이에서 Broadcast 이벤트를 공유합니다.
HTTP Long Polling을 허용하는 경우에는 한 브라우저의 연속 Polling 요청을 동일 ECS Task로 보내야 하므로 Sticky Session이 별도로 필요합니다.

## 현재 구조

```text
브라우저
→ ALB lb_cookie Sticky Session
→ ECS Socket.IO Task
→ Redis Adapter
→ ElastiCache Redis Pub/Sub
→ 다른 ECS Socket.IO Task
```

## 이후 분리 시 주의사항

현재는 REST API와 Socket.IO가 같은 ECS Target Group을 사용하므로 Stickiness가 전체 백엔드 Target Group에 적용됩니다.
향후 REST API와 Socket.IO ECS Service를 분리하면 Stickiness는 Socket.IO Target Group에만 남기는 것이 좋습니다.

## 검증 순서

1. `terraform init`
2. `terraform fmt -check`
3. `terraform validate`
4. `terraform plan`
5. `terraform apply`
6. Redis Endpoint와 Secret ARN 확인
7. Docker Image 재빌드 및 ECR Push
8. ECS Service 새 Task Definition 배포
9. ECS Task 2개 실행
10. 서로 다른 브라우저에서 채팅과 입찰 이벤트 동기화 확인
