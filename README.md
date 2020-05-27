# OPA Meetup

OPA is a General Purpose Open Source Policy Engine, which decouples policy decision making from policy enforcement.
OPA generates policy decisions based on the json query and against policies and data. OPA is a [CNCF project](http://cncf.io), and [Styra](http://www.styra.com)is the main contributor to OPA.

For more information on OPA, visit the website [http://www.openpolicyagent.org](http://www.openpolicyagent.org)

## Presentation

Here is the meetup [presentation](https://docs.google.com/presentation/d/1QU_9pjOAJARb-QJX4eblCDfIcVksGlsFMYeLkDc1ewU/edit?usp=sharing) and live [youtube recording](https://youtu.be/bl6MSrDg_i4)

## Rego

Here are some sample rego files snippets, which we use in the [Rego playground](https://play.openpolicyagent.org/) and in visual studio [conftest](https://www.conftest.dev/) to build and test our policies.

### First Rego

In the first use case, we create a policy to check if the containers have labels. If not, the policy denies the container with the message `Containers must provide app label for pod selectors`.

`conftest test config/first.json -p policy/first.rego`

Fix the labels and check.

`conftest test config/first-w.json -p policy/first.rego`

### Second Rego

In the second use case, we create a policy to check if the containers are running as root user. If yes, the policy denies the container with the message `Containers must not run as root`.

`conftest test config/second.json -p policy/second.rego`

Fix the container spec to run as non root user

`conftest test config/second-w.json -p policy/second.rego`

### Third Rego

In the third use case, we create a policy to check if the containers images are from a corporate registry. If not, the policy denies the containers images from non trusted registry `Image ... comes from untrusted registry`.

`conftest test config/deployment.json -p policy/deployment.rego`

Fix the container spec to run as non root user

`conftest test config/deployment-w.json -p policy/deployment.rego`

Now, lets apply all these policies to our kubernetes cluster.

## Kubernetes

### Validating Admission Controller

In this section we will use the Kubernetes validating admission controller and gatekeeper.

### Installing Gatekeeper

This will install several resources into the Kubernetes cluster, notably the gatekeeper-controller-manager StatefulSet into its own gatekeeper-system Namespace.

`kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/70f65c411552170b4e155c550bc1755c412b27eb/deploy/gatekeeper.yaml`

### Constraints

Gatekeeper defines two types of Kubernetes custom resources for creating policies `ConstraintTemplates` and `Constraints`.

ConstraintTemplates are templates of an OPA policy and define the parameters needed to consume the template.
Once submitted, a ConstraintTemplate creates a Kubernetes custom resource based on the included configuration which is called a Constraint.

`cd kubernetes/validating`
`cat required-labels-template.yaml`

```yaml
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: requiredlabels
spec:
  crd:
    spec:
      names:
        kind: RequiredLabels
        listKind: RequiredLabelsList
        plural: requiredlabels
        singular: requiredlabels
      validation:
        # Schema for the `parameters` field in the constraint
        openAPIV3Schema:
          properties:
            labels:
              type: array
              items: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package requiredlabels
        violation[{"msg": msg, "details": {"missing_labels": missing}}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("you must provide labels for object %v : %v", [input.review.object.kind ,missing])
        }
```

`kubectl apply -f required-labels-template.yaml`
`kubectl get constrainttemplates.templates.gatekeeper.sh`

A Constraint contains the required parameters and what types of Kubernetes events will trigger policy evaluation. Once a Constraint is submitted to the cluster, it creates a unique ValidatingAdmissionWebhook object based on the configuration.

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: RequiredLabels
metadata:
  name: resources-must-have-owner
spec:
  match:
    namespace: ["default"]
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
  parameters:
    labels:
      - owner
```

`kubectl apply -f required-labels-constraint.yaml`
`kubectl get requiredlabels.constraints.gatekeeper.sh`

### Test

Next, create a pod without labels, which violates this constraints

`cat required-labels-deny.yaml`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: busybox-invalid
  labels:
spec:
  containers:
  - name: busybox
    image: busybox
    args:
      - sleep
      - "1000000"
```

`kubectl apply -f required-labels-deny.yaml`

> Error from server ([denied by resources-must-have-owner] you must provide labels for object Pod : {"owner"}): error when creating "required-labels-deny.yaml": admission webhook "validation.gatekeeper.sh" denied the request: [denied by resources-must-have-owner] you must provide labels for object Pod : {"owner"}

Now, create a pod which has labels and the policy allows this creation

```yaml
 apiVersion: v1
kind: Pod
metadata:
  name: busybox-valid
  labels:
    owner: busybox-owner
spec:
  containers:
  - name: busybox
    image: busybox
    args:
      - sleep
      - "1000000"
```

`kubectl apply -f required-labels-allow.yaml`

### Mutating Admission Controller

In this section we will use the Kubernetes mutating admission controller.

OPA Gatekeeper currently does not support generating Mutating admissions controllers based on ConstraintTemplates but to demonstrate a working example, we will use a simple REST API (Ruby Sinatra app) running in the Kubernetes cluster.

Similar to Validating admissions controllers, Mutating admissions controllers can be configured to be notified when specific events happen in the cluster like a CREATE or UPDATE. Instead of returning a yes or no response to the Kubernetes API, a Mutating admissions controller will return a JSON patch object that will tell Kubernetes how to modify the incoming resource.

This example will show how we can modify a submitted pod to add a label after it has been submitted to the cluster. This pattern can be extended to a number of other applications like injecting environment variables, adding side car containers, generating/injecting TLS certificates automatically, and so on. This is a powerful pattern for providing sane defaults to cluster consumers without placing the burden on those users to know how or what to implement for this type of information.

To get started, we first need to create a namespace for our mutating webhook: 

`kubectl create ns sinatra-mutating-webhook`

Kubernetes requires all admissions controllers to communicate over TLS so we need to generate a Certificate Signing Request that will be signed by the Kubernetes cluster certificate authority that will then be used by our REST api.

To simplify this, run the following to generate, sign, and upload a certificate to be used: 

`title="sinatra-mutating-webhook" ./gen-cert.sh`

Before we upload our Mutating Webhook, we need to include the Kubernetes cluster CA bundle in our configuration:

```bash
    ca_bundle=$(kubectl get configmap -n kube-system extension-apiserver-authentication -o=jsonpath='{.data.client-ca-file}' | base64 | tr -d '\n')
    sed -i -e "s/CA_BUNDLE_HERE/$ca_bundle/g" mutating-webhook.yaml
```

Now we can upload our Mutating Webhook to start receiving updates from the Kubernetes API:

`kubectl apply -f mutating-webhook.yaml`

Wait for our mutating webhook to become ready: 

`kubectl wait -n sinatra-mutating-webhook pod --all --for=condition=Ready --timeout=45s`

Finally, to see this working in action we can upload some pods to see it adding a label to each pod unless they specify a specific annotation to skip attaching a label:

`kubectl apply -f mutating-webhook-pod-test.yaml`

Run the following to see which pods were mutated by having a fun label attached. Notice that the excluded pod was skipped since it had a mutating-webhook.example.com/exclude annotation on it:

`kubectl get po -n sinatra-mutating-webhook-test --show-labels`

You can also view the logs of our Mutating Webhook to view the response object returned to the Kubernetes API:

`kubectl logs -n sinatra-mutating-webhook deploy/sinatra-mutating-webhook | grep -v 'GET /health'`

Finally, feel free to view the sample REST api code by inspecting mutating_webhook.rb to see the logic behind this example or to extend it if you are familiar with Ruby/Sinatra:

```bash
MUTATING_WEBHOOK_POD=$(kubectl get pod -n sinatra-mutating-webhook -l run=sinatra-mutating-webhook -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n sinatra-mutating-webhook $MUTATING_WEBHOOK_POD -- cat /app/mutating_webhook.rb
```

Credit for this mutating webhook goes to Austin Heiman with the code located here.

## Publish Rego Bundles

## Tools

- **yq**

    [https://github.com/mikefarah/yq](https://github.com/mikefarah/yq)

    Install yq (don't confuse with pip yq)

    `brew reinstall yq`

    Convert yaml to json

    `/usr/local/bin/yq r deployment.yaml -j -P > deployment.json`

- **Conftest**

    Conftest is a utility to help you write tests against structured configuration data. For instance you could write tests for your Kubernetes configurations, or Tekton pipeline definitions, Terraform code, Serverless configs or any other structured data.

    `brew tap instrumenta/instrumenta`

    `brew install conftest`

    Check the deployment against a policy which dis allows images from insecure registry

    `conftest test config/deployment.yaml -p policy/deployment.rego`

## References

1. [Using OPA and Gatekeeper for Admission Control policies](https://medium.com/@bikramgupta/using-opa-and-gatekeeper-for-admission-control-policies-709c749c76ff)

2. [Open Policy Agent Documentation](https://www.openpolicyagent.org/docs/latest/)

3. [SF Kubernetes Meetup: "Securing Kubernetes with Admission Control" with Ash Narka, SSE (Styra, Inc.)](https://www.youtube.com/watch?v=3Ea9okBUY5Y)

4. [Intro: Open Policy Agent - Torin Sandall, Styra](https://www.youtube.com/watch?v=Lca5u_ODS5s&t=999s)

5. [Forseti Policy Library](https://github.com/forseti-security/policy-library)
