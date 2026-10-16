$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$PubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
if (-not (Test-Path -LiteralPath $PubspecPath -PathType Leaf)) {
    throw "pubspec.yaml tidak ditemukan di $ProjectRoot. Simpan script ini di root project Flutter MusikKu, lalu jalankan lagi."
}

Write-Host "Root project: $ProjectRoot" -ForegroundColor Cyan

# Archive code must not live under the Flutter project root; analyzer scans Dart files there.
$ArchivePath = Join-Path $ProjectRoot 'Audit_Archive'
if (Test-Path -LiteralPath $ArchivePath -PathType Container) {
    $ParentPath = Split-Path -Parent $ProjectRoot
    $ProjectName = Split-Path -Leaf $ProjectRoot
    $Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $ArchiveDestination = Join-Path $ParentPath ("{0}_Audit_Archive_{1}" -f $ProjectName, $Stamp)
    $Suffix = 1
    while (Test-Path -LiteralPath $ArchiveDestination) {
        $ArchiveDestination = Join-Path $ParentPath ("{0}_Audit_Archive_{1}_{2}" -f $ProjectName, $Stamp, $Suffix)
        $Suffix++
    }

    Move-Item -LiteralPath $ArchivePath -Destination $ArchiveDestination
    Write-Host "Arsip dipindahkan keluar dari project ke:" -ForegroundColor Green
    Write-Host "  $ArchiveDestination"
    Write-Host 'Isi arsip dipertahankan; tidak ada file yang dihapus.' -ForegroundColor Green
} else {
    Write-Host 'Folder Audit_Archive tidak ditemukan di root; tidak ada arsip yang dipindahkan.' -ForegroundColor Yellow
}

# Detect any remaining archived Dart sources accidentally nested under the project root.
$RemainingArchiveDart = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.dart' -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '[\\/](Audit_Archive|analyzer_fix_backup[^\\/]*|unused_source_candidates)[\\/]' }
if ($RemainingArchiveDart) {
    Write-Warning 'Masih ada file Dart yang tampak seperti arsip di bawah project root:'
    $RemainingArchiveDart | ForEach-Object { Write-Host "  $($_.FullName)" }
    Write-Warning 'Pindahkan folder arsip tersebut ke luar root sebelum menilai hasil analyzer.'
}

$ReportPath = Join-Path $env:TEMP ("MusikKu_flutter_analyze_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Write-Host 'Menjalankan flutter analyze...' -ForegroundColor Cyan
$AnalyzeOutput = & flutter analyze 2>&1
$AnalyzeExitCode = $LASTEXITCODE
$AnalyzeOutput | Tee-Object -FilePath $ReportPath | ForEach-Object { Write-Host $_ }
Write-Host "Laporan analyzer: $ReportPath"

if ($AnalyzeExitCode -eq 0) {
    Write-Host 'flutter analyze berhasil.' -ForegroundColor Green
    exit 0
}

Write-Warning "flutter analyze masih mengembalikan exit code $AnalyzeExitCode. Periksa laporan di atas."
Write-Warning 'Jika error masih menunjuk ke folder backup/arsip, pindahkan folder itu ke luar root. Jika menunjuk ke lib/ atau test/ aktif, kirim error aktif tersebut.'
exit $AnalyzeExitCode
