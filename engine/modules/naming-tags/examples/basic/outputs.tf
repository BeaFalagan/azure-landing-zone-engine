output "names" {
  description = "Generated names."
  value       = module.naming.names
}

output "tags" {
  description = "Resulting tags."
  value       = module.naming.tags
}
