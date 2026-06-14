# test-sync.ps1
# Integration tests for Sync-AbsToBookOrbit.ps1

$ErrorActionPreference = "Stop"
$global:TestsFailed = $false

$TempMediaDir = Join-Path $PSScriptRoot "test-temp-media"

# Setup temporary test environment
if (Test-Path $TempMediaDir) {
    Remove-Item -Recurse -Force $TempMediaDir
}
New-Item -ItemType Directory -Path $TempMediaDir | Out-Null

# ----------------- Helper Functions -----------------
# Creates a mock book directory and populates it with a metadata.json file
function Create-BookDir($BookName, $MetadataJson) {
    $BookDir = Join-Path $TempMediaDir $BookName
    New-Item -ItemType Directory -Path $BookDir | Out-Null
    $MetadataJson | Out-File -FilePath (Join-Path $BookDir "metadata.json") -Encoding utf8
    return $BookDir
}

# Loads and parses a generated metadata.opf file as XML
function Get-OpfXml($BookDir) {
    $OpfPath = Join-Path $BookDir "metadata.opf"
    if (-not (Test-Path $OpfPath)) {
        return $null
    }
    [xml]$Xml = Get-Content -Raw -Path $OpfPath
    return $Xml
}

# Selects and returns the text value of an XML element via XPath query
function Get-XPathValue($Xml, $XPath) {
    if (-not $Xml) { return $null }
    $ns = New-Object System.Xml.XmlNamespaceManager($Xml.NameTable)
    $ns.AddNamespace("opf", "http://www.idpf.org/2007/opf")
    $ns.AddNamespace("dc", "http://purl.org/dc/elements/1.1/")
    $Node = $Xml.SelectSingleNode($XPath, $ns)
    if ($Node) { return $Node.InnerText } else { return $null }
}

# Selects and returns the value of a specific attribute of an XML element via XPath query
function Get-XPathAttribute($Xml, $XPath, $AttributeName, $AttributeNS = "") {
    if (-not $Xml) { return $null }
    $ns = New-Object System.Xml.XmlNamespaceManager($Xml.NameTable)
    $ns.AddNamespace("opf", "http://www.idpf.org/2007/opf")
    $ns.AddNamespace("dc", "http://purl.org/dc/elements/1.1/")
    $Node = $Xml.SelectSingleNode($XPath, $ns)
    if (-not $Node) { return $null }
    
    if ($AttributeNS) {
        return $Node.GetAttribute($AttributeName, $AttributeNS)
    } else {
        return $Node.GetAttribute($AttributeName)
    }
}

# Asserts that the actual value equals the expected value and flags failures
function Assert-Equals($Actual, $Expected, $Message) {
    if ($Actual -ne $Expected) {
        Write-Host "  [FAIL] $Message (Expected: '$Expected', Actual: '$Actual')" -ForegroundColor Red
        $global:TestsFailed = $true
    } else {
        Write-Host "  [PASS] $Message" -ForegroundColor Green
    }
}

# ----------------- Generate Test Data -----------------
Write-Host "Creating test media directory structure and metadata files..." -ForegroundColor Cyan

# Book 1: Array author, subtitle, English language
$Book1Dir = Create-BookDir "book1" @'
{
  "title": "The Lord of the Rings",
  "subtitle": "The Fellowship of the Ring",
  "authors": ["J.R.R. Tolkien"],
  "language": "English",
  "publisher": "George Allen & Unwin",
  "publishedYear": "1954"
}
'@

# Book 2: String author, series name with index, genres, explicit, Spanish language
$Book2Dir = Create-BookDir "book2" @'
{
  "title": "The Way of Kings",
  "authors": "Brandon Sanderson",
  "series": "The Stormlight Archive #1.5",
  "genres": ["Fantasy", "Epic"],
  "tags": ["Cosmere"],
  "language": "es",
  "explicit": true,
  "isbn": "9780765326355"
}
'@

# Book 3: French language, multiple narrators
$Book3Dir = Create-BookDir "book3" @'
{
  "title": "Le Petit Prince",
  "authors": "Antoine de Saint-Exupéry",
  "language": "fr",
  "narrators": ["Narrator A", "Narrator B"]
}
'@

# Book 4: Unknown language, check length-2 fallback
$Book4Dir = Create-BookDir "book4" @'
{
  "title": "International Book",
  "authors": "Some Author",
  "language": "ja-JP"
}
'@

# ----------------- Run Sync Script -----------------
Write-Host "Running Sync-AbsToBookOrbit.ps1..." -ForegroundColor Cyan
pwsh -File (Join-Path $PSScriptRoot "Sync-AbsToBookOrbit.ps1") -MediaRoot $TempMediaDir

# ----------------- Assertions -----------------
Write-Host "Verifying generated OPF files..." -ForegroundColor Cyan

# --- Verification Book 1 ---
Write-Host "Verifying Book 1 (The Lord of the Rings)..." -ForegroundColor Yellow
$Xml1 = Get-OpfXml $Book1Dir
Assert-Equals (Get-XPathValue $Xml1 "//dc:title") "The Lord of the Rings: The Fellowship of the Ring" "Title should append subtitle"
Assert-Equals (Get-XPathValue $Xml1 "//dc:creator") "J.R.R. Tolkien" "Creator should match author"
Assert-Equals (Get-XPathAttribute $Xml1 "//dc:creator" "role" "http://www.idpf.org/2007/opf") "aut" "Creator should have role='aut'"
Assert-Equals (Get-XPathValue $Xml1 "//dc:language") "en" "Language 'English' should map to ISO 639-1 code 'en'"
Assert-Equals (Get-XPathValue $Xml1 "//dc:publisher") "George Allen & Unwin" "Publisher should be mapped"
Assert-Equals (Get-XPathValue $Xml1 "//dc:date") "1954" "Date should map to publishedYear"

# --- Verification Book 2 ---
Write-Host "Verifying Book 2 (The Way of Kings)..." -ForegroundColor Yellow
$Xml2 = Get-OpfXml $Book2Dir
Assert-Equals (Get-XPathValue $Xml2 "//dc:creator") "Brandon Sanderson" "Creator should match string author"
Assert-Equals (Get-XPathValue $Xml2 "//dc:language") "es" "Language 'es' should map to 'es'"
Assert-Equals (Get-XPathValue $Xml2 "//dc:identifier[@opf:scheme='ISBN']") "9780765326355" "ISBN identifier scheme should be mapped"
Assert-Equals (Get-XPathAttribute $Xml2 "//opf:meta[@name='calibre:series']" "content") "The Stormlight Archive" "Series name should be parsed from string"
Assert-Equals (Get-XPathAttribute $Xml2 "//opf:meta[@name='calibre:series_index']" "content") "1.5" "Series index should be parsed from string"

$ns2 = New-Object System.Xml.XmlNamespaceManager($Xml2.NameTable)
$ns2.AddNamespace("dc", "http://purl.org/dc/elements/1.1/")
$Subjects = @()
foreach ($Node in $Xml2.SelectNodes("//dc:subject", $ns2)) {
    $Subjects += $Node.InnerText
}
Assert-Equals ($Subjects -contains "Fantasy") $true "Genres (Fantasy) should map to subjects"
Assert-Equals ($Subjects -contains "Cosmere") $true "Tags (Cosmere) should map to subjects"
Assert-Equals ($Subjects -contains "Explicit") $true "Explicit switch should add 'Explicit' subject"

# --- Verification Book 3 ---
Write-Host "Verifying Book 3 (Le Petit Prince)..." -ForegroundColor Yellow
$Xml3 = Get-OpfXml $Book3Dir
Assert-Equals (Get-XPathValue $Xml3 "//dc:language") "fr" "Language 'fr' should map to 'fr'"

$ns3 = New-Object System.Xml.XmlNamespaceManager($Xml3.NameTable)
$ns3.AddNamespace("dc", "http://purl.org/dc/elements/1.1/")
$Contributors = @()
foreach ($Node in $Xml3.SelectNodes("//dc:contributor", $ns3)) {
    $Contributors += $Node.InnerText
}
Assert-Equals ($Contributors -contains "Narrator A") $true "Narrator A should be contributor"
Assert-Equals ($Contributors -contains "Narrator B") $true "Narrator B should be contributor"

# --- Verification Book 4 ---
Write-Host "Verifying Book 4 (International Book)..." -ForegroundColor Yellow
$Xml4 = Get-OpfXml $Book4Dir
Assert-Equals (Get-XPathValue $Xml4 "//dc:language") "ja" "Language 'ja-JP' fallback to substring length 2 'ja'"

# ----------------- Delta/Force Logic Verification -----------------
Write-Host "Verifying Delta Engine and FORCE logic..." -ForegroundColor Cyan

# Check last write time of book 1 OPF
$Book1OpfPath = Join-Path $Book1Dir "metadata.opf"
$FirstWriteTime = (Get-Item $Book1OpfPath).LastWriteTime

# Run sync again without changes - should skip update (LastWriteTime remains the same)
Start-Sleep -Seconds 1 # Ensure difference in clock time if updated
pwsh -File (Join-Path $PSScriptRoot "Sync-AbsToBookOrbit.ps1") -MediaRoot $TempMediaDir
$SecondWriteTime = (Get-Item $Book1OpfPath).LastWriteTime
Assert-Equals $SecondWriteTime $FirstWriteTime "Delta Engine: OPF should NOT update if metadata.json has not changed"

# Run sync again with -Force parameter - should force update
pwsh -File (Join-Path $PSScriptRoot "Sync-AbsToBookOrbit.ps1") -MediaRoot $TempMediaDir -Force
$ThirdWriteTime = (Get-Item $Book1OpfPath).LastWriteTime
Assert-Equals ($ThirdWriteTime -gt $FirstWriteTime) $true "Force parameter: OPF should update when -Force is set"

# Run sync again with FORCE env variable - should force update
$env:FORCE = "true"
Start-Sleep -Seconds 1
pwsh -File (Join-Path $PSScriptRoot "Sync-AbsToBookOrbit.ps1") -MediaRoot $TempMediaDir
$FourthWriteTime = (Get-Item $Book1OpfPath).LastWriteTime
Assert-Equals ($FourthWriteTime -gt $ThirdWriteTime) $true "FORCE environment variable: OPF should update when env:FORCE is set"
$env:FORCE = $null # Clean up env var

# ----------------- Cleanup -----------------
Write-Host "Cleaning up test environment..." -ForegroundColor Cyan
if (Test-Path $TempMediaDir) {
    Remove-Item -Recurse -Force $TempMediaDir
}

# Final Exit Code
if ($global:TestsFailed) {
    Write-Host "`n[RESULT] Some integration tests FAILED." -ForegroundColor Red
    exit 1
} else {
    Write-Host "`n[RESULT] All integration tests PASSED successfully!" -ForegroundColor Green
    exit 0
}
