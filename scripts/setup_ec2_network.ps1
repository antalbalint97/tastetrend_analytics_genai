# setup_ec2_network.ps1
# Creates minimal networking and keypair setup for EC2 (VPC, subnet, IGW, SG)

Write-Host "Setting up AWS network for TasteTrend EC2..."

# Create or get default VPC
$vpc = (aws ec2 describe-vpcs --region eu-central-1 --query "Vpcs[?IsDefault].VpcId" --output text)
if (-not $vpc -or $vpc -eq "None") {
    Write-Host "Creating new VPC..."
    $vpc = (aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region eu-central-1 --query "Vpc.VpcId" --output text)
    aws ec2 modify-vpc-attribute --vpc-id $vpc --enable-dns-support "{\"Value\":true}" --region eu-central-1
    aws ec2 modify-vpc-attribute --vpc-id $vpc --enable-dns-hostnames "{\"Value\":true}" --region eu-central-1
} else {
    Write-Host "Using default VPC: $vpc"
}

# Create subnet
$subnet = (aws ec2 create-subnet --vpc-id $vpc --cidr-block 10.0.1.0/24 --availability-zone eu-central-1a --region eu-central-1 --query "Subnet.SubnetId" --output text)
Write-Host "Created subnet: $subnet"

# Create and attach Internet Gateway
$igw = (aws ec2 create-internet-gateway --region eu-central-1 --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $igw --vpc-id $vpc --region eu-central-1
Write-Host "Created and attached IGW: $igw"

# Create route table
$rt = (aws ec2 create-route-table --vpc-id $vpc --region eu-central-1 --query "RouteTable.RouteTableId" --output text)
aws ec2 create-route --route-table-id $rt --destination-cidr-block 0.0.0.0/0 --gateway-id $igw --region eu-central-1 | Out-Null
aws ec2 associate-route-table --route-table-id $rt --subnet-id $subnet --region eu-central-1 | Out-Null
Write-Host "Route table: $rt"

# Security group (SSH, HTTPS)
$sg = (aws ec2 create-security-group --group-name tastetrend-ec2-sg --description "Security group for TasteTrend EC2" --vpc-id $vpc --region eu-central-1 --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id $sg --protocol tcp --port 22 --cidr 0.0.0.0/0 --region eu-central-1 | Out-Null
aws ec2 authorize-security-group-egress --group-id $sg --protocol -1 --port all --cidr 0.0.0.0/0 --region eu-central-1 | Out-Null
Write-Host "Security group: $sg"

# Key pair
$keyname = "tastetrend-ec2-key"
$keypath = "$HOME\Desktop\$keyname.pem"
if (-not (Test-Path $keypath)) {
    aws ec2 create-key-pair --key-name $keyname --region eu-central-1 --query "KeyMaterial" --output text | Out-File -Encoding ascii $keypath
    Write-Host "Created key pair and saved to: $keypath"
} else {
    Write-Host "Key already exists: $keypath"
}

# Summary
Write-Host "`nVPC: $vpc"
Write-Host "Subnet: $subnet"
Write-Host "Security Group: $sg"
Write-Host "KeyPair: $keyname"
Write-Host "`n✅ Network setup complete."
