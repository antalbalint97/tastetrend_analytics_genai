param (
    [string]$Version = "4.1",
    [string]$Region = "eu-central-1",
    [string]$ArtifactsBucket = "tastetrend-poc-artifacts-550744777598",
    [string]$RawBucket = "tastetrend-poc-raw-550744777598"
)

# Paths
$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$tmp = Join-Path $root "tmp"
$src = Join-Path $root "src"
$dist = Join-Path $root "deployment"
$rawData = Join-Path $root "data\raw"

# Clean and prepare
Write-Host "Cleaning build folders..."
Remove-Item -Recurse -Force $tmp,$dist -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $tmp,$dist | Out-Null

# Copy source to tmp
Write-Host "Copying source files..."
Copy-Item -Path "$src\*" -Destination $tmp -Recurse -Force

# Build ZIPs
Write-Host "Creating Lambda ZIPs..."
$etlZip = Join-Path $dist "tastetrend-etl-$Version.zip"
$embedZip = Join-Path $dist "tastetrend-embedding-$Version.zip"
$proxyZip = Join-Path $dist "tastetrend-proxy-$Version.zip"

Compress-Archive -Path "$tmp\*" -DestinationPath $etlZip -Force
Compress-Archive -Path "$tmp\*" -DestinationPath $embedZip -Force
Compress-Archive -Path "$tmp\*" -DestinationPath $proxyZip -Force

Write-Host "ZIPs created:"
Get-ChildItem $dist | Format-Table Name,Length,LastWriteTime

# Upload ZIPs to S3
Write-Host "Uploading Lambda ZIPs to S3 bucket $ArtifactsBucket..."
aws s3 cp $etlZip "s3://$ArtifactsBucket/lambda/api-$Version.zip" --region $Region
aws s3 cp $embedZip "s3://$ArtifactsBucket/lambda/embed-$Version.zip" --region $Region
aws s3 cp $proxyZip "s3://$ArtifactsBucket/lambda/proxy-$Version.zip" --region $Region
Write-Host "Lambda ZIPs upload complete."

# Ask if this is the first run
$firstRun = Read-Host "Is this the first run? (y/n)"
if ($firstRun -eq "y" -or $firstRun -eq "Y") {
    if (Test-Path $rawData) {
        Write-Host "Uploading raw data from $rawData to s3://$RawBucket/ ..."
        aws s3 cp $rawData "s3://$RawBucket/" --recursive --region $Region
        Write-Host "Raw data upload complete."
    } else {
        Write-Host "No raw data folder found at $rawData. Skipping raw data upload."
    }
} else {
    Write-Host "Skipping raw data upload (not first run)."
}

Write-Host "Deployment complete."
