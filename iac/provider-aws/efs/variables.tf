variable "prefix" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for EFS mount targets"
  type        = list(string)
}

variable "efs_sg_id" {
  description = "Security group ID for EFS"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
}

variable "persistent_volume_types" {
  description = "Map of persistent volume type names to their capacity configs. Each creates an EFS access point."
  type = map(object({
    capacity_gb = optional(number, 100)
  }))
  default = {}
}
