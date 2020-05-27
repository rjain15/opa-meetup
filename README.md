# OPA Meetup

## Rego

Here are some sample rego files snippets, which we use in the `rego playground` and in visual studio `conftest` to build and test our policies. 

### First Rego

In the first use case, we create a policy to check if the containers have labels. If not, the policy denies the container with the message `Containers must provide app label for pod selectors`

`conftest test config/first.json -p policy/first.rego`

Fix the labels and check.

`conftest test config/first-w.json -p policy/first.rego`

### Second Rego

In the second use case, we create a policy to check if the containers are running as root user. If yes, the policy denies the container with the message `Containers must not run as root"`

`conftest test config/second.json -p policy/second.rego`

Fix the container spec to run as non root user

`conftest test config/second-w.json -p policy/second.rego`

### Third Rego

In the third use case, we create a policy to check if the containers images are from a corporate registry. If no, the policy denies the containers images from non trusted registry `Image ... comes from untrusted registry"`

`conftest test config/deployment.json -p policy/deployment.rego`

Fix the container spec to run as non root user

`conftest test config/deployment-w.json -p policy/deployment.rego`

Now, lets apply all these policies to our kubernetes cluster.

## Kubernetes

## Testing in VSCode

## Publish Rego Bundles

## Tools

1. yq (<https://github.com/mikefarah/yq)>

Install yq (don't confuse with pip yq)
`brew reinstall yq`

Convert yaml to json
`/usr/local/bin/yq r deployment.yaml -j -P > deployment.json`

2. Conftest

Conftest is a utility to help you write tests against structured configuration data. For instance you could write tests for your Kubernetes configurations, or Tekton pipeline definitions, Terraform code, Serverless configs or any other structured data.

`brew tap instrumenta/instrumenta`
`brew install conftest`

Check the deployment against a policy which dis allows images from insecure registry

`conftest test config/deployment.yaml -p policy/deployment.rego`

## References

1. https://medium.com/@bikramgupta/using-opa-and-gatekeeper-for-admission-control-policies-709c749c76ff

