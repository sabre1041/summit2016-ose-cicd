package com.redhat.summit16.rest;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.List;

import javax.ws.rs.DELETE;
import javax.ws.rs.GET;
import javax.ws.rs.Path;
import javax.ws.rs.PathParam;
import javax.ws.rs.Produces;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.redhat.summit16.model.Environment;

import io.fabric8.kubernetes.api.model.Pod;
import io.fabric8.openshift.api.model.DeploymentConfig;
import io.fabric8.openshift.client.DefaultOpenShiftClient;
import io.fabric8.openshift.client.OpenShiftClient;

@Path("/api")
public class OpenShiftEndpoint {
		
	private static final String TEST_MODE_PROP = "OSE_CICD_TEST_MODE";
	private static final String SWARM_POD_NAME_PROP = "SWARM_POD_NAME";
	private static final String SWARM_POD_NAMESPACE_PROP = "SWARM_POD_NAMESPACE";
	
	private static String podNamespace;
	private static String podName;
	
	private static OpenShiftClient client;
	
	private static final Logger LOGGER = LoggerFactory.getLogger(OpenShiftEndpoint.class);
	

  @GET
  @Path("environment")
  @Produces(MediaType.APPLICATION_JSON)
  public Environment getEnvironment() {
	  Environment env = new Environment();
	  env.setNamespace(getPodNamespace());
	  env.setName(getPodName());
	  return env;
  }
  
  @GET
  @Path("pods")
  @Produces(MediaType.APPLICATION_JSON)
  public List<Pod> getPods() {
	  
//	  List<Pod> pods = new ArrayList<Pod>();
	  
	  String deploymentLabel = getClient().pods().inNamespace(getPodNamespace()).withName(getPodName()).get().getMetadata().getLabels().get("deployment");
	  
	  List<Pod> osePods = getClient().pods().inNamespace(getPodNamespace()).withLabel("deployment", deploymentLabel).list().getItems();
	  return osePods;
//	  for(io.fabric8.kubernetes.api.model.Pod osePod : osePods) {
//		  Pod pod = new Pod();
//		  pod.setName(osePod.getMetadata().getName());
//		  pod.setCreateTimestamp(osePod.getMetadata().getCreationTimestamp());
//	  }
	  
	 // return pods;
  }
  
  @GET
  @Path("scale/{replicas}")
  @Produces(MediaType.APPLICATION_JSON)
  public DeploymentConfig scale(@PathParam("replicas") Integer replicas) {
	  
	  String deploymentConfigName = getClient().pods().inNamespace(getPodNamespace()).withName(getPodName()).get().getMetadata().getAnnotations().get("openshift.io/deployment-config.name");
	  
	  DeploymentConfig dc = getClient().deploymentConfigs().inNamespace(getPodNamespace()).withName(deploymentConfigName).edit().editSpec().withReplicas(replicas).endSpec().done();
	 	  
	  return dc;
	  
  }
  
  
  
  @DELETE
  @Path("pod/name/{name}")
  public Response deletePod(@PathParam("name") String name) {
	  
	  // Get Pod
	  Pod pod = getClient().pods().inNamespace(getPodNamespace()).withName(name).get();
	  
	  getClient().pods().inNamespace(getPodNamespace()).delete(pod);
	  
	  return Response.ok().build();
	  
  }
  
  

  
  private OpenShiftClient getClient() {
	  
	  if(client != null) {
		  return client;
	  }
	  
	  io.fabric8.kubernetes.client.Config config = new io.fabric8.kubernetes.client.Config();
	  
	  // Testing Mode
	  if(System.getenv(TEST_MODE_PROP) != null){
		  
		  config.setMasterUrl("https://10.1.2.2:8443");
		  config.setCaCertFile("../local-testing/ca.crt");
		  java.nio.file.Path tokenFile = Paths.get("../local-testing/token");

	      String token = null;
	      try {
	    	  token = new String(Files.readAllBytes(tokenFile));
			  config.setOauthToken(token);
	      } catch (IOException e) {
			LOGGER.error(e.getMessage(), e);
	      }
		  
	  }
	   	  
	  client = new DefaultOpenShiftClient(config);
	  
	  return client;
	  
  }
  
  private String getPodName() {
	  
	  if(podName == null) {
		  podName = System.getenv(SWARM_POD_NAME_PROP);
	  }
	  
	  return podName;
	  
  }
  
  private String getPodNamespace() {
	  if(podNamespace == null) {
		  podNamespace = System.getenv(SWARM_POD_NAMESPACE_PROP);
	  }
	  
	  return podNamespace;
  }
  
  
  
}