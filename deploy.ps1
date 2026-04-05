chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$repoName   = "japan-song-quiz"
$htmlFile   = "japan_song_quiz.html"
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$htmlPath   = Join-Path $scriptDir $htmlFile
$configPath = Join-Path $scriptDir ".deploy-config"

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Magenta
Write-Host "    J-POP Quiz  -  GitHub Pages Auto Deploy" -ForegroundColor Magenta
Write-Host "  ============================================" -ForegroundColor Magenta
Write-Host ""

if (-not (Test-Path $htmlPath)) {
    Write-Host "  [!] $htmlFile 파일을 찾을 수 없습니다." -ForegroundColor Red
    Write-Host "      이 스크립트를 $htmlFile 과 같은 폴더에 두세요." -ForegroundColor Red
    pause; exit 1
}

# ── 설정 로드 / 최초 입력 ──
if (Test-Path $configPath) {
    $cfg = Get-Content $configPath
    $username = $cfg[0]
    $token    = $cfg[1]
    Write-Host "  저장된 계정: $username" -ForegroundColor Cyan
    $change = Read-Host "  이 계정으로 배포할까요? (Y/n)"
    if ($change -eq 'n') { Remove-Item $configPath }
}

if (-not (Test-Path $configPath)) {
    Write-Host "  --- 최초 설정 (한 번만 하면 됩니다) ---" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. GitHub 토큰이 필요합니다. 아래 링크를 브라우저에 붙여넣기:" -ForegroundColor White
    Write-Host ""
    Write-Host "     https://github.com/settings/tokens/new?scopes=repo&description=quiz-deploy" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  2. 'Expiration' 은 원하는 기간으로 설정" -ForegroundColor White
    Write-Host "  3. [Generate token] 클릭 후 'ghp_...' 토큰 복사" -ForegroundColor White
    Write-Host ""
    $username = Read-Host "  GitHub 아이디"
    $token    = Read-Host "  GitHub 토큰 (ghp_...)"
    @($username, $token) | Out-File $configPath -Encoding utf8
    Write-Host ""
    Write-Host "  설정 저장 완료 (.deploy-config)" -ForegroundColor Green
}

if (-not (Test-Path $configPath)) {
    $cfg = Get-Content $configPath
    $username = $cfg[0]
    $token    = $cfg[1]
}

$headers = @{
    Authorization  = "token $token"
    Accept         = "application/vnd.github+json"
    "Content-Type" = "application/json; charset=utf-8"
}

# ── 1. 저장소 생성 ──
Write-Host ""
Write-Host "  [1/4] 저장소 확인..." -ForegroundColor Yellow
try {
    Invoke-RestMethod -Uri "https://api.github.com/repos/$username/$repoName" -Headers $headers -ErrorAction Stop | Out-Null
    Write-Host "    -> 저장소 존재 확인" -ForegroundColor Green
} catch {
    Write-Host "    -> 새 저장소 생성 중..." -ForegroundColor Cyan
    try {
        $body = @{ name=$repoName; description="J-POP & Anime Song Quiz"; public=$true; auto_init=$false } | ConvertTo-Json
        Invoke-RestMethod -Uri "https://api.github.com/user/repos" -Method Post -Headers $headers -Body $body -ErrorAction Stop | Out-Null
        Write-Host "    -> 저장소 생성 완료" -ForegroundColor Green
    } catch {
        Write-Host "    [!] 저장소 생성 실패: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "        아이디/토큰을 확인하세요. .deploy-config 파일을 삭제 후 다시 시도." -ForegroundColor Red
        pause; exit 1
    }
}

# ── 파일 업로드 함수 ──
function Upload-File($filePath, $repoPath, $commitMsg) {
    $bytes   = [System.IO.File]::ReadAllBytes($filePath)
    $base64  = [Convert]::ToBase64String($bytes)

    $sha = $null
    try {
        $existing = Invoke-RestMethod -Uri "https://api.github.com/repos/$username/$repoName/contents/$repoPath" -Headers $headers -ErrorAction Stop
        $sha = $existing.sha
    } catch {}

    $bodyObj = @{ message=$commitMsg; content=$base64 }
    if ($sha) { $bodyObj.sha = $sha }
    $body = $bodyObj | ConvertTo-Json

    Invoke-RestMethod -Uri "https://api.github.com/repos/$username/$repoName/contents/$repoPath" -Method Put -Headers $headers -Body $body -ErrorAction Stop | Out-Null
}

# ── 2. 퀴즈 파일 업로드 ──
Write-Host "  [2/4] 퀴즈 파일 업로드..." -ForegroundColor Yellow
try {
    Upload-File $htmlPath $htmlFile "update: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    Write-Host "    -> $htmlFile 업로드 완료" -ForegroundColor Green
} catch {
    Write-Host "    [!] 업로드 실패: $($_.Exception.Message)" -ForegroundColor Red
    pause; exit 1
}

# ── 3. index.html 리다이렉트 생성 ──
Write-Host "  [3/4] index.html 설정..." -ForegroundColor Yellow
$indexTmp = Join-Path $env:TEMP "index_redirect.html"
"<!DOCTYPE html><html><head><meta charset=`"utf-8`"><meta http-equiv=`"refresh`" content=`"0;url=$htmlFile`"><title>Redirecting...</title></head><body></body></html>" | Out-File $indexTmp -Encoding utf8
try {
    Upload-File $indexTmp "index.html" "index redirect"
    Write-Host "    -> index.html 설정 완료" -ForegroundColor Green
} catch {
    Write-Host "    -> (건너뜀)" -ForegroundColor Gray
}
Remove-Item $indexTmp -ErrorAction SilentlyContinue

# ── 4. GitHub Pages 활성화 ──
Write-Host "  [4/4] GitHub Pages 활성화..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
try {
    $pgBody = @{ source=@{ branch="main"; path="/" } } | ConvertTo-Json -Depth 3
    Invoke-RestMethod -Uri "https://api.github.com/repos/$username/$repoName/pages" -Method Post -Headers $headers -Body $pgBody -ErrorAction Stop | Out-Null
    Write-Host "    -> Pages 활성화 완료" -ForegroundColor Green
} catch {
    Write-Host "    -> Pages 이미 활성화됨" -ForegroundColor Green
}

# ── 완료 ──
$siteUrl = "https://$username.github.io/$repoName/"

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Magenta
Write-Host "    배포 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "    $siteUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "    1~2분 뒤에 접속 가능합니다." -ForegroundColor Gray
Write-Host "    이 링크를 카톡으로 보내세요!" -ForegroundColor Yellow
Write-Host "  ============================================" -ForegroundColor Magenta
Write-Host ""

try { Set-Clipboard $siteUrl; Write-Host "  (링크가 클립보드에 복사되었습니다)" -ForegroundColor Gray } catch {}

Write-Host ""
pause
