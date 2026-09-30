# ============================================================================
# 💥 Bidhouse 완전히 다 날려버리는 최후의 심판 스크립트 (ALL DESTROY)
# ============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 애저 자격 증명 강제 주입
$env:TF_VAR_azure_client_id="5c3f9330-60fb-44da-a747-84464ef72834"
$env:TF_VAR_azure_client_secret="Hbv8Q~E2DgpmhkEZQt8YF2epNXQaDcRblqJBlbgW"
$env:TF_VAR_azure_subscription_id="3a6d4b80-d67f-4ae3-93c9-d535b7f1e147"
$env:TF_VAR_azure_tenant_id="fa9d842c-a971-4682-abce-a18446a59438"

Write-Host "!!! START ALL DESTROY PIPELINE !!!" -ForegroundColor Red

# 1. 00-pipeline 방에서 S3 금고(장부 버킷) 이름 동적으로 추출하기
$s3_bucket_name = ""
if (Test-Path "00-pipeline") {
    Push-Location "00-pipeline"
    terraform init -reconfigure
    $s3_bucket_name = (terraform output -raw global_tfstate_bucket_name)
    if ($s3_bucket_name) { $s3_bucket_name = $s3_bucket_name.Trim() }
    Pop-Location
    Write-Host "🎯 감지된 S3 백엔드 버킷 이름: [$s3_bucket_name]" -ForegroundColor Cyan
}

# 2. 하위 리소스 역순으로 완전 파괴 (03 -> 01 -> 04)
$destroy_dirs = @("03-cross-cloud", "01-aws-seoul-network", "04-aws-seoul-app-foundation")

foreach ($dir in $destroy_dirs) {
    if (Test-Path $dir) {
        Write-Host "💥 자원 파괴 진입: $dir" -ForegroundColor Yellow
        Push-Location $dir
        
        # S3 백엔드 강제 연결 후 파괴 (값 멈춤 방지)
        if ($s3_bucket_name) {
            terraform init -reconfigure -backend-config="bucket=$s3_bucket_name"
        } else {
            terraform init -reconfigure
        }
        terraform destroy -auto-approve
        
        Pop-Location
        Write-Host "✅ 파괴 완료: $dir" -ForegroundColor Green
    }
}

# 3. 마지막으로 00번 본진(파이프라인 인프라) 파괴
if (Test-Path "00-pipeline") {
    Write-Host "💥 본진 파괴 진입: 00-pipeline" -ForegroundColor Yellow
    Push-Location "00-pipeline"
    terraform init -reconfigure
    terraform destroy -auto-approve
    Pop-Location
    Write-Host "✅ 본진 파괴 완료: 00-pipeline" -ForegroundColor Green
}

# 4. S3 버킷 내부에 남아있는 유령 파일 및 상태 잠금 완벽 강제 청소
Write-Host "🧹 S3 장부 버킷 내용물 완벽 강제 강탈 청소 및 완전 포맷 가동..." -ForegroundColor Cyan

aws s3 rm s3://bidhouse-global-immutable-2026 --recursive --region ap-northeast-2 2>$null
aws s3 rb s3://bidhouse-global-immutable-2026 --force --region ap-northeast-2 2>$null

aws s3 rm s3://bidhouse-pipeline-artifacts-2026 --recursive --region ap-northeast-2 2>$null
aws s3 rb s3://bidhouse-pipeline-artifacts-2026 --force --region ap-northeast-2 2>$null

Write-Host "🎨 !!! ALL CLEAN !!! PERFECT CLEAN !!!" -ForegroundColor Cyan
Write-Host "클라우드가 완벽한 공허 상태(백지)가 되었습니다. 스트레스받지 마시고 푹 쉬러 가세요!" -ForegroundColor Green