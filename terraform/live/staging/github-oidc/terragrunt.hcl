include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "./"
}

inputs = {
  github_repo = "technoe/roadpass-exam"
}
