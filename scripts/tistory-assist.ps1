# 매일 저녁 실행: 가장 최근에 쓴 글을 찾아 본문을 HTML로 변환해 클립보드에 복사하고
# 티스토리 글쓰기 페이지(HTML 모드)를 브라우저로 열어둔다. 로그인/발행은 사용자가 직접.

Add-Type -AssemblyName System.Web

$repo = "E:\Claude_Project\Blog_Worker"
$postsDir = Join-Path $repo "_posts"
$tistoryWriteUrl = "https://t442-mya.tistory.com/manage/newpost/"

function Convert-MarkdownBodyToHtml {
    param([string]$Text)

    $blocks = [regex]::Split($Text.Trim(), "(?:\r?\n){2,}")
    $htmlBlocks = @()

    foreach ($block in $blocks) {
        $block = $block.Trim()
        if (-not $block) { continue }

        $lines = $block -split "\r?\n"

        if ($lines[0] -match '^\s*-\s+') {
            $items = foreach ($line in $lines) {
                $t = $line -replace '^\s*-\s+', ''
                $t = [System.Web.HttpUtility]::HtmlEncode($t)
                $t = $t -replace '\*\*(.+?)\*\*', '<strong>$1</strong>'
                "<li>$t</li>"
            }
            $htmlBlocks += "<ul>`n" + ($items -join "`n") + "`n</ul>"
        } else {
            $paragraphText = ($lines -join ' ')
            # 문장 단위(마침표/물음표/느낌표 뒤 공백)로 쪼개서 한 문장씩 <p>로 분리
            # -> 티스토리 블로그 특유의 "한 줄씩 띄어서 여백 주기" 느낌
            $sentences = [regex]::Split($paragraphText.Trim(), '(?<=[.!?])\s+') |
                Where-Object { $_.Trim() -ne '' }

            foreach ($sentence in $sentences) {
                $t = [System.Web.HttpUtility]::HtmlEncode($sentence)
                $t = $t -replace '\*\*(.+?)\*\*', '<strong>$1</strong>'
                $htmlBlocks += "<p>$t</p>"
            }
        }
    }

    return ($htmlBlocks -join "`n`n")
}

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

$bodyHtml = Convert-MarkdownBodyToHtml -Text $body
$titleEncoded = [System.Web.HttpUtility]::HtmlEncode($title)

$clipboardText = "<!-- 제목(제목 입력란에 직접 옮겨주세요): $titleEncoded -->`r`n`r`n$bodyHtml"
Set-Clipboard -Value $clipboardText

Start-Process $tistoryWriteUrl

