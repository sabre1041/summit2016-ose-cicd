#!/bin/bash

#set -e

SCRIPT_BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# Login Information
OSE_CLI_USER="admin"
OSE_CLI_PASSWORD="admin"
OSE_CLI_HOST="https://10.1.2.2:8443"

OSE_SWARM_INFRA_PROJECT="swarm-infra"

OSE_CI_PROJECT="ci"
OSE_SWARM_APP_DEV="swarm-dev"
OSE_SWARM_APP_QA="swarm-qa"
OSE_SWARM_APP_PROD="swarm-prod"


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

# Login to CDK
oc login -u ${OSE_CLI_USER} -p ${OSE_CLI_PASSWORD} ${OSE_CLI_HOST} --insecure-skip-tls-verify=true

# Create CI Project
echo
echo "Creating new CI Project (${OSE_CI_PROJECT})..."
echo
oc new-project ${OSE_CI_PROJECT}

# Create Infrastructure Project
echo
echo "Creating new Infrastructure Project (${OSE_SWARM_INFRA_PROJECT})..."
echo
oc new-project ${OSE_SWARM_INFRA_PROJECT}

# Create App Dev Project
echo
echo "Creating new App Dev Project (${OSE_SWARM_APP_DEV})..."
echo
oc new-project ${OSE_SWARM_APP_DEV}

# Create App Prod Project
echo
echo "Creating new App Prod Project (${OSE_SWARM_APP_PROD})..."
echo
oc new-project ${OSE_SWARM_APP_PROD}

# Grant Default CI Account Edit Access to All Projects and OpenShift Project
oc policy add-role-to-user edit system:serviceaccount:${OSE_CI_PROJECT}:default -n ${OSE_CI_PROJECT}
oc policy add-role-to-user edit system:serviceaccount:${OSE_CI_PROJECT}:default -n ${OSE_SWARM_INFRA_PROJECT}
oc policy add-role-to-user edit system:serviceaccount:${OSE_CI_PROJECT}:default -n ${OSE_SWARM_APP_DEV}
oc policy add-role-to-user edit system:serviceaccount:${OSE_CI_PROJECT}:default -n ${OSE_SWARM_APP_PROD}
oc policy add-role-to-user edit system:serviceaccount:${OSE_CI_PROJECT}:default -n openshift

# Grant Default Service Account in Each Project Editt Access
oc policy add-role-to-user edit system:serviceaccount:${OSE_SWARM_APP_DEV}:default -n ${OSE_SWARM_APP_DEV}
oc policy add-role-to-user edit system:serviceaccount:${OSE_SWARM_APP_PROD}:default -n ${OSE_SWARM_APP_PROD}


# Grant Higher Level Service Account Access to the Dev Project for ImageStream Tagging
# TODO: Refactor to only ImagePuller role
oc policy add-role-to-user edit system:serviceaccount:${OSE_SWARM_APP_PROD}:default -n ${OSE_SWARM_APP_DEV}


# Grant Access For Builder Account to Pull Images in Dev Project
oc policy add-role-to-user edit system:serviceaccount:${OSE_SWARM_APP_DEV}:builder -n ${OSE_SWARM_INFRA_PROJECT}



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
oc process -v APPLICATION_NAME=nexus -f "${SCRIPT_BASE_DIR}/support/templates/nexus-template.json" | oc -n ${OSE_CI_PROJECT} create -f -

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
oc process -f $SCRIPT_BASE_DIR/support/templates/postgresql-ephemeral.json -v=POSTGRESQL_DATABASE=$POSTGRESQL_DATABASE,POSTGRESQL_USER=$POSTGRESQL_USER,POSTGRESQL_PASSWORD=$POSTGRESQL_PASSWORD  | oc create -n $OSE_CI_PROJECT -f-

wait_for_endpoint_registration "postgresql" "$OSE_CI_PROJECT"

echo
echo "Deploying Gogs Server..."
echo
oc process -f $SCRIPT_BASE_DIR/support/templates/gogs-template.json | oc create -n $OSE_CI_PROJECT -f-

wait_for_endpoint_registration "gogs" "$OSE_CI_PROJECT"

# Determine Running Pod
GOGS_POD=$(oc get pods -n $OSE_CI_PROJECT -l=deploymentconfig=gogs --no-headers | awk '{ print $1 }')

GOGS_ROUTE=$(oc get routes -n $OSE_CI_PROJECT gogs --template='{{ .spec.host }}')

# Sleep before setting up gogs server
sleep 5

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
echo "Setting up wildfly-swarm-s2i repository..."
echo
oc rsync -n $OSE_CI_PROJECT $SCRIPT_BASE_DIR/wildfly-swarm-s2i $GOGS_POD:/tmp/
oc rsh -n $OSE_CI_PROJECT -t $GOGS_POD bash -c "cd /tmp/wildfly-swarm-s2i && git init && git config --global user.email 'gogs@redhat.com' && git config --global user.name 'gogs' && git add . &&  git commit -m 'initial commit'"
curl -H "Content-Type: application/json" -X POST -d '{"clone_addr": "/tmp/wildfly-swarm-s2i","uid": 1,"repo_name": "wildfly-swarm-s2i"}' --user $GOGS_ADMIN_USER:$GOGS_ADMIN_PASSWORD http://$GOGS_ROUTE/api/v1/repos/migrate


echo
echo "Setting up ose-cicd-api repository..."
echo
oc rsync -n $OSE_CI_PROJECT $SCRIPT_BASE_DIR/ose-cicd-api $GOGS_POD:/tmp/
oc rsh -n $OSE_CI_PROJECT -t $GOGS_POD bash -c "cd /tmp/ose-cicd-api && git init && git config --global user.email 'gogs@redhat.com' && git config --global user.name 'gogs' && git add . &&  git commit -m 'initial commit'"
curl -H "Content-Type: application/json" -X POST -d '{"clone_addr": "/tmp/ose-cicd-api","uid": 1,"repo_name": "ose-cicd-api"}' --user $GOGS_ADMIN_USER:$GOGS_ADMIN_PASSWORD http://$GOGS_ROUTE/api/v1/repos/migrate



# Process Jenkins Slave Template
echo
echo "Processing Jenkins Slave Template..."
echo
oc process -v APPLICATION_NAME=jenkins-slave -f "${SCRIPT_BASE_DIR}/support/templates/jenkins-slave-template.json" | oc -n ${OSE_CI_PROJECT} create -f -

echo
echo "Starting Jenkins Slave binary build..."
echo
oc start-build -n ${OSE_CI_PROJECT} jenkins-slave --from-dir="${SCRIPT_BASE_DIR}/infrastructure/jenkins-slave"

wait_for_running_build "jenkins-slave" "${OSE_CI_PROJECT}"

oc build-logs -n ${OSE_CI_PROJECT} -f jenkins-slave-1

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


oc project ${OSE_SWARM_INFRA_PROJECT}


echo
echo "Instantiating the Swarm builder and associated dependencies in the ${OSE_SWARM_INFRA_PROJECT} project..."
echo
oc process -f "$SCRIPT_BASE_DIR/support/templates/swarm-s2i-template.json" | oc -n ${OSE_SWARM_INFRA_PROJECT} create -f-

echo
echo "Importing upstream OpenShift Base Centos 7 Image..."
echo
oc import-image swarm-centos -n ${OSE_SWARM_INFRA_PROJECT}

echo
echo "Waiting for swarm-s2i build to begin..."
echo
wait_for_running_build "swarm-s2i" "${OSE_SWARM_INFRA_PROJECT}"

# Cancel initial build since this is a binary build with no content
echo
echo "Cancelling initial swarm-s2i build..."
echo
oc cancel-build swarm-s2i-1 -n ${OSE_SWARM_INFRA_PROJECT}



oc project ${OSE_SWARM_APP_DEV}

echo
echo "Instantiating the Swarm application and associated dependencies in the ${OSE_SWARM_APP_DEV} project..."
echo
oc process -f "$SCRIPT_BASE_DIR/support/templates/swarm-app-template.json" -v=SWARM_BASE_TAG=1.0 | oc -n ${OSE_SWARM_APP_DEV} create -f-


#TODO: Delete builds as well?

oc project ${OSE_SWARM_APP_PROD}

echo
echo "Instantiating the Swarm application and associated dependencies in the ${OSE_SWARM_APP_PROD} project..."
echo
oc process -f "$SCRIPT_BASE_DIR/support/templates/swarm-app-template.json" | oc create -n ${OSE_SWARM_APP_PROD} -f-

# Delete BuildConfig object as it is not needed in this project
echo
echo "Deleting BuildConfig in the ${OSE_SWARM_APP_PROD} project..."
echo
oc delete bc swarm-app -n ${OSE_SWARM_APP_PROD}

echo
echo "=================================="
echo "Setup Complete!"
echo "=================================="

