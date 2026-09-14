# 매일 저녁 실행: 가장 최근에 쓴 글을 찾아 본문을 클립보드에 복사하고
# 티스토리 글쓰기 페이지를 브라우저로 열어둔다. 로그인/발행은 사용자가 직접.

$repo = "E:\Claude_Project\Blog_Worker"
$postsDir = Join-Path $repo "_posts"
$tistoryWriteUrl = "https://t442-mya.tistory.com/manage/newpost/"

$latest = Get-ChildItem -Path $postsDir -Recurse -Filter *.md -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $latest) {
    exit 0
}

$raw = Get-Content -Raw -Encoding UTF8 $latest.FullName

# front matter(--- ... ---)에서 title 추출, 본문은 두 번째 --- 뒤부터
$title = ""
if ($raw -match '(?ms)^---\s*.*?^title:\s*"?(.*?)"?\s*$.*?^---\s*') {
    $title = $Matches[1]
}

$parts = [regex]::Split($raw, '(?ms)^---\s*$')
if ($parts.Count -ge 3) {
    $body = $parts[2].TrimStart("`r", "`n")
} else {
    $body = $raw
}

$clipboardText = "[제목] $title`r`n`r`n$body"
Set-Clipboard -Value $clipboardText

Start-Process $tistoryWriteUrl

