terraform {
  required_providers {
    postgresql = {
      source  = "cyrilgdn/postgresql"
      # version = "~> 1.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "source_ip" {}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "rds"
  cidr = "10.0.0.0/16"

  azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets       = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  enable_dns_hostnames = true
}

resource "aws_db_parameter_group" "postgres-parameters" {
  name        = "postgres"
  family      = "postgres13"
  description = "postgres"
}

resource "aws_db_subnet_group" "postgres-subnet" {
  name        = "postgres"
  description = "postgres subnet group"
  subnet_ids  = module.vpc.public_subnets
}

resource "aws_security_group" "allow-postgres" {
  vpc_id      = module.vpc.vpc_id
  name        = "postgres"
  description = "postgres"
  ingress {
    from_port   = 5432
    protocol    = "tcp"
    to_port     = 5432
    cidr_blocks = [var.source_ip, "10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    self        = true #(Optional) Whether the security group itself will be added as a source to this egress rule.
  }
  tags = {
    Name = "postgres"
  }
}

resource "aws_db_instance" "postgres" {
  allocated_storage       = 20
  engine                  = "postgres"
  engine_version          = "13.3"
  instance_class          = "db.t3.micro"
  identifier              = "postgres"
  name                    = "postgres"
  username                = "root"
  password                = "tempunsecurepassword"
  db_subnet_group_name    = aws_db_subnet_group.postgres-subnet.name
  parameter_group_name    = aws_db_parameter_group.postgres-parameters.name
  multi_az                = false
  vpc_security_group_ids  = [aws_security_group.allow-postgres.id]
  storage_type            = "gp2"
  backup_retention_period = 7
  skip_final_snapshot     = true
  publicly_accessible     = false
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
    subnet_ids         = module.vpc.public_subnets
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      ENDPOINT   = aws_db_instance.postgres.address
      PORT       = "5432"
      DBUSER     = "root"
      DBPASSWORD = "tempunsecurepassword"
      DATABASE   = "postgres"
    }
  }
}