terraform {
  required_providers {
    # The "pulumi/" prefix selects the native Pulumi Service provider.
    # Native providers need an exact version, not a constraint.
    pulumiservice = {
      source  = "pulumi/pulumiservice"
      version = "1.9.0"
    }
  }
}
