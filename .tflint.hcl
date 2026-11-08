config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Enable once Phase 3 modules exist and `tflint --init` can fetch the plugin:
# plugin "aws" {
#   enabled = true
#   version = "0.38.0"
#   source  = "github.com/terraform-linters/tflint-ruleset-aws"
# }
