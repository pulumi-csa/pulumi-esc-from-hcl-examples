# Creating a Pulumi ESC environment and variables from HCL

This repository shows two ways to create a Pulumi ESC environment and its variables from HCL. Both write the same environment definition, including an encrypted secret. They differ in which tool runs the HCL.

| Directory | Approach | Run with |
| --- | --- | --- |
| [`pulumi-hcl/`](pulumi-hcl/README.md) | A Pulumi program written in HCL, using the Pulumi Service provider. | `pulumi up` |
| [`terraform-backend/`](terraform-backend/README.md) | A Terraform program that stores its state in Pulumi Cloud and calls the Pulumi CLI to manage the environment. | `terraform apply` |

Each directory has its own README with the full walkthrough. The two versions use separate Pulumi stacks and separate ESC environments, so both can be deployed at the same time.

## Configure your organization

No Pulumi Cloud organization name is written into the code. Before running either version, supply your own. Replace `<org>` below with the organization name shown in the Pulumi Cloud console or in the output of `pulumi whoami -v`. Your account needs permission to create stacks and ESC environments in it.

### `pulumi-hcl/`

```bash
pulumi stack init <org>/dev
pulumi config set organization <org>
```

The first command chooses the organization that stores the stack. The second sets the `organization` variable, which decides where the ESC environment is created. The value is saved in `Pulumi.dev.yaml`, which `.gitignore` keeps out of version control. `Pulumi.stack.example.yaml` is a template for that file.

### `terraform-backend/`

```bash
terraform init -backend-config="organization=<org>"
export TF_VAR_organization=<org>
```

The first command chooses the organization that stores the Terraform state. A backend block cannot read variables, so the name is passed at init time and remembered in the local `.terraform` directory. The second sets the `organization` variable for the ESC environment. A `terraform.tfvars` file works in place of the environment variable, and `.gitignore` excludes it.

### If it is missing

| Version | Step | Error |
| --- | --- | --- |
| `pulumi-hcl/` | `pulumi preview` or `pulumi up` | `variable "organization" is required but no value was provided` |
| `terraform-backend/` | `terraform init` | `The "organization" attribute value must not be empty` |
| `terraform-backend/` | `terraform plan` or `terraform apply` | `No value for required variable` |

## The difference

ESC environments are managed through the Pulumi Service provider, `pulumiservice`. That provider is a native Pulumi provider. It is not published to the Terraform registry, so only the Pulumi CLI can load it.

**Pulumi HCL** is a Pulumi language. The files look like Terraform, but the Pulumi engine runs them, so the program can declare a real `pulumiservice_environment` resource. Pulumi tracks that resource the way it tracks any other.

**Terraform with a Pulumi Cloud backend** keeps the Terraform CLI in charge. Pulumi Cloud replaces S3 or HCP Terraform as the place state is stored. That changes where state lives, not which providers Terraform can use. With no Terraform provider for ESC, the program falls back to `terraform_data` resources whose provisioners run `pulumi env init`, `pulumi env edit`, and `pulumi env rm`.

## Side by side

| | `pulumi-hcl/` | `terraform-backend/` |
| --- | --- | --- |
| CLI that runs the HCL | `pulumi` | `terraform` |
| How the environment is managed | `pulumiservice_environment` resource | `local-exec` provisioners calling the Pulumi CLI |
| Where state is stored | Pulumi Cloud stack | Pulumi Cloud stack, through `backend "remote"` |
| Change to the YAML | Updated in place | Provisioner resource replaced, definition rewritten |
| Preview of a YAML change | Shows `yaml` will change (contents hidden when a secret is present) | Shows a hash changed |
| Drift detection | Yes, with `--refresh` | No |
| Import an existing environment | Yes, with an `import` block | No |
| Revision number as an output | Yes | No |
| Secret in state | Encrypted | Not stored; only a hash of the definition |
| Credentials needed | Pulumi login | Pulumi login, plus a token for the Terraform backend |
| Tools needed | Pulumi CLI 3.256.0 or later | Terraform CLI and Pulumi CLI |
| Extra setup after the first init | None | Stack must be switched to local execution |
| ESC project created by default | `hcl-esc-example-pulumi` | `hcl-esc-example-terraform` |
| Pulumi stack | `<org>/hcl-esc-env-vars-pulumi/dev` | `<org>/hcl-esc-env-vars/dev` |

## Pulumi HCL

### Strengths

- The environment is a first-class resource. Pulumi knows its ID, its inputs, and its revision.
- Changes to the definition are applied in place, and each update reports the new revision.
- Drift is detectable. After a manual edit, `pulumi preview --refresh` shows the difference and `pulumi up --refresh` restores the program's definition.
- Existing environments can be imported with an `import` block, without recreating them.
- One tool and one login. Nothing shells out to another CLI.
- The rest of the `pulumiservice` provider is available in the same program, for example teams, access tokens, and stack settings.

### Weaknesses

- It is not Terraform. The `pulumi/pulumiservice` provider source and the `stringasset()` function do not work under the Terraform CLI; `terraform init` fails on these files.
- A team that uses Terraform today has to adopt the Pulumi CLI and its workflow for this project: stacks, `pulumi config`, and `pulumi up`.
- Pulumi HCL is a recent addition to Pulumi and needs CLI 3.256.0 or later.
- Changing the organization, project, or environment name replaces the environment.

## Terraform with a Pulumi Cloud backend

### Strengths

- The team keeps the Terraform CLI and its existing workflow: `init`, `plan`, `apply`, `destroy`, `tfvars` files.
- State sits in Pulumi Cloud next to any Pulumi stacks. Terraform resources and outputs show up in the stack view, and Pulumi Cloud handles state locking and access control.
- It fits a team that is moving state to Pulumi Cloud first and converting programs later.
- The secret value is never written to Terraform state.

### Weaknesses

- There is no ESC resource. The environment is created by shell commands, so Terraform tracks that the commands ran, not what the environment contains.
- No drift detection. After a manual edit to the environment, `terraform plan` still reports no changes.
- No import. If the environment already exists, `pulumi env init` fails with a conflict and the apply stops.
- Plans are less informative. A definition change appears as a replaced `terraform_data` resource with a changed hash.
- The machine running Terraform needs the Pulumi CLI installed and logged in, plus a separate token for the backend.
- The stack must be switched to local execution, because the provisioners need a logged-in Pulumi CLI. Pulumi Cloud's remote execution, and the preventative policies that depend on it, are not available to this project.
- A failed provisioner leaves the resource tainted, and it has to be cleared by fixing the cause and applying again.
- Changing the organization, project, or environment name deletes the environment and creates a new one.

## Which to use

Use `pulumi-hcl/` when the goal is to manage ESC environments properly from HCL. It is the only one of the two that treats the environment as a managed resource.

Use `terraform-backend/` when the Terraform CLI has to stay, and accept that the environment is managed by scripts wrapped in Terraform. A team in that position can also run both: keep existing Terraform programs on the Pulumi Cloud backend, and manage ESC environments from a small Pulumi HCL project.

## References

- [Pulumi HCL](https://www.pulumi.com/docs/iac/languages-sdks/hcl/)
- [pulumiservice Environment resource](https://www.pulumi.com/registry/packages/pulumiservice/api-docs/environment/)
- [Store Terraform state in Pulumi Cloud](https://www.pulumi.com/docs/integrations/terraform/state-backend/)
- [Terraform remote execution in Pulumi Cloud](https://www.pulumi.com/docs/integrations/terraform/remote-execution/)
- [Pulumi ESC](https://www.pulumi.com/docs/esc/)
