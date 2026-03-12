include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "./"
}

inputs = {
  # Update with your email address — AWS will send a confirmation link
  alert_email   = "technoe@gmail.com"
  threshold_usd = 50
}
