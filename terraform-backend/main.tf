locals {
  environment_ref = "${var.organization}/${var.project}/${var.environment}"

  # The environment definition is ordinary ESC YAML.
  # Everything under "values" is a variable in the environment:
  #   - plain values and nested objects
  #   - fn::secret for encrypted values
  #   - environmentVariables: exported to the shell by `esc run` / `esc open`
  #   - pulumiConfig: stack config for stacks that import this environment
  definition = <<-EOT
    values:
      app:
        name: example-app
        region: ${var.region}
        logLevel: info
        replicas: 2
      apiToken:
        fn::secret: ${var.api_token}
      environmentVariables:
        APP_NAME: $${app.name}
        AWS_REGION: $${app.region}
        LOG_LEVEL: $${app.logLevel}
        API_TOKEN: $${apiToken}
      pulumiConfig:
        aws:region: $${app.region}
        app:replicas: $${app.replicas}
    EOT
}

# There is no Terraform provider for Pulumi ESC, so the environment is
# managed by calling the Pulumi CLI from provisioners.
resource "terraform_data" "environment" {
  input            = local.environment_ref
  triggers_replace = [local.environment_ref]

  provisioner "local-exec" {
    command = "pulumi env init \"$ESC_ENV\""
    environment = {
      ESC_ENV = self.input
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "pulumi env rm \"$ESC_ENV\" --yes"
    environment = {
      ESC_ENV = self.input
    }
  }
}

# Re-applies the definition whenever the YAML changes or the environment
# is recreated. The YAML is passed on stdin so the secret never appears in
# the command line.
resource "terraform_data" "definition" {
  triggers_replace = [
    terraform_data.environment.id,
    sha256(local.definition),
  ]

  provisioner "local-exec" {
    command = "printf '%s' \"$ESC_YAML\" | pulumi env edit \"$ESC_ENV\" -f -"
    environment = {
      ESC_ENV  = terraform_data.environment.output
      ESC_YAML = local.definition
    }
  }
}
