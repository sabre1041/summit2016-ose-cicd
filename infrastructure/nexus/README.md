Nexus Docker Container
===================

Preconfigured Sonatype Nexus Docker image to proxy external repositories and to store artifacts

# Building and Running with Docker

Build the image by running the following command within this directory:

    docker build -t ose-bdd-demo/nexus

Launch an instance of the newly created image

    docker run -it --rm -p 8081:8081 ose-bdd-demo/nexus

Nexus will be available at http://&lt;DOCKER_IP&gt;:8081

# Building in OpenShift

Login to OpenShift and create a new project or use an existing project

Create a new build of the application by running the following commands within this directory

    oc new-build registry.access.redhat.com/rhel7/rhel --name=nexus --binary=true
    
Start a new build of the Nexus image

    oc start-build nexus --from-dir=.
    
Once the build has completed, launch a new application

    oc new-app nexus
    
Expose the service so that the application is accessible externally

    oc expose svc nexus
    
Nexus will be available at http://nexus.&lt;PROJECT&gt;.&lt;DEFAULT_SUBDOMAIN&gt;