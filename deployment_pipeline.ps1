param (
    [string]$Version = "5.0",
    [string]$Region = "eu-central-1",
    [string]$ArtifactsBucket = "tastetrend-poc-artifacts-550744777598",
    [string]$RawBucket = "tastetrend-poc-raw-550744777598"
)

# --- Paths ---
$root         = Split-Path -Parent $MyInvocation.MyCommand.Definition
$tmp          = Join-Path $root "tmp"
$src          = Join-Path $root "src"
$dist         = Join-Path $root "deployment"
$rawData      = Join-Path $root "data\raw"
$versionFile  = Join-Path $root "version.txt"
$historyFile  = Join-Path $root "version_history.txt"

# --- Clean and prepare ---
Write-Host "`nCleaning build folders..."
Remove-Item -Recurse -Force $tmp, $dist -ErrorAction SilentlyContinue | Out-Null
New-Item -ItemType Directory -Force -Path $tmp, $dist | Out-Null

# --- Copy source ---
Write-Host "Copying source files..."
Copy-Item -Path "$src\*" -Destination $tmp -Recurse -Force

# --- Build ZIPs ---
Write-Host "`nCreating Lambda ZIPs..."
$etlZip    = Join-Path $dist "tastetrend-etl-$Version.zip"
$embedZip  = Join-Path $dist "tastetrend-embedding-$Version.zip"
$proxyZip  = Join-Path $dist "tastetrend-proxy-$Version.zip"
$searchZip = Join-Path $dist "tastetrend-search-reviews-$Version.zip"

Compress-Archive -Path "$tmp\*" -DestinationPath $etlZip -Force
Compress-Archive -Path "$tmp\*" -DestinationPath $embedZip -Force
Compress-Archive -Path "$tmp\*" -DestinationPath $proxyZip -Force
Compress-Archive -Path "$tmp\*" -DestinationPath $searchZip -Force

Write-Host "`nZIPs created:"
Get-ChildItem $dist | Format-Table Name,Length,LastWriteTime

# --- Upload to S3 ---
Write-Host "`nUploading Lambda ZIPs to S3 bucket $ArtifactsBucket..."
aws s3 cp $etlZip    "s3://$ArtifactsBucket/lambda/api-$Version.zip"            --region $Region
aws s3 cp $embedZip  "s3://$ArtifactsBucket/lambda/embed-$Version.zip"          --region $Region
aws s3 cp $proxyZip  "s3://$ArtifactsBucket/lambda/proxy-$Version.zip"          --region $Region
aws s3 cp $searchZip "s3://$ArtifactsBucket/lambda/search-reviews-$Version.zip" --region $Region
Write-Host "Lambda ZIPs upload complete.`n"

# --- Optional raw data upload ---
$firstRun = Read-Host "Is this the first run? (y/n)"
if ($firstRun -match "^[Yy]$") {
    if (Test-Path $rawData) {
        Write-Host "Uploading raw data from $rawData to s3://$RawBucket/ ..."
        aws s3 cp $rawData "s3://$RawBucket/" --recursive --region $Region
        Write-Host "Raw data upload complete."
    }
    else {
        Write-Host "No raw data folder found at $rawData. Skipping raw data upload."
    }
}
else {
    Write-Host "Skipping raw data upload (not first run)."
}

Write-Host "`nDeployment complete."
