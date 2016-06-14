Red Hat Summit 2016 Enterprise CI/CD with OpenShift
==============================

This repository contains the material for the 2016 Enterprise CI/CD with OpenShift presentation

## Building the Demo Locally

Use the following steps to build the demo in an OpenShift environment:

First, make sure to login to an OpenShift environment
    
    oc login <openshift_master_url>
    
Create a new project

    oc new-project swarm
    

Grant default service account *edit* access on the project

    oc policy add-role-to-user edit system:service account:swarm:default
    
Instantiate the `swarm-s2i` template

    oc process -f support/swarm-s2i-template.json | oc create -f-
    
Cancel the initial build initiated by the template instantiation:

    oc cancel-build swarm-s2i-1
    
Start a new binary build for the swarm builder image

    oc start-build swarm-s2i --follow --from-dir=wildfly-swarm-s2i/
    
Instantiate the `swarm-app` template

oc process -f support/swarm-app-template.json -v IMAGE_STREAM_NAMESPACE=swarm | oc create -f-

Cancel the initial build initiated by the template instantiation:

    oc cancel-build swarm-app-1
    
Start a new binary build for the swarm application

    oc start-build swarm-app --follow --from-dir=ose-cicd-api/

Validate the pod is running after the builds complete by running `oc get pods -l "application=swarm-app"`

Validate the UI can be reached

    curl http://$(oc get routes swarm-app --template='{{ .spec.host }}')
    
Validate the rest API can be reached by requesting the list of running pods

    curl http://$(oc get routes swarm-app --template='{{ .spec.host }}')/rest/api/pods