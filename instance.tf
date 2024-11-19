resource "aws_key_pair" "temp_deployer" {
  key_name   = "temp-deployer-key"
  public_key = file("./terraform-cli-key2.pub")
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_traffic"
  description = "Allow SSH inbound traffic, necessary services inbound traffic and all outbound traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ALLOWED_IPS
  }

  ingress {
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    cidr_blocks = var.ALLOWED_IPS
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = var.ALLOWED_IPS
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.ALLOWED_IPS
  }

  ingress {
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    cidr_blocks = var.ALLOWED_IPS
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_spot_instance_request" "microservice_test" {
  ami             = "ami-0e8d228ad90af673b"
  instance_type   = "t2.2xlarge"
  key_name        = aws_key_pair.temp_deployer.key_name
  security_groups = [aws_security_group.allow_ssh.name]
  spot_price      = "0.2"
  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }
  wait_for_fulfillment = true

  user_data = <<-EOF
  #!/bin/bash
  apt-get update -y
  apt-get install -y apt-transport-https ca-certificates curl software-properties-common

  # Install Docker
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
  apt-get update -y
  apt-get install -y docker-ce

  # Start Docker service and enable it to start on boot
  systemctl start docker
  systemctl enable docker

  usermod -aG docker ubuntu

  systemctl restart docker

  # Install Docker Compose
  curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose

  export HOME=/home/ubuntu
  # Install Git
  apt-get install -y git

  mkdir envs

EOF

  tags = {
    Name = "MicroserviceTest"
  }
}

resource "null_resource" "provisioner" {

  depends_on = [ aws_spot_instance_request.microservice_test ]

  provisioner "local-exec" {
    command = "echo ${aws_spot_instance_request.microservice_test.public_ip}"
  }

  provisioner "file" {
    source      = "./id_rsa_base64.txt"
    destination = "/home/ubuntu/id_rsa_base64.txt"
  }

  provisioner "file" {
    source      = "./envs"
    destination = "/home/ubuntu/envs"
  }

  provisioner "remote-exec" {

    inline = [
      "echo which docker",
      "sleep 60",
      "base64 -d /home/ubuntu/id_rsa_base64.txt > /home/ubuntu/.ssh/id_rsa",
      "chmod 600 /home/ubuntu/.ssh/id_rsa",
      "ssh -o StrictHostKeyChecking=no -T git@github.com",
      "mkdir /home/ubuntu/servicesconnect && cd servicesconnect",
      "git clone git@github.com:servicesconnect/notifications.git",
      "mv /home/ubuntu/envs/notifications/.env ./notifications/.env",
      "git clone git@github.com:servicesconnect/gateway.git",
      "mv /home/ubuntu/envs/gateway/.env ./gateway/.env",
      "git clone git@github.com:servicesconnect/auth.git",
      "mv /home/ubuntu/envs/auth/.env ./auth/.env",
      "git clone git@github.com:servicesconnect/users.git",
      "mv /home/ubuntu/envs/users/.env ./users/.env",
      "git clone git@github.com:servicesconnect/project.git",
      "mv /home/ubuntu/envs/project/.env ./project/.env",
      "git clone git@github.com:servicesconnect/cicd.git",
      "mv /home/ubuntu/envs/cicd/.env ./cicd/.env",
      "cd cicd",
      "sudo docker compose up -d",
    ]
  }

  connection {
    user        = var.USER
    private_key = file("terraform-cli-key2")
    host        = aws_spot_instance_request.microservice_test.public_ip
  }
}

output "instance_ip" {
  value = aws_spot_instance_request.microservice_test.public_ip
}
