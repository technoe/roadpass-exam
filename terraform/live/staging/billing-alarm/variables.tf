variable "alert_email" {
  description = "Email address to receive billing alerts (must confirm the SNS subscription)"
  type        = string
}

variable "threshold_usd" {
  description = "USD amount that triggers the billing alarm"
  type        = number
  default     = 50
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
