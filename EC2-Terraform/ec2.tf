# Setting up key 
resource "aws_key_pair" "mykey" {
  key_name   = "terra-key-ec2-new"  # Change this to a unique name
  public_key = file("terra_key_ec2.pub")
}

# Creating VPC 
resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
    description = "creating vpc"
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_default_vpc.default.id

  ingress {
     from_port = 22
     to_port = 22
     protocol = "tcp"
     cidr_blocks = ["0.0.0.0/0"]
     description = "ssh open"
  }

   ingress {
     from_port = 80
     to_port = 80
     protocol = "tcp"
     cidr_blocks = ["0.0.0.0/0"]
     description = "http port open"
  }

  ingress {
     from_port = 8000
     to_port = 8000
     protocol = "tcp"
     cidr_blocks = ["0.0.0.0/0"]
     description = "application opens"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "all over access open outbound"
  }
}

# Creating EC2 instance
resource "aws_instance" "my_ec2" {
  key_name               = aws_key_pair.mykey.key_name
  vpc_security_group_ids = [aws_default_security_group.default.id]
  ami                    = var.ec2_ami
  instance_type          = var.ec2_instance_type
  user_data = file("docker_install.sh")

  root_block_device {
    volume_size = var.ec2_root_block_size
    volume_type = "gp3"
  }

  tags = {
    Name = var.ec2_name
  }
}
