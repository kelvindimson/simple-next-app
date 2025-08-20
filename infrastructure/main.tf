terraform {
  cloud{
    organization = "OneForge"  # Replace with your Terraform Cloud organization name
    workspaces {
      name = "CCF501-Assessment"
    }
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Create Resource Group (in AWS, we use tags for grouping)
locals {
  common_tags = {
    Project     = "CCF501-Assessment"
    Environment = "Development"
    Student     = "YourName"
  }
}

# Create VPC (Virtual Network)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "CCF501-VPC"
  })
}

# Create Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "CCF501-IGW"
  })
}

# Create Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "CCF501-Public-Subnet"
  })
}

# Create Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "CCF501-Public-RT"
  })
}

# Associate Route Table with Subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Create Security Group (Firewall)
resource "aws_security_group" "web" {
  name        = "CCF501-Web-SG"
  description = "Security group for Next.js application"
  vpc_id      = aws_vpc.main.id

  # Allow SSH
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS
  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Next.js dev port
  ingress {
    description = "Next.js App"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "CCF501-Security-Group"
  })
}

# Create EC2 Instance
resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"  # Free tier eligible
  subnet_id     = aws_subnet.public.id
  key_name      = var.key_pair_name

  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = <<-EOF
    #!/bin/bash
    # Update system
    apt-get update
    apt-get upgrade -y
    
    # Install Node.js 18.x and npm
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    apt-get install -y nodejs
    
    # Install git and nginx
    apt-get install -y git nginx
    
    # Install PM2 globally
    npm install -g pm2
    
    # Create app directory
    mkdir -p /var/www/nextjs-app
    cd /var/www/nextjs-app
    
    # Clone your repository (you'll need to update this with your repo URL)
    # git clone ${var.github_repo_url} .
    
    # For now, create a simple Next.js app
    npx create-next-app@latest . --typescript --no-tailwind --no-eslint --app --no-src-dir --import-alias "@/*"
    
    # Install dependencies
    npm install
    
    # Build the Next.js app
    npm run build
    
    # Start the app with PM2
    pm2 start npm --name "nextjs-app" -- start
    pm2 startup systemd
    pm2 save
    
    # Configure Nginx as reverse proxy
    cat > /etc/nginx/sites-available/default <<'EOL'
    server {
        listen 80;
        server_name _;
        
        location / {
            proxy_pass http://localhost:3000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_cache_bypass \$http_upgrade;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
    EOL
    
    # Restart Nginx
    systemctl restart nginx
    systemctl enable nginx
  EOF

  tags = merge(local.common_tags, {
    Name = "CCF501-NextJS-Server"
  })
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}