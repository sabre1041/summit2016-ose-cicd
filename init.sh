#!/bin/bash

set -e

SCRIPT_BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# Login Information
OSE_CLI_USER="admin"
OSE_CLI_PASSWORD="admin"
OSE_CLI_HOST="https://10.1.2.2:8443"

CUSTOM_BASE_IMAGE_PROJECT="custom-base-image"

OSE_CI_PROJECT="ci"
OSE_API_APP_DEV="api-app-dev"
OSE_API_APP_UAT="api-app-uat"
OSE_API_APP_PROD="api-app-prod"


POSTGRESQL_USER="postgresql"
POSTGRESQL_PASSWORD="password"
POSTGRESQL_DATABASE="gogs"
GOGS_ADMIN_USER="gogs"
GOGS_ADMIN_PASSWORD="osegogs"


function wait_for_running_build() {
    APP_NAME=$1
    NAMESPACE=$2
    BUILD_NUMBER=$3

    [ ! -z "$3" ] && BUILD_NUMBER="$3" || BUILD_NUMBER="1"

    set +e

    while true
    do
        BUILD_STATUS=$(oc get builds ${APP_NAME}-${BUILD_NUMBER} -n ${NAMESPACE} --template='{{ .status.phase }}')

        if [ "$BUILD_STATUS" == "Running" ] || [ "$BUILD_STATUS" == "Complete" ] || [ "$BUILD_STATUS" == "Failed" ]; then
           break
        fi
    done

    set -e

}

function wait_for_endpoint_registration() {
    ENDPOINT=$1
    NAMESPACE=$2
    
    set +e
    
    while true
    do
        oc get ep $ENDPOINT -n $NAMESPACE -o yaml | grep "\- addresses:"
        
        if [ $? -eq 0 ]; then
            break
        fi
        
        sleep 10
        
    done

    set -e
}

# Login to OSE
oc login -u ${OSE_CLI_USER} -p ${OSE_CLI_PASSWORD} ${OSE_CLI_HOST} --insecure-skip-tls-verify=true

# Create CI Project
echo
echo "Creating new CI Project (${OSE_CI_PROJECT})..."
echo
oc new-project ${OSE_CI_PROJECT}

# Create Custom Base Image Project
echo
echo "Creating new Custom Base Image Project (${CUSTOM_BASE_IMAGE_PROJECT})..."
echo
oc new-project ${CUSTOM_BASE_IMAGE_PROJECT}

# Create App Dev Project
echo
echo "Creating new App Dev Project (${OSE_API_APP_DEV})..."
echo
oc new-project ${OSE_API_APP_DEV}

# Create App UAT Project
echo
echo "Creating new App UAT Project (${OSE_API_APP_UAT})..."
echo
oc new-project ${OSE_API_APP_UAT}

# Create App Prod Project
echo
echo "Creating new App Prod Project (${OSE_API_APP_PROD})..."
echo
oc new-project ${OSE_API_APP_PROD}

# Grant Default CI Account Edit Access to All Projects and OpenShift Project
oc policy add-role-to-user edit system:serviceaccount:${OSE_CI_PROJECT}:default -n ${OSE_CI_PROJECT}
oc policy add-role-to-user edit system:serviceaccount:${OSE_CI_PROJECT}:default -n ${CUSTOM_BASE_IMAGE_PROJECT}
oc policy add-role-to-user edit system:serviceaccount:${OSE_CI_PROJECT}:default -n ${OSE_API_APP_DEV}
oc policy add-role-to-user edit system:serviceaccount:${OSE_CI_PROJECT}:default -n ${OSE_API_APP_UAT}
oc policy add-role-to-user edit system:serviceaccount:${OSE_CI_PROJECT}:default -n ${OSE_API_APP_PROD}
oc policy add-role-to-user edit system:serviceaccount:${OSE_CI_PROJECT}:default -n openshift

# Grant Default Service Account in Each Project Editt Access
oc policy add-role-to-user edit system:serviceaccount:${OSE_API_APP_DEV}:default -n ${OSE_API_APP_DEV}
oc policy add-role-to-user edit system:serviceaccount:${OSE_API_APP_UAT}:default -n ${OSE_API_APP_UAT}
oc policy add-role-to-user edit system:serviceaccount:${OSE_API_APP_PROD}:default -n ${OSE_API_APP_PROD}


# Grant Higher Level Service Account Access to the Dev Project for ImageStream Tagging
# TODO: Refactor to only ImagePuller role
oc policy add-role-to-user edit system:serviceaccount:${OSE_API_UAT_PROD}:default -n ${OSE_API_APP_DEV}
oc policy add-role-to-user edit system:serviceaccount:${OSE_API_APP_PROD}:default -n ${OSE_API_APP_DEV}


# Grant Access For Builder Account to Pull Images in Dev Project
oc policy add-role-to-user edit system:serviceaccount:${OSE_API_APP_DEV}:builder -n ${CUSTOM_BASE_IMAGE_PROJECT}



# CI Project

# Process RHEL Template
echo
echo "Waiting for RHEL ImageStream Template..."
echo
oc create -n ${OSE_CI_PROJECT} -f"${SCRIPT_BASE_DIR}/support/templates/rhel7-is.json"

# Import Upstream Image
echo
echo "Importing RHEL7 ImageStream..."
echo
oc import-image -n ${OSE_CI_PROJECT} rhel7

# Process Nexus Template
echo
echo "Processing Nexus Template..."
echo
oc process -v APPLICATION_NAME=nexus -f "${SCRIPT_BASE_DIR}/support/templates/nexus-ephemeral-template.json" | oc -n ${OSE_CI_PROJECT} create -f -

echo
echo "Waiting for Nexus build to begin..."
echo
wait_for_running_build "nexus" "${OSE_CI_PROJECT}"

# Cancel initial build since this is a binary build with no content
oc cancel-build -n ${OSE_CI_PROJECT} nexus-1

echo
echo "Starting Nexus binary build..."
echo
oc start-build -n ${OSE_CI_PROJECT} nexus --from-dir="${SCRIPT_BASE_DIR}/infrastructure/nexus"

wait_for_running_build "nexus" "${OSE_CI_PROJECT}" "2"

oc build-logs -n ${OSE_CI_PROJECT} -f nexus-2


echo
echo "Deploying PostgreSQL for Gogs..."
echo
oc process -f $SCRIPT_BASE_DIR/support/templates/postgresql-persistent.json -v=POSTGRESQL_DATABASE=$POSTGRESQL_DATABASE,POSTGRESQL_USER=$POSTGRESQL_USER,POSTGRESQL_PASSWORD=$POSTGRESQL_PASSWORD  | oc create -n $OSE_CI_PROJECT -f-

wait_for_endpoint_registration "postgresql" "$OSE_CI_PROJECT"

echo
echo "Deploying Gogs Server..."
echo
oc process -f $SCRIPT_BASE_DIR/support/templates/gogs-persistent-template.json | oc create -n $OSE_CI_PROJECT -f-

wait_for_endpoint_registration "gogs" "$OSE_CI_PROJECT"

# Determine Running Pod
GOGS_POD=$(oc get pods -n $OSE_CI_PROJECT -l=deploymentconfig=gogs --no-headers | awk '{ print $1 }')

GOGS_ROUTE=$(oc get routes -n $OSE_CI_PROJECT gogs --template='{{ .spec.host }}')

# Sleep before setting up gogs server
sleep 10


echo
echo "Setting up Gogs Server..."
echo
# Setup Server
HTTP_RESPONSE=$(curl -o /dev/null -sL -w "%{http_code}" http://$GOGS_ROUTE/install \
--form db_type=PostgreSQL \
--form db_host=postgresql:5432 \
--form db_user=$POSTGRESQL_USER \
--form db_passwd=$POSTGRESQL_PASSWORD \
--form db_name=$POSTGRESQL_DATABASE \
--form ssl_mode=disable \
--form db_path=data/gogs.db \
--form "app_name=Gogs: Go Git Service" \
--form repo_root_path=/home/gogs/gogs-repositories \
--form run_user=gogs \
--form domain=localhost \
--form ssh_port=22 \
--form http_port=3000 \
--form app_url=http://$GOGS_ROUTE/ \
--form log_root_path=/opt/gogs/log \
--form admin_name=$GOGS_ADMIN_USER \
--form admin_passwd=$GOGS_ADMIN_PASSWORD \
--form admin_confirm_passwd=$GOGS_ADMIN_PASSWORD \
--form admin_email=gogs@redhat.com)

if [ $HTTP_RESPONSE != "200" ]
then
    echo "Error occurred when installing Gogs Service. HTTP Response $HTTP_RESPONSE"
    exit 1
fi

echo
echo "Initialized Gogs Server...."
echo


sleep 10

echo
echo "Setting up custom base image git repository..."
echo
oc rsync -n $OSE_CI_PROJECT $SCRIPT_BASE_DIR/custom-base-image $GOGS_POD:/tmp/
oc rsh -n $OSE_CI_PROJECT -t $GOGS_POD bash -c "cd /tmp/custom-base-image && git init && git config --global user.email 'gogs@redhat.com' && git config --global user.name 'gogs' && git add . &&  git commit -m 'initial commit'"
curl -H "Content-Type: application/json" -X POST -d '{"clone_addr": "/tmp/custom-base-image","uid": 1,"repo_name": "custom-base-image"}' --user $GOGS_ADMIN_USER:$GOGS_ADMIN_PASSWORD http://$GOGS_ROUTE/api/v1/repos/migrate
curl -H "Content-Type: application/json" -X POST -d '{"type": "gogs","config": { "url": "http://admin:password@jenkins:8080/job/custom-base-image-pipeline/build?delay=0", "content_type": "json" }, "active": true }' --user $GOGS_ADMIN_USER:$GOGS_ADMIN_PASSWORD http://$GOGS_ROUTE/api/v1/repos/gogs/custom-base-image/hooks

echo
echo "Setting up OSE API App repository..."
echo
oc rsync -n $OSE_CI_PROJECT $SCRIPT_BASE_DIR/ose-api-app $GOGS_POD:/tmp/
oc rsh -n $OSE_CI_PROJECT -t $GOGS_POD bash -c "cd /tmp/ose-api-app && git init && git config --global user.email 'gogs@redhat.com' && git config --global user.name 'gogs' && git add . &&  git commit -m 'initial commit'"
curl -H "Content-Type: application/json" -X POST -d '{"clone_addr": "/tmp/ose-api-app","uid": 1,"repo_name": "ose-api-app"}' --user $GOGS_ADMIN_USER:$GOGS_ADMIN_PASSWORD http://$GOGS_ROUTE/api/v1/repos/migrate
curl -H "Content-Type: application/json" -X POST -d '{"type": "gogs","config": { "url": "http://admin:password@jenkins:8080/job/ose-api-app-pipeline/build?delay=0", "content_type": "json" }, "active": true }' --user $GOGS_ADMIN_USER:$GOGS_ADMIN_PASSWORD http://$GOGS_ROUTE/api/v1/repos/gogs/ose-api-app/hooks

echo
echo "Setting up persistent gogs configuration..."
echo

mkdir -p $SCRIPT_BASE_DIR/installgogs
oc rsync -n ${OSE_CI_PROJECT} $GOGS_POD:/etc/gogs installgogs/
oc secrets new gogs-config -n ${OSE_CI_PROJECT} $SCRIPT_BASE_DIR/installgogs/gogs/conf
oc volume dc/gogs -n ${OSE_CI_PROJECT} --add --overwrite --name=config-volume -m /etc/gogs/conf/ --type=secret --secret-name=gogs-config
rm -rf $SCRIPT_BASE_DIR/installgogs

# Process Jenkins Agent Template
echo
echo "Processing Jenkins Agent Template..."
echo
oc process -v APPLICATION_NAME=jenkins-agent -f "${SCRIPT_BASE_DIR}/support/templates/jenkins-agent-template.json" | oc -n ${OSE_CI_PROJECT} create -f -

echo
echo "Starting Jenkins Agent binary build..."
echo
oc start-build -n ${OSE_CI_PROJECT} jenkins-agent --from-dir="${SCRIPT_BASE_DIR}/infrastructure/jenkins-agent"

wait_for_running_build "jenkins-agent" "${OSE_CI_PROJECT}"

oc build-logs -n ${OSE_CI_PROJECT} -f jenkins-agent-1

# Process Jenkins Template
echo
echo "Processing Jenkins Template..."
echo
oc process -v APPLICATION_NAME=jenkins -f "${SCRIPT_BASE_DIR}/support/templates/jenkins-template.json" | oc -n ${OSE_CI_PROJECT} create -f -

echo
echo "Starting Jenkins binary build..."
echo
oc start-build -n ${OSE_CI_PROJECT} jenkins --from-dir="${SCRIPT_BASE_DIR}/infrastructure/jenkins"

wait_for_running_build "jenkins" "${OSE_CI_PROJECT}"

oc build-logs -n ${OSE_CI_PROJECT} -f jenkins-1


oc project ${CUSTOM_BASE_IMAGE_PROJECT}


echo
echo "Instantiating the base builder and associated dependencies in the ${CUSTOM_BASE_IMAGE_PROJECT} project..."
echo
oc process -f "$SCRIPT_BASE_DIR/support/templates/custom-base-image-template.json" | oc -n ${CUSTOM_BASE_IMAGE_PROJECT} create -f-

echo
echo "Importing upstream OpenShift Base Centos 7 Image..."
echo
oc import-image base-centos -n ${CUSTOM_BASE_IMAGE_PROJECT}

echo
echo "Waiting for custom base image build to begin..."
echo
wait_for_running_build "custom-base-image" "${CUSTOM_BASE_IMAGE_PROJECT}"

# Cancel initial build since this is a binary build with no content
echo
echo "Cancelling initial custom base image build..."
echo
oc cancel-build custom-base-image-1 -n ${CUSTOM_BASE_IMAGE_PROJECT}



oc project ${OSE_API_APP_DEV}

echo
echo "Instantiating the application and associated dependencies in the ${OSE_API_APP_DEV} project..."
echo
oc process -f "$SCRIPT_BASE_DIR/support/templates/app-template.json" -v=CUSTOM_BASE_IMAGE_TAG=1.0,APPLICATION_NAME=ose-api-app | oc -n ${OSE_API_APP_DEV} create -f-


#TODO: Delete builds as well?

oc project ${OSE_API_APP_UAT}

echo
echo "Instantiating the application and associated dependencies in the ${OSE_API_APP_UAT} project..."
echo
oc process -f "$SCRIPT_BASE_DIR/support/templates/app-template.json" -v=APPLICATION_NAME=ose-api-app | oc create -n ${OSE_API_APP_UAT} -f-

# Delete BuildConfig object as it is not needed in this project
echo
echo "Deleting BuildConfig in the ${OSE_API_APP_UAT} project..."
echo
oc delete bc ose-api-app -n ${OSE_API_APP_UAT}


oc project ${OSE_API_APP_PROD}

echo
echo "Instantiating the application and associated dependencies in the ${OSE_API_APP_PROD} project..."
echo
oc process -f "$SCRIPT_BASE_DIR/support/templates/app-template.json" -v=APPLICATION_NAME=ose-api-app | oc create -n ${OSE_API_APP_PROD} -f-

# Delete BuildConfig object as it is not needed in this project
echo
echo "Deleting BuildConfig in the ${OSE_API_APP_PROD} project..."
echo
oc delete bc ose-api-app -n ${OSE_API_APP_PROD}

echo
echo "=================================="
echo "Setup Complete!"
echo "=================================="

