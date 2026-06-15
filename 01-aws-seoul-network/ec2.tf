# 01-aws-seoul-network/ec2.tf

resource "aws_security_group" "bastion_sg" {
  name        = "bidhouse-bastion-sg"
  description = "Allow SSH inbound"
  vpc_id      = aws_vpc.prod_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "bidhouse-bastion-sg" }
}

resource "aws_instance" "bastion" {
  ami                         = "ami-042e76978adeb8c48"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.prod_public.id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true
  key_name                    = "BIDHOUSE0610"

  iam_instance_profile        = aws_iam_instance_profile.bastion_ssm_profile.name

  tags = { Name = "bidhouse-bastion" }

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install -y mysql
  EOF
}

resource "aws_iam_role" "bastion_ssm_role" {
  name = "bidhouse-bastion-ssm-role"
  lifecycle {
    ignore_changes = all
  }
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion_ssm_profile" {
  name = "bidhouse-bastion-ssm-profile"
  role = aws_iam_role.bastion_ssm_role.name
}

output "bastion_public_ip" {
  value       = aws_instance.bastion.public_ip
  description = "Bastion EC2 Public IP"
}