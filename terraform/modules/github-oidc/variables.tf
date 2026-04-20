variable "project_name" {
  description = "Project name"
  type        = string
}

variable "allowed_repositories" {
  description = "List of GitHub repository subjects allowed to assume this role (e.g. repo:org/repo:ref:refs/heads/main)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
