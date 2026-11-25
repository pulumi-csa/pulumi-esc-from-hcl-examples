terraform {
  # Pulumi Cloud implements the Terraform remote backend API, so state is
  # stored there with a standard "remote" backend block.
  # The organization is not set here. Supply it at init time:
  #   terraform init -backend-config="organization=<org>"
  backend "remote" {
    hostname = "tf.pulumi.com"

    # <project>_<stack>: stored as stack "dev" in project "hcl-esc-env-vars".
    workspaces {
      name = "hcl-esc-env-vars_dev"
    }
  }
}
