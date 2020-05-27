package main

deny[msg] {
  input.kind = "Deployment"
  not input.spec.securityContext.runAsNonRoot = true
  msg = "Containers must not run as root"
}
