# ============================================================================
# 🟡 Bidhouse 파이프라인 STAGE 3 격발 스크립트 (크로스 클라우드 연동)
# ============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$env:TF_VAR_azure_client_id="5c3f9330-60fb-44da-a747-84464ef72834"
$env:TF_VAR_azure_client_secret="Hbv8Q~E2DgpmhkEZQt8YF2epNXQaDcRblqJBlbgW"
$env:TF_VAR_azure_subscription_id="3a6d4b80-d67f-4ae3-93c9-d535b7f1e147"
$env:TF_VAR_azure_tenant_id="fa9d842c-a971-4682-abce-a18446a59438"


Write-Host "🚀 [STAGE 3] 크로스 클라우드 연결 및 DB/스토리지 복제 지령 발사 준비 중..." -ForegroundColor Yellow

# 👉 [추가된 부분] STAGE 3 지령서 업데이트
Set-Content -Path "STAGE_CONFIG.txt" -Value "3" -Encoding Ascii
git add STAGE_CONFIG.txt
git add buildspec.yml
git commit -m "[STAGE 3] Cross-Cloud VPN & DB Replication" -q
git push origin main -q

Write-Host "✨ [STAGE 3 상황 종료] 멀티 클라우드 연동 지령 전송 성공! CodePipeline을 확인하세요!" -ForegroundColor Green