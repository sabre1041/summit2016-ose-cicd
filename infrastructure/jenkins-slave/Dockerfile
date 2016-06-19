FROM centos:7

MAINTAINER Andrew Block <andy.block@gmail.com>

ENV HOME /opt/jenkins-slave
ENV JNLP_SLAVE_VERSION 2.60
ENV MAVEN_VERSION 3.3.9
ENV JAVA_HOME /usr/lib/jvm/java

RUN yum clean all && \ 
    export INSTALL_PKGS="nss_wrapper java-1.8.0-openjdk-devel java-1.8.0-openjdk-headless gettext tar git which origin-clients unzip" && \
    yum -y --setopt=tsflags=nodocs install epel-release centos-release-openshift-origin && \
    yum install -y --setopt=tsflags=nodocs install $INSTALL_PKGS && \
    rpm -V $INSTALL_PKGS && \
    yum clean all && \
    useradd -u 1001 -r -m -d ${HOME} -s /sbin/nologin -c "Jenkins Slave" jenkins-slave && \
    mkdir -p /opt/jenkins-slave/bin /var/lib/jenkins && \
    chown -R 1001:0 /var/lib/jenkins && \
    curl -fsSL http://archive.apache.org/dist/maven/maven-3/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz | tar xzf - -C /usr/share \
      && mv /usr/share/apache-maven-$MAVEN_VERSION /usr/share/maven \
      && ln -s /usr/share/maven/bin/mvn /usr/bin/mvn

# Copy script
COPY config/jenkins-slave.sh config/settings.xml config/passwd.template /opt/jenkins-slave/

# Download JNLP Client, move configurations/scripts and modify permissions
RUN mv /opt/jenkins-slave/jenkins-slave.sh /opt/jenkins-slave/bin && \
  mv /opt/jenkins-slave/settings.xml /usr/share/maven/conf/settings.xml && \
  chown -R 1001:0 /opt/jenkins-slave /opt/jenkins-slave/bin

WORKDIR /var/lib/jenkins

VOLUME /var/lib/jenkins

USER 1001

ENTRYPOINT ["/opt/jenkins-slave/bin/jenkins-slave.sh"]