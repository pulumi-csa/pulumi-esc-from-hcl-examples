# Pulumi ESC environment and variables with Pulumi HCL

This example is a Pulumi program written in HCL. It creates a Pulumi ESC environment and populates it with variables, including an encrypted secret, in your Pulumi Cloud organization. It runs with the `pulumi` CLI, not `terraform`.

For a comparison with the Terraform version, see the [top-level README](../README.md).

## What it does

The program declares one resource, `pulumiservice_environment`, from the Pulumi Service provider. That resource creates the ESC environment `<org>/hcl-esc-example-pulumi/dev` and sets its definition.

ESC has no separate resource for each variable. An environment's variables are the contents of its YAML definition, so the program passes that YAML to the resource's `yaml` argument as a string asset. Everything under the `values` key becomes a variable in the environment:

| Key | Purpose |
| --- | --- |
| `app` | Plain configuration values: name, region, log level, replica count. |
| `apiToken` | A secret. `fn::secret` tells ESC to store it encrypted. |
| `environmentVariables` | Values exported as shell environment variables by `pulumi env run` and `esc run`. |
| `pulumiConfig` | Values supplied as stack configuration to any Pulumi stack that imports the environment. |

## Files

| File | Contents |
| --- | --- |
| `Pulumi.yaml` | Project definition. `runtime: hcl` selects the Pulumi HCL language. |
| `Pulumi.dev.yaml` | Configuration for the `dev` stack: your organization and the encrypted `api_token` value. Created by `pulumi config set` and excluded from version control by `.gitignore`. |
| `Pulumi.stack.example.yaml` | A template for the stack configuration file. Copy it to `Pulumi.<stack>.yaml` and fill it in. |
| `terraform.tf` | The provider configuration: the `pulumiservice` provider requirement. |
| `variables.tf` | The input variable definitions. |
| `main.tf` | The main program: the environment resource. |
| `outputs.tf` | The stack outputs. |

## How the HCL works

### Provider

```hcl
terraform {
  required_providers {
    pulumiservice = {
      source  = "pulumi/pulumiservice"
      version = "1.9.0"
    }
  }
}
```

The `pulumi/` prefix in `source` selects the native Pulumi provider rather than a Terraform provider from the OpenTofu registry. Native providers need an exact version, not a version constraint.

### Input variables

| Variable | Default | Description |
| --- | --- | --- |
| `organization` | none (required) | Pulumi Cloud organization that owns the environment. |
| `project` | `hcl-esc-example-pulumi` | ESC project the environment lives in. |
| `environment` | `dev` | ESC environment name. |
| `region` | `us-west-2` | Example value written into the environment. |
| `api_token` | none (required) | Example secret. Marked `sensitive`. |

Values come from stack configuration (`pulumi config set`), `terraform.tfvars` or `*.auto.tfvars` files, or `TF_VAR_` environment variables.

### The environment resource

```hcl
resource "pulumiservice_environment" "example" {
  organization = var.organization
  project      = var.project
  name         = var.environment

  yaml = stringasset(<<-EOT
    values:
      app:
        region: ${var.region}
      apiToken:
        fn::secret: ${var.api_token}
      environmentVariables:
        AWS_REGION: $${app.region}
        API_TOKEN: $${apiToken}
    EOT
  )
}
```

Two kinds of interpolation appear in the YAML, and the difference matters:

- `${var.region}` is resolved by HCL when the program runs. The deployed definition contains the literal value, such as `us-west-2`.
- `$${app.region}` is escaped. HCL writes the literal text `${app.region}` into the definition, and ESC resolves it each time the environment is opened. This is how one ESC value references another.

Because `api_token` is a sensitive variable, Pulumi treats the whole `yaml` input as a secret, encrypts it in stack state, and hides it in previews. ESC then encrypts the value itself because of `fn::secret`.

### Outputs

| Output | Value |
| --- | --- |
| `environment` | The full environment path, `organization/project/name`. |
| `revision` | The revision number of the latest version of the environment. |

## Prerequisites

- Pulumi CLI 3.256.0 or later. The HCL language plugin downloads automatically.
- A Pulumi Cloud login (`pulumi login`) with permission to create environments in the target organization.

## Deploy

```bash
pulumi install
pulumi stack init <org>/dev
pulumi config set organization <org>
pulumi config set --secret api_token <value>
pulumi up
```

Replace `<org>` with your Pulumi Cloud organization name. No organization is written into the code, so the program fails with `variable "organization" is required` until it is set.

Run `pulumi install` again whenever the set of providers changes.

As an alternative to `pulumi config set organization`, start from the template. Copy it to match your stack name, replace `<org>` in the copy, then set the secret with the CLI:

```bash
cp Pulumi.stack.example.yaml Pulumi.dev.yaml
pulumi config set --secret api_token <value>
```

The secret cannot be written into the file by hand, because it is encrypted with a key that belongs to your stack.

## Verify

Show the definition, with secrets masked:

```bash
pulumi env get <org>/hcl-esc-example-pulumi/dev
```

Open the environment and resolve every value, including secrets:

```bash
pulumi env open <org>/hcl-esc-example-pulumi/dev
```

Run a command with the environment's `environmentVariables` exported:

```bash
pulumi env run <org>/hcl-esc-example-pulumi/dev -- env | grep -E 'APP_NAME|AWS_REGION|LOG_LEVEL'
```

## Change the variables

Edit the YAML in `main.tf` and run `pulumi up`. The environment is updated in place. Each update creates a new revision, and the `revision` output reports the latest one.

To create the environment under a different project or name, override the defaults:

```bash
pulumi config set project <project>
pulumi config set environment <name>
```

Changing the organization, project, or name on a deployed stack replaces the environment: Pulumi creates the new one and deletes the old one.

## Detect and correct drift

If someone edits the environment outside this program, a refresh picks it up:

```bash
pulumi preview --refresh
pulumi up --refresh
```

The preview shows the changed revision and a pending update to `yaml`. The update writes the program's definition back.

## Import an existing environment

An environment that already exists can be brought under management with an `import` block. The ID format is `organization/project/environment`.

```hcl
import {
  to = pulumiservice_environment.example
  id = "<org>/hcl-esc-example-pulumi/dev"
}
```

## Clean up

```bash
pulumi destroy
pulumi stack rm <org>/dev
```

`pulumi destroy` deletes the ESC environment.

## References

- [pulumiservice Environment resource](https://www.pulumi.com/registry/packages/pulumiservice/api-docs/environment/)
- [Pulumi HCL](https://www.pulumi.com/docs/iac/languages-sdks/hcl/)
- [Pulumi ESC](https://www.pulumi.com/docs/esc/)
