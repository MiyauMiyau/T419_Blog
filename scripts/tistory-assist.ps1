# 매일 저녁 실행: 가장 최근에 쓴 글을 찾아 HTML로 변환한 뒤,
# 클립보드에 바로 넣지 않고 "미리보기 + 확인 버튼" 페이지를 만들어 브라우저로 연다.
# 사용자가 미리보기를 보고 버튼을 눌러야 그때 클립보드에 복사 + 티스토리 글쓰기 페이지가 열린다.

Add-Type -AssemblyName System.Web

$repo = "E:\Claude_Project\Blog_Worker"
$postsDir = Join-Path $repo "_posts"
$previewDir = Join-Path $repo "tistory-preview"
$previewFile = Join-Path $previewDir "latest.html"
$tistoryWriteUrl = "https://t442-mya.tistory.com/manage/newpost/"

function Convert-MarkdownBodyToHtml {
    param([string]$Text)

    # 티스토리 에디터(카카오 에디터)가 실제로 쓰는 마크업에 맞춤:
    # - 모든 문단에 data-ke-size="size16"
    # - 빈 줄 대신 "&nbsp;만 있는 문단"으로 여백을 만듦
    # - 첫 블록(인트로)은 점(.) 세 줄로 열고, 그 뒤에 구분선(hr)
    $gap = '<p data-ke-size="size16">&nbsp;</p>'
    $hr = '<hr contenteditable="false" data-ke-type="horizontalRule" data-ke-style="style3" />'

    $blocks = [regex]::Split($Text.Trim(), "(?:\r?\n){2,}")
    $out = @()

    $out += '<p data-ke-size="size16">.</p>'
    $out += '<p data-ke-size="size16">.</p>'
    $out += '<p data-ke-size="size16">.</p>'
    $out += $gap

    for ($bi = 0; $bi -lt $blocks.Count; $bi++) {
        $block = $blocks[$bi].Trim()
        if (-not $block) { continue }

        $lines = $block -split "\r?\n"

        if ($lines[0] -match '^\s*-\s+') {
            $items = foreach ($line in $lines) {
                $t = $line -replace '^\s*-\s+', ''
                $t = [System.Web.HttpUtility]::HtmlEncode($t)
                $t = $t -replace '\*\*(.+?)\*\*', '<strong>$1</strong>'
                "<li>$t</li>"
            }
            $out += '<ul style="list-style-type: disc;" data-ke-list-type="disc">' + "`n" + ($items -join "`n") + "`n</ul>"
            $out += $gap
        } else {
            $paragraphText = ($lines -join ' ')
            # 문장 단위(마침표/물음표/느낌표 뒤 공백)로 쪼개서 한 문장씩 <p>로 분리하고
            # 문장 사이사이에 여백 문단을 넣어 "한 줄씩 띄어서 읽는" 느낌을 냄
            $sentences = [regex]::Split($paragraphText.Trim(), '(?<=[.!?])\s+') |
                Where-Object { $_.Trim() -ne '' }

            for ($si = 0; $si -lt $sentences.Count; $si++) {
                $t = [System.Web.HttpUtility]::HtmlEncode($sentences[$si])
                $t = $t -replace '\*\*(.+?)\*\*', '<strong>$1</strong>'
                $out += "<p data-ke-size=`"size16`">$t</p>"
                $out += $gap
            }
        }

        # 첫 블록(인트로) 다음에만 구분선 — 인트로와 본문을 시각적으로 분리
        if ($bi -eq 0 -and $blocks.Count -gt 1) {
            $out += $hr
            $out += $gap
        }
    }

    return ($out -join "`n")
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

# 실제로 클립보드에 들어갈(=티스토리에 붙여넣을) 원본 소스
$clipboardText = "<!-- 제목(제목 입력란에 직접 옮겨주세요): $titleEncoded -->`r`n`r`n$bodyHtml"

if (-not (Test-Path $previewDir)) {
    New-Item -ItemType Directory -Path $previewDir | Out-Null
}

$previewHtml = @"
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<title>미리보기 - $titleEncoded</title>
<style>
  body { font-family: -apple-system, "Malgun Gothic", "맑은 고딕", sans-serif; max-width: 720px; margin: 0 auto; padding: 0 24px 80px; line-height: 1.9; color: #222; background: #fafafa; }
  h1 { font-size: 1.6em; padding: 24px 0 16px; margin: 0; }
  #content p { margin: 1.3em 0; }
  #content ul { margin: 1.3em 0; padding-left: 1.4em; }
  .toolbar { position: sticky; top: 0; background: #fafafa; padding: 16px 0; border-bottom: 1px solid #ddd; margin-bottom: 8px; display: flex; align-items: center; gap: 12px; z-index: 10; }
  button { font-size: 1em; padding: 10px 20px; border-radius: 8px; border: none; background: #0064ff; color: white; cursor: pointer; }
  button:hover { background: #0050cc; }
  button:disabled { background: #9cbcf0; cursor: default; }
  .status { color: #666; }
  .card { background: #fff; border-radius: 12px; padding: 8px 32px 32px; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
</style>
</head>
<body>
  <div class="toolbar">
    <button id="copyBtn">복사하고 티스토리 열기</button>
    <span class="status" id="status"></span>
  </div>
  <div class="card">
    <h1>$titleEncoded</h1>
    <div id="content">
$bodyHtml
    </div>
  </div>

  <textarea id="rawSrc" style="position:absolute; left:-9999px; top:-9999px;">$clipboardText</textarea>

  <script>
    const btn = document.getElementById('copyBtn');
    const status = document.getElementById('status');
    const ta = document.getElementById('rawSrc');

    btn.addEventListener('click', () => {
      ta.style.display = 'block';
      ta.focus();
      ta.select();
      let ok = false;
      try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
      ta.style.display = 'none';

      if (ok) {
        status.textContent = '복사됨! 티스토리 여는 중...';
        btn.disabled = true;
        window.open('$tistoryWriteUrl', '_blank');
      } else {
        status.textContent = '복사 실패 — 직접 아래 텍스트를 선택해서 복사해주세요.';
        ta.style.display = 'block';
        ta.style.position = 'static';
        ta.style.width = '100%';
        ta.style.height = '200px';
      }
    });
  </script>
</body>
</html>
"@

Set-Content -Path $previewFile -Value $previewHtml -Encoding UTF8

Start-Process $previewFile

