# ============================================================================
# 🔵 Bidhouse 파이프라인 STAGE 2 격발 스크립트 (Azure DR 생성)
# ============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$env:TF_VAR_azure_client_id="5c3f9330-60fb-44da-a747-84464ef72834"
$env:TF_VAR_azure_client_secret="Hbv8Q~E2DgpmhkEZQt8YF2epNXQaDcRblqJBlbgW"
$env:TF_VAR_azure_subscription_id="3a6d4b80-d67f-4ae3-93c9-d535b7f1e147"
$env:TF_VAR_azure_tenant_id="fa9d842c-a971-4682-abce-a18446a59438"



Write-Host "🚀 [STAGE 2] Azure DR 및 VPN Gateway 생성 지령 발사 준비 중..." -ForegroundColor Cyan

# 👉 [추가된 부분] STAGE 2 지령서 업데이트
Set-Content -Path "STAGE_CONFIG.txt" -Value "2" -Encoding Ascii
git add .
git commit -m "[STAGE 2] Azure Singapore DR Provisioning" -q
git push origin main -q

Write-Host "✨ [STAGE 2 상황 종료] Azure 배포 지령 전송 성공! CodePipeline을 확인하세요! (약 30~40분 소요됩니다)" -ForegroundColor Green