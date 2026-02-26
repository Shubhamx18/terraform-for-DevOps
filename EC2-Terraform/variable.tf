variable "ec2_ami" {
     default = "ami-019715e0d74f695be"
     type = string
}

variable "ec2_instance_type" {
     default = "t3.micro" 
     type = string
}

variable "ec2_root_block_size" {
     default = 10
     type = number
}

variable "ec2_name" {
     default = "variable"
     type = string
}
