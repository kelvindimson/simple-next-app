variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "key_pair_name" {
  description = "Name of the AWS key pair to use for EC2 instance"
  type        = string
  default     = "ccf501-assessment-key"
}

variable "github_repo_url" {
  description = "GitHub repository URL for your Next.js app"
  type        = string
  default     = ""
}