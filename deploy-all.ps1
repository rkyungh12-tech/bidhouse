# deploy-all.ps1

Write-Host "🚀 모든 인프라 및 앱 통합 배포를 시작합니다..." -ForegroundColor Cyan

# 1. AWS 서울 인프라 및 애플리케이션 배포
Write-Host "Step 1: 배포 중... (AWS Seoul)" -ForegroundColor Yellow
if (-not (Test-Path "./push1-aws.ps1")) { Write-Error "push1 파일 없음"; exit }
./push1-aws.ps1 
if ($LASTEXITCODE -ne 0) { Write-Error "AWS 배포 실패! 다음 단계 진행 중단."; exit }

# 2. Azure 싱가포르 DR 애플리케이션 배포
Write-Host "Step 2: 배포 중... (Azure Singapore DR)" -ForegroundColor Yellow
if (-not (Test-Path "./push2-azure.ps1")) { Write-Error "push2 파일 없음"; exit }
./push2-azure.ps1
if ($LASTEXITCODE -ne 0) { Write-Error "Azure 배포 실패! 다음 단계 진행 중단."; exit }

# 3. 크로스 클라우드 동기화 (Route 53, WAF 등)
Write-Host "Step 3: 배포 중... (Cross-Cloud Sync)" -ForegroundColor Yellow
if (-not (Test-Path "./push3-cross.ps1")) { Write-Error "push3 파일 없음"; exit }
./push3-cross.ps1
if ($LASTEXITCODE -ne 0) { Write-Error "동기화 실패!"; exit }

Write-Host "✅ 모든 배포가 성공적으로 완료되었습니다!" -ForegroundColor Green