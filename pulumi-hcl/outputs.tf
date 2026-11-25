output "environment" {
  value = "${pulumiservice_environment.example.organization}/${pulumiservice_environment.example.project}/${pulumiservice_environment.example.name}"
}

output "revision" {
  value = pulumiservice_environment.example.revision
}
