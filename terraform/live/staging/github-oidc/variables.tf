variable "github_repo" {
  description = "GitHub repository in owner/repo format — scopes the OIDC trust to this repo's main branch"
  type        = string
  default     = "technoe/roadpass-exam"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
