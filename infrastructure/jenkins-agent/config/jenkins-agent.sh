#!/bin/bash

# Set current user in nss_wrapper
USER_ID=$(id -u)
GROUP_ID=$(id -g)

if [ x"$USER_ID" != x"0" -a x"$USER_ID" != x"1001" ]; then

    NSS_WRAPPER_PASSWD=/tmp/nss_passwd
    NSS_WRAPPER_GROUP=/etc/group

    cat /etc/passwd | sed -e 's/^default:/builder:/' > $NSS_WRAPPER_PASSWD

    echo "default:x:${USER_ID}:${GROUP_ID}:Default Application User:${HOME}:/sbin/nologin" >> $NSS_WRAPPER_PASSWD

    export NSS_WRAPPER_PASSWD
    export NSS_WRAPPER_GROUP
    export LD_PRELOAD=libnss_wrapper.so
fi

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
