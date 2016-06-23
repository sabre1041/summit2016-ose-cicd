package com.redhat.summit16.model;

import java.io.Serializable;

public class Environment implements Serializable {
	
	private String namespace;
	private String name;

	public String getNamespace() {
		return namespace;
	}

	public void setNamespace(String namespace) {
		this.namespace = namespace;
	}

	public String getName() {
		return name;
	}

	public void setName(String name) {
		this.name = name;
	}
	

}
