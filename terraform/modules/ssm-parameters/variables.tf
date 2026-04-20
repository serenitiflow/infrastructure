variable "parameters" {
  description = "Map of SSM parameter names to their values"
  type = map(object({
    value = string
    type  = optional(string, "String")
  }))
}

variable "tags" {
  description = "Tags to apply to all parameters"
  type        = map(string)
  default     = {}
}
