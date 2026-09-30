# ============================================================================
# 🚀 Bidhouse 파이프라인 STAGE 1 격발 스크립트 (AWS 본진 생성)
# ============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$env:TF_VAR_azure_client_id="REPLACE_ME"
$env:TF_VAR_azure_client_secret="REPLACE_ME"
$env:TF_VAR_azure_subscription_id="REPLACE_ME"
$env:TF_VAR_azure_tenant_id="REPLACE_ME"
$env:TF_VAR_aws_access_key_id="REPLACE_ME"
$env:TF_VAR_aws_secret_access_key="REPLACE_ME"

Write-Host "🤖 [1단계] 00번 파이프라인 공장 및 S3 금고 상태 자동 점검..." -ForegroundColor Cyan

Push-Location "00-pipeline"
if (-not (Test-Path ".terraform")) {
    Write-Host "⚙️  00번 방 쌩 백지 상태 감지! 순정 통로 개설 중..." -ForegroundColor Yellow
    terraform init
}
Write-Host "🏗️  00번 공장 및 장부 금고 S3 강제 동기화(Apply) 시동..." -ForegroundColor Yellow
terraform apply -auto-approve

$s3_bucket_name = (terraform output -raw global_tfstate_bucket_name)
if ($s3_bucket_name) { $s3_bucket_name = $s3_bucket_name.Trim() }
Pop-Location

Write-Host "⏳ AWS IAM 권한 증서가 본진에 복제될 때까지 15초간 안전하게 대기 중..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

if (-not $s3_bucket_name -or $s3_bucket_name -match "Error" -or $s3_bucket_name -eq "") {
    Write-Host "❌ [비상] S3 백엔드 버킷 이름을 가져오지 못했습니다! 00번 방 설정을 확인하세요." -ForegroundColor Red
    Exit
}

Write-Host "🎯 추출된 S3 금고 주소 획득 완료 -> [$s3_bucket_name]" -ForegroundColor Green
Write-Host "🧹 꼬여버린 깃 캐시 및 하위 모듈 숨은 찌꺼기 완전 세탁..." -ForegroundColor Cyan

foreach ($dir in @("00-pipeline", "01-aws-seoul-network", "02-azure-singapore-dr", "03-cross-cloud", "04-aws-seoul-app-foundation")) {
    if (Test-Path "$dir\.git") { Remove-Item -Recurse -Force "$dir\.git" -ErrorAction SilentlyContinue }
}

Remove-Item -Recurse -Force .git -ErrorAction SilentlyContinue

git init -q
git remote add origin https://github.com/minjo46/bidhouse.git
git branch -M main

Write-Host "⚙️  01~04번 방에 S3 금고 고속도로 통로(Init) 원터치 개통식 가동..." -ForegroundColor Cyan

$target_dirs = @("01-aws-seoul-network", "02-azure-singapore-dr", "03-cross-cloud", "04-aws-seoul-app-foundation")
foreach ($dir in $target_dirs) {
    if (Test-Path $dir) {
        Push-Location $dir
        terraform init -reconfigure -backend-config="bucket=$s3_bucket_name"
        Pop-Location
        Write-Host "🟢 [$dir] 통로 개통 성공!" -ForegroundColor Green
    }
}

Write-Host "🚀 [STAGE 1] 깃허브 본진으로 스파이크 발사!!!" -ForegroundColor Magenta

# 👉 [추가된 부분] CodeBuild에 전달할 STAGE 1 지령서 파일 생성
Set-Content -Path "STAGE_CONFIG.txt" -Value "1" -Encoding Ascii

git add 00-pipeline/*
git add 01-aws-seoul-network/*
git add 02-azure-singapore-dr/*
git add 03-cross-cloud/*
git add 04-aws-seoul-app-foundation/*
git add app/
git add failback_lambda/
git add promote_lambda/
git add s3_sync_lambda/
git add buildspec.yml
git add STAGE_CONFIG.txt

if (Test-Path "README.md") { git add README.md }
if (Test-Path ".gitignore") { git add .gitignore } 

git commit -m "[STAGE 1] AWS Seoul Network & App Deploy" -q
git push origin main -f -q

Write-Host "✨ [STAGE 1 상황 종료] AWS 배포 지령 전송 성공! CodePipeline에서 초록불을 확인하세요!" -ForegroundColor Green