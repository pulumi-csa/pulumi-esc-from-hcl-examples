# The environment definition is ordinary ESC YAML passed as a string asset.
# Everything under "values" is a variable in the environment:
#   - plain values and nested objects
#   - fn::secret for encrypted values
#   - environmentVariables: exported to the shell by `esc run` / `esc open`
#   - pulumiConfig: stack config for stacks that import this environment
resource "pulumiservice_environment" "example" {
  organization = var.organization
  project      = var.project
  name         = var.environment

  yaml = stringasset(<<-EOT
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
  )
}
