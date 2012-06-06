# VMware Serengeti Ironfan

This is a fork of Ironfan project (created by Infochimps) to enable Ironfan work with VMware vSphere 5.0.

This fork of Ironfan (VMware Serengeti Ironfan) is part of VMware Serengeti Open Source project, it will be called by VMware Serengeti Server component. However, this Ironfan fork can also work standalone, please read section 'Create a vSphere cluster'.

## Major changes in VMware Serengeti Ironfan

* Refactor Ironfan code architecture to support multi cloud providers gracefully.
* Add full support for vSphere Cloud (i.e. create and manage VMs in VMware vCenter server).
* Add monitor function to Ironfan to enable Ironfan report progress of cluster operation and bootstrap to a RabbitMQ server.
* Provide a set of cookbooks for deploying a hadoop cluster in a vSphere Cloud.

## Support for Multi Cloud Providers

### vSphere Cloud

vSphere Cloud Provider uses a RubyGem cloud-manager (created by VMware Serengeti project) instead of RubyGem Fog (used by EC2 Cloud Provider) to talk to vSphere vCenter server.
RubyGem cloud-manager provides the function for IaaS like cluster management, and it uses an enhanced RubyGem Fog (created by VMware Serengeti project) to talk to vSphere vCenter server.

#### Knife commands for manage a vSphere cluster

You can use the following Ironfan Knife commands to manage a vSphere cluster:
* knife cluster create ... --bootstrap
* knife cluster launch ... --bootstrap
* knife cluster bootstrap ...
* knife cluster show ...
* knife cluster stop ...
* knife cluster start ... --bootstrap
* knife cluster delete ...

One outstanding change to all these commands (only when executed on a vSphere cluster) requires an additional param '-f /path/to/cluster_definition.json'.
This param specifies a json file containing the cluster definition and RabbitMQ server configuration (used by Ironfan), and configuration for connecting to vCenter (used by cloud-manager).
Take spec/data/cluster_definition.json as an example of the cluster defintion file.

#### Create a vSphere cluster

Assume you've setup a Hosted Chef Server or Open Source Chef Server and have a configured .chef/knife.rb .
1. Copy spec/data/cluster_definition.json to ~/hadoopcluster.json
2. Open ~/hadoopdemo_cluster.json, modify the cluster definition and vCenter connection configuration
3. Append "knife[:monitor_disabled] = true" to .chef/knife.rb to disable the Ironfan monitor function.
4. Execute cluster create command:  knife cluster create hadoopcluster -f ~/hadoopcluster.json --yes --bootstrap
5. After the cluster is created, you can use other Knife commands to manage it.

### EC2 Cloud

Original Infochimps Ironfan mainly supports EC2 cloud. This fork of Ironfan still provide support for EC2 cloud the same as the Infochimps Ironfan does. The only change is we must specify the cloud provider in cluster definition file, e.g. in ironfan-homebase/clusters/hadoopdemo.rb, change "Ironfan.cluster 'hadoopdemo' do" to "Ironfan.cluster :ec2, 'hadoopdemo' do" .

Please be noted that we have been focusing on vSphere support, and haven't done full test for the EC2 support.

### Support more Cloud Providers

Each cloud provider has a seperate folder to contain the necessary model classes: Cloud, Cluster, Facet, Server, ServerSlice.
For example, cloud provider for vSphere has a folder (lib/ironfan/vsphere) which contains 5 files, and each file defines a model class for vSphere cloud.
If you want to add a new cloud provider, create a folder and the model classes for it, override necessary methods defined in the base model classes. Please take vSphere cloud provider as an example when writing new cloud provider.

# Original Ironfan Created by Infochimps

Thanks very much to the original open source Ironfan project created by Infochimps (https://github.com/infochimps-labs/ironfan)
