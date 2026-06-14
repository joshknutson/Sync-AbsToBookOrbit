# Sync-AbsToBookOrbit.ps1
# Senior Admin Sync Script: Parallelized OPF generator

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string[]]$MediaRoot = @(),
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# Parse scan paths from parameters or fallback to env variable, then to /media
$PathsToScan = @()
if ($MediaRoot -and $MediaRoot.Count -gt 0) {
    foreach ($Entry in $MediaRoot) {
        if ($Entry) {
            $PathsToScan += ($Entry -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
        }
    }
} elseif ($env:MEDIA_ROOT) {
    $PathsToScan = ($env:MEDIA_ROOT -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
}

if ($PathsToScan.Count -eq 0) {
    $PathsToScan = @("/media")
}

Write-Host "========== SYNC INITIALIZED ==========" -ForegroundColor Cyan

$AbsJsonFiles = @()
foreach ($Path in $PathsToScan) {
    Write-Host "Scanning directory: $Path" -ForegroundColor Gray
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "The path '$Path' does not exist or is not accessible."
        continue
    }

    $FoundFiles = Get-ChildItem -LiteralPath $Path -Filter "metadata.json" -Recurse -File -ErrorAction SilentlyContinue
    if ($FoundFiles) {
        $AbsJsonFiles += $FoundFiles
    }
}

if ($AbsJsonFiles.Count -eq 0) {
    Write-Host "No metadata.json files found to process." -ForegroundColor Yellow
    Write-Host "========== COMPLETE ==========" -ForegroundColor Cyan
    return
}

# Process in parallel with a maximum throttle of 3 threads
$AbsJsonFiles | ForEach-Object -Parallel {
    $JsonFile = $_
    $ItemDir = $JsonFile.DirectoryName
    $OpfPath = Join-Path $ItemDir "metadata.opf"

    # Delta/Force logic - check if target exists or is older than the source metadata file
    $NeedsUpdate = $using:Force -or `
                   (-not (Test-Path -LiteralPath $OpfPath)) -or `
                   ((Get-Item -LiteralPath $OpfPath).LastWriteTime -lt $JsonFile.LastWriteTime)

    if ($NeedsUpdate) {
        try {
            $Data = Get-Content -Raw -LiteralPath $JsonFile.FullName | ConvertFrom-Json

            # Subtitle & Title Logic - append subtitle if available for Calibre compatibility
            $Title = $Data.title
            if ($Data.subtitle) {
                $Title = "${Title}: $($Data.subtitle)"
            }

            # Language Mapping Logic - convert English name to 2-letter ISO 639-1 code
            $LanguageCode = "en"
            if ($Data.language) {
                switch -Regex ($Data.language.ToLower().Trim()) {
                    '^en(glish)?$' { $LanguageCode = 'en' }
                    '^es(panol|panish)?$' { $LanguageCode = 'es' }
                    '^de(utsch|german)?$' { $LanguageCode = 'de' }
                    '^fr(ance|ench)?$' { $LanguageCode = 'fr' }
                    '^it(alian)?$' { $LanguageCode = 'it' }
                    '^pt(ortuguese)?$' { $LanguageCode = 'pt' }
                    '^ru(ssian)?$' { $LanguageCode = 'ru' }
                    '^ja(panese)?$' { $LanguageCode = 'ja' }
                    '^zh(inese)?$' { $LanguageCode = 'zh' }
                    default {
                        if ($Data.language.Length -ge 2) {
                            $LanguageCode = $Data.language.Substring(0, 2).ToLower()
                        }
                    }
                }
            }

            # Normalize authors (can be a string or an array)
            $AuthorsList = $null
            if ($Data.authors) {
                if ($Data.authors -is [array]) {
                    $AuthorsList = $Data.authors
                } else {
                    $AuthorsList = @($Data.authors)
                }
            }

            # Normalize narrators (can be a string or an array)
            $NarratorsList = $null
            if ($Data.narrators) {
                if ($Data.narrators -is [array]) {
                    $NarratorsList = $Data.narrators
                } else {
                    $NarratorsList = @($Data.narrators)
                }
            }

            # Normalize series (can be a string or an array)
            $SeriesVal = $null
            if ($Data.series) {
                if ($Data.series -is [array]) {
                    if ($Data.series.Count -gt 0) { $SeriesVal = $Data.series[0] }
                } else {
                    $SeriesVal = $Data.series
                }
            }

            # Date fallback
            $DateVal = $Data.publishedYear
            if (-not $DateVal -and $Data.publishedDate -and $Data.publishedDate -match '^(\d{4})') {
                $DateVal = $Matches[1]
            }

            # Object Mapping
            $MetadataObj = [PSCustomObject]@{
                Title       = $Title
                Authors     = $AuthorsList
                Publisher   = $Data.publisher
                Date        = $DateVal
                Language    = $LanguageCode
                Description = $Data.description
                Subjects    = ($Data.tags + $Data.genres) | Select-Object -Unique
                Series      = $SeriesVal
                SeriesIdx   = "1.0"
                Explicit    = ($Data.explicit -eq $true)
                Isbn        = $Data.isbn
                Asin        = $Data.asin
                Narrators   = $NarratorsList
            }

            # Series Logic - extract name and number index if the string format matches
            if ($MetadataObj.Series -match '(.+?)\s*(?:#|v)?(\d+(?:\.\d+)?)$') {
                $MetadataObj.Series = $Matches[1].Trim()
                $MetadataObj.SeriesIdx = $Matches[2].Trim()
            }

            # XML Construction with proper namespace definitions
            [xml]$XmlDoc = New-Object System.Xml.XmlDocument
            $OpfNS = "http://www.idpf.org/2007/opf"
            $DcNS  = "http://purl.org/dc/elements/1.1/"

            $Package = $XmlDoc.AppendChild($XmlDoc.CreateElement("package", $OpfNS))
            $Package.SetAttribute("version", "2.0")

            $Metadata = $Package.AppendChild($XmlDoc.CreateElement("metadata", $OpfNS))
            $Metadata.SetAttribute("xmlns:dc", $DcNS)
            $Metadata.SetAttribute("xmlns:opf", $OpfNS)

            # Inline node helper - innerText assignment handles XML escaping automatically
            # Assign namespace URI depending on the tag prefix so that XmlWriter does not throw redefinition errors
            function Add-Node($Parent, $Name, $Value) {
                $NS = if ($Name -like "dc:*") { "http://purl.org/dc/elements/1.1/" } else { "http://www.idpf.org/2007/opf" }
                $Node = $Parent.AppendChild($XmlDoc.CreateElement($Name, $NS))
                if ($null -ne $Value) { $Node.InnerText = $Value }
                return $Node
            }

            # Add DC Title
            Add-Node $Metadata "dc:title" $MetadataObj.Title | Out-Null

            # Add DC Creators (Authors) - support multiple authors as separate nodes
            if ($MetadataObj.Authors) {
                foreach ($Author in $MetadataObj.Authors) {
                    if ($Author) {
                        $Creator = Add-Node $Metadata "dc:creator" $Author
                        $Creator.SetAttribute("role", $OpfNS, "aut") | Out-Null
                    }
                }
            } else {
                $Creator = Add-Node $Metadata "dc:creator" "Unknown"
                $Creator.SetAttribute("role", $OpfNS, "aut") | Out-Null
            }

            # Add DC Contributors (Narrators)
            if ($MetadataObj.Narrators) {
                foreach ($Narrator in $MetadataObj.Narrators) {
                    if ($Narrator) {
                        $Contributor = Add-Node $Metadata "dc:contributor" $Narrator
                        $Contributor.SetAttribute("role", $OpfNS, "nrt") | Out-Null
                    }
                }
            }

            # Add Identifiers (ISBN/ASIN)
            if ($MetadataObj.Isbn) {
                $IdNode = Add-Node $Metadata "dc:identifier" $MetadataObj.Isbn
                $IdNode.SetAttribute("scheme", $OpfNS, "ISBN") | Out-Null
            }
            if ($MetadataObj.Asin) {
                $IdNode = Add-Node $Metadata "dc:identifier" $MetadataObj.Asin
                $IdNode.SetAttribute("scheme", $OpfNS, "ASIN") | Out-Null
            }

            Add-Node $Metadata "dc:publisher" $MetadataObj.Publisher | Out-Null
            Add-Node $Metadata "dc:date" $MetadataObj.Date | Out-Null
            Add-Node $Metadata "dc:language" $MetadataObj.Language | Out-Null
            Add-Node $Metadata "dc:description" $MetadataObj.Description | Out-Null

            foreach ($Sub in $MetadataObj.Subjects) {
                if ($Sub) { Add-Node $Metadata "dc:subject" $Sub | Out-Null }
            }
            if ($MetadataObj.Explicit) { Add-Node $Metadata "dc:subject" "Explicit" | Out-Null }

            # Add Calibre Series tags
            if ($MetadataObj.Series) {
                $Meta = Add-Node $Metadata "meta" $null
                $Meta.SetAttribute("name", "calibre:series")
                $Meta.SetAttribute("content", $MetadataObj.Series)
                $MetaIdx = Add-Node $Metadata "meta" $null
                $MetaIdx.SetAttribute("name", "calibre:series_index")
                $MetaIdx.SetAttribute("content", $MetadataObj.SeriesIdx)
            }

            # Configure XML Writer for formatted and indented output (pretty-print)
            $Settings = New-Object System.Xml.XmlWriterSettings
            $Settings.Indent = $true
            $Settings.IndentChars = "  "
            $Settings.NewLineChars = [System.Environment]::NewLine
            $Settings.OmitXmlDeclaration = $true
            $Settings.Encoding = [System.Text.Encoding]::UTF8

            $Writer = [System.Xml.XmlWriter]::Create($OpfPath, $Settings)
            try {
                $XmlDoc.Save($Writer)
            }
            finally {
                $Writer.Dispose()
            }

            Write-Host "[*] Sync Complete: $($MetadataObj.Title)" -ForegroundColor Cyan
        }
        catch {
            Write-Host "[-] ERROR on $($JsonFile.FullName): $_" -ForegroundColor Red
        }
    }
} -ThrottleLimit 3

Write-Host "========== COMPLETE ==========" -ForegroundColor Cyan