terraform {
  backend "s3" {
    bucket         = "rentify-terraform-state"
    key            = "rentify/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "rentify-terraform-locks"
    encrypt        = true
  }
}
