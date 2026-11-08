module "naming" {
  source = "../.."

  business_unit  = "pga"
  project        = "billing"
  environment    = "dev"
  region_short   = "weu"
  subnets        = ["app", "db"]
  access_groups  = ["readers"]
  engine_version = "1.0.0"
  source_path    = "projects/pga/billing/dev.yaml"

  tags = {
    cost_center     = "ES0009"
    business_owner  = "owner@example.com"
    technical_owner = "team@example.com"
  }
}
