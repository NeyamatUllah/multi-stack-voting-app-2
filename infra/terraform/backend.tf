terraform {
  backend "s3" {
    bucket         = "voting-app-tfstate-73d11b0b"
    key            = "voting-app/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "voting-app-tf-locks"
    encrypt        = true
  }
}