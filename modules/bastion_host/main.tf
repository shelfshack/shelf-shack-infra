locals {
  tags = merge(var.tags, { Module = "bastion" })
}

data "aws_ssm_parameter" "amazon_linux" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "this" {
  count       = var.enabled ? 1 : 0
  name        = "${var.name}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allow_ssh_cidr_blocks
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "Optional SSH access"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.name}-bastion-sg" })
}

resource "aws_iam_role" "this" {
  count              = var.enabled ? 1 : 0
  name               = "${var.name}-bastion-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(local.tags, { Name = "${var.name}-bastion-role" })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count      = var.enabled ? 1 : 0
  role       = aws_iam_role.this[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  count = var.enabled ? 1 : 0
  name  = "${var.name}-bastion-profile"
  role  = aws_iam_role.this[0].name
}

resource "aws_instance" "this" {
  count                       = var.enabled ? 1 : 0
  ami                         = data.aws_ssm_parameter.amazon_linux.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.this[0].name
  vpc_security_group_ids      = [aws_security_group.this[0].id]

  tags = merge(local.tags, { Name = "${var.name}-bastion" })
}
