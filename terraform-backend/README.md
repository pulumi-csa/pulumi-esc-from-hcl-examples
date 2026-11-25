# Pulumi ESC environment and variables with Terraform and a Pulumi Cloud backend

This example is a plain Terraform program that creates a Pulumi ESC environment and populates it with variables, including an encrypted secret. Terraform state is stored in Pulumi Cloud, in your organization. It runs with the `terraform` CLI, not `pulumi up`.

For a comparison with the Pulumi HCL version, see the [top-level README](../README.md).

## What it does

1. Stores Terraform state in Pulumi Cloud through a standard `backend "remote"` block pointed at `tf.pulumi.com`.
2. Creates the ESC environment `<org>/hcl-esc-example-terraform/dev`.
3. Writes the environment's YAML definition, which holds the variables.

There is no Terraform provider for Pulumi ESC. The Pulumi Service provider (`pulumiservice`) is a native Pulumi provider and is not published to the Terraform registry. This example therefore manages the environment by calling the Pulumi CLI from `local-exec` provisioners on two `terraform_data` resources.

ESC has no separate object for each variable. An environment's variables are the contents of its YAML definition. Everything under the `values` key becomes a variable in the environment:

| Key | Purpose |
| --- | --- |
| `app` | Plain configuration values: name, region, log level, replica count. |
| `apiToken` | A secret. `fn::secret` tells ESC to store it encrypted. |
| `environmentVariables` | Values exported as shell environment variables by `pulumi env run` and `esc run`. |
| `pulumiConfig` | Values supplied as stack configuration to any Pulumi stack that imports the environment. |

## Files

| File | Contents |
| --- | --- |
| `terraform.tf` | The Pulumi Cloud backend configuration. |
| `variables.tf` | The input variable definitions. |
| `main.tf` | The main program: the ESC YAML definition and the two resources that create the environment and apply the definition. |
| `outputs.tf` | The output. |

## How it works

### Backend

```hcl
terraform {
  backend "remote" {
    hostname = "tf.pulumi.com"

    workspaces {
      name = "hcl-esc-env-vars_dev"
    }
  }
}
```

Pulumi Cloud implements the Terraform remote backend API. The workspace name follows the convention `<project>_<stack>`, so `hcl-esc-env-vars_dev` is stored as the stack `dev` in the Pulumi project `hcl-esc-env-vars`. Terraform resources appear in that stack as `pulumi:terraform:<type>`, and Terraform outputs become stack outputs.

A backend block cannot use variables, so the organization is left out of the block and supplied when the backend is initialized, with `terraform init -backend-config="organization=<org>"`. Terraform remembers it in the local `.terraform` directory. The workspace name is written in directly.

### Execution mode

A stack that Terraform creates in Pulumi Cloud defaults to remote execution, where plans and applies run on Pulumi Cloud's runners. This example needs local execution, because its provisioners call the Pulumi CLI with your own login. The Deploy steps below switch the stack to local mode, after which Pulumi Cloud stores state only.

When Pulumi Cloud creates the stack it also creates a linked ESC environment with the same name, `<org>/hcl-esc-env-vars/dev`. That environment supplies variables to remote runs. It is separate from the environment this example creates, and it is not used in local mode.

### Input variables

| Variable | Default | Description |
| --- | --- | --- |
| `organization` | none (required) | Pulumi Cloud organization that owns the environment. |
| `project` | `hcl-esc-example-terraform` | ESC project the environment lives in. |
| `environment` | `dev` | ESC environment name. |
| `region` | `us-west-2` | Example value written into the environment. |
| `api_token` | none (required) | Example secret. Marked `sensitive`. |

Values come from `TF_VAR_` environment variables, `terraform.tfvars` or `*.auto.tfvars` files, or `-var` flags.

### The definition

The ESC YAML is a heredoc in a `locals` block in `main.tf`. Two kinds of interpolation appear in it, and the difference matters:

- `${var.region}` is resolved by Terraform at plan time. The deployed definition contains the literal value, such as `us-west-2`.
- `$${app.region}` is escaped. Terraform writes the literal text `${app.region}` into the definition, and ESC resolves it each time the environment is opened. This is how one ESC value references another.

### The resources

| Resource | On create | On destroy |
| --- | --- | --- |
| `terraform_data.environment` | Runs `pulumi env init <org>/<project>/<name>`. | Runs `pulumi env rm <org>/<project>/<name> --yes`. |
| `terraform_data.definition` | Pipes the YAML into `pulumi env edit <org>/<project>/<name> -f -`. | Nothing. The environment is removed by the other resource. |

`terraform_data.definition` is replaced, and so re-applied, whenever the SHA-256 hash of the YAML changes or the environment is recreated.

The YAML reaches the CLI on standard input through an environment variable, so the secret does not appear on the command line. Terraform suppresses the provisioner's output because the input is sensitive. Terraform state holds only the hash of the definition, not the secret. ESC encrypts the value itself because of `fn::secret`.

### Limits of this approach

- Terraform does not detect drift. If someone edits the environment in the Pulumi Cloud console, `terraform plan` still reports no changes.
- `pulumi env init` fails if the environment already exists. Existing environments cannot be imported.
- Changing `organization`, `project`, or `environment` deletes the old environment and creates a new one.
- The machine running Terraform needs the Pulumi CLI, logged in.

## Prerequisites

- Terraform CLI. Tested with 1.15.3.
- Pulumi CLI, logged in (`pulumi login`) with permission to create environments in the target organization.
- A Pulumi access token for the Terraform backend, supplied in one of two ways:
  - `terraform login tf.pulumi.com`, which opens a browser and stores a token.
  - The `TF_TOKEN_tf_pulumi_com` environment variable, for CI.

## Deploy

```bash
terraform login tf.pulumi.com
terraform init -backend-config="organization=<org>"
pulumi stack tag set terraform:execution-mode local -s <org>/hcl-esc-env-vars/dev
export TF_VAR_organization=<org>
export TF_VAR_api_token=<value>
terraform apply
```

Replace `<org>` with your Pulumi Cloud organization name. It is needed in two places, because the backend and the program are configured separately:

- `-backend-config="organization=<org>"` tells Terraform which organization stores the state. Without it, `terraform init` fails with `The "organization" attribute value must not be empty`.
- `TF_VAR_organization` tells the program which organization owns the ESC environment. Without it, `terraform plan` fails with `No value for required variable`.

`terraform init` creates the stack in Pulumi Cloud. The `pulumi stack tag set` command is needed once, after the first `init`.

## Verify

Show the definition, with secrets masked:

```bash
pulumi env get <org>/hcl-esc-example-terraform/dev
```

Open the environment and resolve every value, including secrets:

```bash
pulumi env open <org>/hcl-esc-example-terraform/dev
```

Run a command with the environment's `environmentVariables` exported:

```bash
pulumi env run <org>/hcl-esc-example-terraform/dev -- env | grep -E 'APP_NAME|AWS_REGION|LOG_LEVEL'
```

Confirm the state is in Pulumi Cloud:

```bash
terraform state list
pulumi stack -s <org>/hcl-esc-env-vars/dev
```

## Change the variables

Edit the YAML in `main.tf` and run `terraform apply`. Terraform replaces `terraform_data.definition`, which writes the new definition as a new revision of the environment.

To create the environment under a different project or name, override the defaults:

```bash
export TF_VAR_project=<project>
export TF_VAR_environment=<name>
```

## Clean up

```bash
terraform destroy
```

`terraform destroy` deletes the ESC environment. The stack that holds the state, and its linked ESC environment, remain in Pulumi Cloud. Removing the stack removes the linked environment with it:

```bash
pulumi stack rm <org>/hcl-esc-env-vars/dev
```

## References

- [Store Terraform state in Pulumi Cloud](https://www.pulumi.com/docs/integrations/terraform/state-backend/)
- [Terraform remote execution in Pulumi Cloud](https://www.pulumi.com/docs/integrations/terraform/remote-execution/)
- [Pulumi ESC](https://www.pulumi.com/docs/esc/)
