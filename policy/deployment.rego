package main

deny[msg] {
  input.kind = "Deployment"
  not input.spec.securityContext.runAsNonRoot = true
  msg = "Containers must not run as root"
}

deny[msg] {
  input.kind = "Deployment"
  not input.spec.selector.matchLabels.app
  msg = "Containers must provide app label for pod selectors"
}

deny[msg] {
	# The `some` keyword declares local variables. This rule declares a variable
	# called `i`. The rule asks if there is some array index `i` such that the value
	# of the array element's `"image"` field does not start with "hooli.com/".
	some i
	input.kind == "Deployment"
    image := input.spec.template.spec.containers[i].image
	not startswith(image, "hooli.com/")
	msg := sprintf("Image '%v' comes from untrusted registry", [image])
}