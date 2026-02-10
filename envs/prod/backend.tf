terraform {
  backend "s3" {
    bucket         = "shelfshack-terraform-state-v2"
    key            = "shelfshack/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "shelfshack-terraform-locks"
    encrypt        = true
  }
}
