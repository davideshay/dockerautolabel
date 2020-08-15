# dockerautolabel
Docker Auto Labelling tool for swarm engine clusters

## Docker/Github Build Status

![Docker Pulls](https://img.shields.io/docker/pulls/davideshay/dockerautolabel?style=for-the-badge)
![GitHub Workflow Status](https://img.shields.io/github/workflow/status/davideshay/dockerautolabel/BuildDockerImage?style=for-the-badge)
![Docker Image Size (latest by date)](https://img.shields.io/docker/image-size/davideshay/dockerautolabel?style=for-the-badge)

## What it Does
This container, intended to be run on a docker swarm cluster as a service (must be run on a manager node), automatically creates/updates node labels and keeps them in sync with where services are running. For instance, if I am running a "virtual IP" keepalived service called "clusterip", most nodes in the cluster will have a label "running_clusterip=0", but the node where the clusterip service is running will have the label set to 1 "running_clusterip=1".

## Purpose
The primary purpose of this is to to create the concept of "service affinity" via labels. It is otherwise quite difficult to indicate that two specific services should be run on the same physical node.  There are many reasons why you might need to co-locate services, especially if some are running in some type of network host mode, or many other reasons.  In my case, I wanted to have a traefik service running, but co-located with the clusterip service.  Via this script, the "running_clusterip" node is set to 1 only on the node where the clusterIP service is running, and is 0 everywhere else.  You can then use a service placement constraint that is a label dependency, i.e. "node.label.running_clusterip=1" on the traefik service. This then creates the desired behavior. If the clusterip service for any reason stops and restarts on another node, the traefik service will then detect that it's constraint has changed, and will relocate nodes along with the clusterip service as appropriate, and automatically without intervention.

## Usage
To use the service, simply create a comma-separated file "servicelist.txt" which contains two values - value of the service name to watch for, and the name of the label that will be automatically set to 0/1 based on where the service is running.  For instance:
```bash
cluster_clusterip,running_clusterip
```
Remember in this file that the service name should be prefixed with the stack name if you are using "docker stack deploy" to deploy your swarm services.

## Deploying 

This servicelist.txt file should be bind-mounted to /config/servicelist.txt in some manner (either direct file or /config directory).
In addition /var/run/docker.sock should be bind-mounted as well, and this service must be run on a swarm manager node. The included docker-compose file accounts for all of this:

```docker
version: "3.7"
services:
    dockerautolabel:
        build: .
        image: davideshay/dockerautolabel:1
        volumes:
           - /data/docker/config/dockerautolabel:/config
           - /var/run/docker.sock:/var/run/docker.sock
        networks:
           - proxy-net
        deploy:
            placement:
               constraints:
                  - node.role==manager

networks:
    proxy-net:
          external: true
```          
