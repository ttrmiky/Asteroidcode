$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Utf8 = [System.Text.Encoding]::UTF8
$Failures = New-Object System.Collections.Generic.List[string]

function Read-Text {
  param([Parameter(Mandatory)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, $Utf8)
}

function Assert-True {
  param(
    [Parameter(Mandatory)][bool]$Condition,
    [Parameter(Mandatory)][string]$Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

function Get-Attribute {
  param(
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Name
  )

  $match = [regex]::Match($Tag, "(?is)\s$Name\s*=\s*[""']([^""']+)[""']")
  if ($match.Success) {
    return $match.Groups[1].Value
  }

  return $null
}

function Resolve-LocalPath {
  param(
    [Parameter(Mandatory)][System.IO.FileInfo]$FromFile,
    [Parameter(Mandatory)][string]$Reference
  )

  $withoutQuery = ($Reference -split '\?')[0]
  $pathPart = ($withoutQuery -split '#')[0]

  if ([string]::IsNullOrWhiteSpace($pathPart)) {
    return $FromFile.FullName
  }

  $normalized = $pathPart -replace '/', [System.IO.Path]::DirectorySeparatorChar
  if ([System.IO.Path]::IsPathRooted($normalized)) {
    $normalized = $normalized.TrimStart('\', '/')
    return [System.IO.Path]::GetFullPath((Join-Path $Root $normalized))
  }

  return [System.IO.Path]::GetFullPath((Join-Path $FromFile.DirectoryName $normalized))
}

function Test-Case {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][scriptblock]$Body
  )

  try {
    & $Body
    Write-Host "ok - $Name"
  } catch {
    $Failures.Add("$Name :: $($_.Exception.Message)")
    Write-Host "not ok - $Name"
  }
}

$HtmlFiles = Get-ChildItem -Path $Root -Recurse -File -Filter '*.html' |
  Where-Object { $_.FullName -notmatch '\\.git\\|\\.vs\\' }

$SiteCss = Join-Path $Root 'assets\site.css'

Test-Case 'HTML pages expose required metadata' {
  foreach ($file in $HtmlFiles) {
    $html = Read-Text $file.FullName

    Assert-True ($html -match '(?is)<!doctype html>') "$($file.Name) is missing doctype"
    Assert-True ($html -match '(?is)<html\b[^>]*\blang=["'']it["'']') "$($file.Name) is missing lang=it"
    Assert-True ($html -match '(?is)<meta\b[^>]*name=["'']viewport["'']') "$($file.Name) is missing viewport meta"
    Assert-True ($html -match '(?is)<title>[^<]{4,}</title>') "$($file.Name) is missing a meaningful title"

    $isNoIndex = $html -match '(?is)<meta\b[^>]*name=["'']robots["''][^>]*content=["''][^"'']*noindex'
    if (-not $isNoIndex) {
      Assert-True ($html -match '(?is)<meta\b[^>]*name=["'']description["'']') "$($file.Name) is missing meta description"
    }
  }
}

Test-Case 'Asteroid Code branding is consistent' {
  $homeHtml = Read-Text (Join-Path $Root 'index.html')
  $logo = Read-Text (Join-Path $Root 'assets\asteroid-logo.svg')

  Assert-True ($homeHtml -match '<title>Asteroid Code \|') 'Home title does not use Asteroid Code'
  Assert-True ($homeHtml -match 'aria-label="Asteroid Code"') 'Home navbar aria-label does not use Asteroid Code'
  Assert-True ($logo -match 'Asteroid Code logo') 'Logo title does not use Asteroid Code'
  Assert-True ($logo -match 'minimal asteroid icon') 'Logo is not described as a minimal asteroid icon'
  Assert-True ($logo -notmatch '(?is)<rect|code mark|M40 82|M88 46') 'Logo still contains the old code-mark artwork'
  Assert-True ($logo -notmatch 'dinosaur') 'Logo still describes the old illustrated mark'

  foreach ($file in $HtmlFiles) {
    $html = Read-Text $file.FullName
    if ($html -match '(?is)<nav\b') {
      Assert-True ($html -match 'brand-main">Asteroid</span><span class="brand-code">code</span>') "$($file.Name) does not use the split wordmark"
    }
    Assert-True ($html -notmatch 'aria-label="Asteroid"') "$($file.Name) still has the old aria brand"
  }
}

Test-Case 'Hero uses the new geometric interactive treatment' {
  $homeHtml = Read-Text (Join-Path $Root 'index.html')
  $packages = Read-Text (Join-Path $Root 'pacchetti.html')
  $allSiteText = ($HtmlFiles | ForEach-Object { Read-Text $_.FullName }) -join "`n"
  $sharedCss = Read-Text $SiteCss

  Assert-True ($homeHtml -match 'data-hero-ambient') 'Home hero is missing the ambient interaction hook'
  Assert-True ($homeHtml -match 'hero-mesh') 'Home hero is missing the geometric mesh'
  Assert-True ($homeHtml -match 'pointermove') 'Home hero is missing pointer interaction'
  Assert-True ($homeHtml -notmatch 'url\("assets/hero') 'Home CSS still references a bitmap hero background'
  Assert-True ($packages -notmatch 'url\("assets/hero') 'Packages CSS still references a bitmap hero background'
  Assert-True ($sharedCss -notmatch 'hero-(process-map|impact-workflow|command-center)') 'Shared CSS still references old hero imagery'
  Assert-True ($allSiteText -notmatch 'hero-(process-map|impact-workflow|command-center)') 'HTML still references old hero imagery'
}

Test-Case 'Pages use one local stylesheet without inline CSS' {
  Assert-True (Test-Path $SiteCss) 'assets/site.css is missing'

  $localCss = Get-ChildItem -Path (Join-Path $Root 'assets') -File -Filter '*.css'
  Assert-True ($localCss.Count -eq 1) "Expected exactly one local CSS file, found $($localCss.Count)"
  Assert-True ($localCss[0].Name -eq 'site.css') "Expected site.css, found $($localCss[0].Name)"

  foreach ($file in $HtmlFiles) {
    $html = Read-Text $file.FullName
    $siteCssLinks = [regex]::Matches($html, '(?is)<link\b[^>]*href=["''](?:\.\./)?assets/site\.css["''][^>]*rel=["'']stylesheet["''][^>]*>')

    Assert-True ($siteCssLinks.Count -eq 1) "$($file.Name) must link assets/site.css exactly once"
    Assert-True ($html -notmatch '(?is)<style\b') "$($file.Name) still contains an inline style block"
    Assert-True ($html -notmatch '(?is)\sstyle=["'']') "$($file.Name) still contains inline style attributes"
  }
}

Test-Case 'Local images exist and include alt attributes' {
  foreach ($file in $HtmlFiles) {
    $html = Read-Text $file.FullName
    $images = [regex]::Matches($html, '(?is)<img\b[^>]*>')

    foreach ($image in $images) {
      $tag = $image.Value
      $src = Get-Attribute $tag 'src'
      Assert-True (-not [string]::IsNullOrWhiteSpace($src)) "$($file.Name) has an image without src"
      Assert-True ($tag -match '(?is)\salt\s*=') "$($file.Name) image '$src' is missing alt"

      if ($src -match '^(https?:|data:|mailto:|tel:)') {
        continue
      }

      $target = Resolve-LocalPath $file $src
      Assert-True (Test-Path $target) "$($file.Name) references missing image $src"
    }
  }
}

Test-Case 'Internal links resolve to files and anchors' {
  foreach ($file in $HtmlFiles) {
    $html = Read-Text $file.FullName
    $links = [regex]::Matches($html, '(?is)<a\b[^>]*\bhref=["'']([^"'']+)["'']')

    foreach ($link in $links) {
      $href = [System.Net.WebUtility]::HtmlDecode($link.Groups[1].Value)
      if ($href -match '^(https?:|mailto:|tel:|javascript:)') {
        continue
      }

      $target = Resolve-LocalPath $file $href
      Assert-True (Test-Path $target) "$($file.Name) references missing link target $href"

      if ($href -match '#(.+)$') {
        $anchor = [regex]::Escape($Matches[1])
        $targetHtml = Read-Text $target
        $hasAnchor = $targetHtml -match "(?is)\b(id|name)=[""']$anchor[""']"
        Assert-True $hasAnchor "$($file.Name) references missing anchor $href"
      }
    }
  }
}

Test-Case 'JSON-LD blocks parse as JSON' {
  foreach ($file in $HtmlFiles) {
    $html = Read-Text $file.FullName
    $scripts = [regex]::Matches($html, '(?is)<script\b[^>]*type=["'']application/ld\+json["''][^>]*>(.*?)</script>')

    foreach ($script in $scripts) {
      $json = [System.Net.WebUtility]::HtmlDecode($script.Groups[1].Value.Trim())
      try {
        $null = $json | ConvertFrom-Json
      } catch {
        throw "$($file.Name) has invalid JSON-LD: $($_.Exception.Message)"
      }
    }
  }
}

Test-Case 'SEO social metadata and headings are complete' {
  foreach ($file in $HtmlFiles) {
    $html = Read-Text $file.FullName
    $isNoIndex = $html -match '(?is)<meta\b[^>]*name=["'']robots["''][^>]*content=["''][^"'']*noindex'

    if ($isNoIndex) {
      continue
    }

    $h1s = [regex]::Matches($html, '(?is)<h1\b')
    Assert-True ($h1s.Count -eq 1) "$($file.Name) should have exactly one h1"
    Assert-True ($html -match '(?is)<link\b[^>]*rel=["'']canonical["''][^>]*href=["'']https://www\.asteroidcode\.it/[^"'']*["'']') "$($file.Name) is missing canonical URL"
    Assert-True ($html -match '(?is)<link\b[^>]*rel=["'']alternate["''][^>]*hreflang=["'']it["'']') "$($file.Name) is missing it hreflang"
    Assert-True ($html -match '(?is)<link\b[^>]*rel=["'']alternate["''][^>]*hreflang=["'']x-default["'']') "$($file.Name) is missing x-default hreflang"

    foreach ($property in @('og:type','og:locale','og:site_name','og:title','og:description','og:url','og:image','og:image:alt')) {
      Assert-True ($html -match "(?is)<meta\b[^>]*property=[""']$([regex]::Escape($property))[""'][^>]*content=[""'][^""']+[""']") "$($file.Name) is missing $property"
    }

    foreach ($name in @('twitter:card','twitter:title','twitter:description','twitter:image','twitter:image:alt')) {
      Assert-True ($html -match "(?is)<meta\b[^>]*name=[""']$([regex]::Escape($name))[""'][^>]*content=[""'][^""']+[""']") "$($file.Name) is missing $name"
    }
  }
}

Test-Case 'Sitemap lists indexable canonicals with lastmod' {
  $sitemap = Read-Text (Join-Path $Root 'sitemap.xml')
  Assert-True ($sitemap -match '<lastmod>2026-05-28</lastmod>') 'Sitemap is missing lastmod entries'

  foreach ($file in $HtmlFiles) {
    $html = Read-Text $file.FullName
    $isNoIndex = $html -match '(?is)<meta\b[^>]*name=["'']robots["''][^>]*content=["''][^"'']*noindex'
    if ($isNoIndex) {
      continue
    }

    $canonical = Get-Attribute ([regex]::Match($html, '(?is)<link\b[^>]*rel=["'']canonical["''][^>]*>').Value) 'href'
    Assert-True (-not [string]::IsNullOrWhiteSpace($canonical)) "$($file.Name) is missing canonical"
    Assert-True ($sitemap -match [regex]::Escape("<loc>$canonical</loc>")) "$($file.Name) canonical is missing from sitemap"
  }
}

if ($Failures.Count -gt 0) {
  Write-Host ''
  Write-Host 'Failures:'
  foreach ($failure in $Failures) {
    Write-Host " - $failure"
  }
  exit 1
}

Write-Host ''
Write-Host "All static-site checks passed ($($HtmlFiles.Count) HTML files)."
