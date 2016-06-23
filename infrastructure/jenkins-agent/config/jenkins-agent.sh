#!/bin/bash

export USER_ID=$(id -u)
export GROUP_ID=$(id -g)
envsubst < ${HOME}/passwd.template > ${HOME}/passwd
export LD_PRELOAD=libnss_wrapper.so
export NSS_WRAPPER_PASSWD=${HOME}/passwd
export NSS_WRAPPER_GROUP=/etc/group

JAR="/opt/jenkins-agent/bin/agent.jar"


# if -url is not provided try env vars
if [[ "$@" != *"-url "* ]]; then
  if [ ! -z "$JENKINS_URL" ]; then
    PARAMS="$PARAMS -url $JENKINS_URL"
  elif [ ! -z "$JENKINS_SERVICE_HOST" ] && [ ! -z "$JENKINS_SERVICE_PORT" ]; then
    PARAMS="$PARAMS -url http://$JENKINS_SERVICE_HOST:$JENKINS_SERVICE_PORT"
  fi
fi

echo "Downloading ${JENKINS_URL}/jnlpJars/remoting.jar ..."
curl ${JENKINS_URL}/jnlpJars/remoting.jar -o ${JAR}

# if -tunnel is not provided try env vars
if [[ "$@" != *"-tunnel "* ]]; then
  if [ ! -z "$JENKINS_TUNNEL" ]; then
    PARAMS="$PARAMS -tunnel $JENKINS_TUNNEL"
  elif [ ! -z "$JENKINS_AGENT_SERVICE_HOST" ] && [ ! -z "$JENKINS_AGENT_SERVICE_PORT" ]; then
    PARAMS="$PARAMS -tunnel $JENKINS_AGENT_SERVICE_HOST:$JENKINS_AGENT_SERVICE_PORT"
  fi
fi

exec java $JAVA_OPTS \
    -cp $JAR hudson.remoting.jnlp.Main -headless $PARAMS -jar-cache $HOME "$@"

exec "$@"
