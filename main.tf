provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "rds"
  cidr = "10.0.0.0/16"

  azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets       = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  private_subnets      = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
  enable_dns_hostnames = true
  enable_nat_gateway   = true
}

resource "aws_iam_role" "sample" {
  name = "sample"

  inline_policy {
    name = "lambda_vpc"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = [
            "ec2:CreateNetworkInterface",
            "ec2:DescribeNetworkInterfaces",
            "ec2:DeleteNetworkInterface"
          ]
          Effect   = "Allow"
          Resource = "*"
        },
        {
          "Effect": "Allow",
          "Action": "ssm:GetParameter",
          "Resource": "arn:aws:ssm:*:890363476833:parameter/*"
        }
      ]
    })
  }

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [
          "lambda.amazonaws.com",
          "edgelambda.amazonaws.com"
        ]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir = "lambda"
  output_path = "lambda_function.zip"
}

resource "aws_security_group" "lambda" {
  vpc_id      = module.vpc.vpc_id
  name        = "lambda"
  description = "lambda"
  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    self        = true #(Optional) Whether the security group itself will be added as a source to this egress rule.
  }
  tags = {
    Name = "lambda"
  }
}

resource "aws_lambda_function" "sample" {
  filename         = "lambda_function.zip"
  function_name    = "sample"
  role             = aws_iam_role.sample.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.8"
  publish          = true

  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.lambda.id]
  }
}

resource "aws_ssm_parameter" "foo" {
  name  = "foo"
  type  = "String"
  value = "bar"
}