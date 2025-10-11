param (
    [string]$Version = "1.9",
    [string]$Region = "eu-central-1",
    [string]$BucketName = "tastetrend-poc-artifacts-550744777598"
)

    
# Paths
$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$tmp = Join-Path $root "tmp"
$src = Join-Path $root "src"
$dist = Join-Path $root "deployment"

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
Write-Host "Uploading to S3 bucket $BucketName..."

aws s3 cp $etlZip "s3://$BucketName/lambda/api-$Version.zip" --region $Region
aws s3 cp $embedZip "s3://$BucketName/lambda/embed-$Version.zip" --region $Region
aws s3 cp $proxyZip "s3://$BucketName/lambda/proxy-$Version.zip" --region $Region

Write-Host "Upload complete."

