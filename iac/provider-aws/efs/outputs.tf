output "efs_id" {
  value = aws_efs_file_system.shared_cache.id
}

output "efs_dns_name" {
  value = aws_efs_file_system.shared_cache.dns_name
}

output "efs_access_point_id" {
  value = aws_efs_access_point.chunks_cache.id
}

output "persistent_volume_mounts" {
  description = "Map of persistent volume type names to their EFS mount paths"
  value = {
    for key, _ in var.persistent_volume_types : key => "/mnt/persistent-volume-types/${key}"
  }
}

output "persistent_volume_access_point_ids" {
  description = "Map of persistent volume type names to their EFS access point IDs"
  value = {
    for key, ap in aws_efs_access_point.persistent_volume : key => ap.id
  }
}
