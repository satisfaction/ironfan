# Ironfan Core: Knife Tools and Core Models

Ironfan, the foundation of The Infochimps Platform, is an expressive toolset for constructing scalable, resilient architectures. It works in the cloud, in the data center, and on your laptop, and it makes your system diagram visible and inevitable. Inevitable systems coordinate automatically to interconnect, removing the hassle of manual configuration of connection points (and the associated danger of human error).
For more information about Ironfan and the Infochimps Platform, visit [infochimps.com](http://www.infochimps.com/).

This repo implements:

* Core models to describe your system diagram with a clean, expressive domain-specific language
* Knife plugins to orchestrate clusters of machines using simple commands like `knife cluster launch`
* Logic to coordinate truth among chef server and cloud providers

## Getting Started

To jump right into using Ironfan, follow our [Installation Instructions](https://github.com/infochimps-labs/ironfan/wiki/INSTALL). For an explanatory tour, check out our [Web Walkthrough](https://github.com/infochimps-labs/ironfan/wiki/walkthrough-web).  Please file all issues on [Ironfan issues](https://github.com/infochimps-labs/ironfan/issues).

### Tools

Ironfan consists of the following Toolset:

* [ironfan-homebase](https://github.com/infochimps-labs/ironfan-homebase): centralizes the cookbooks, roles and clusters. A solid foundation for any chef user.
* [ironfan gem](https://github.com/infochimps-labs/ironfan):
  - core models to describe your system diagram with a clean, expressive domain-specific language
  - knife plugins to orchestrate clusters of machines using simple commands like `knife cluster launch`
  - logic to coordinate truth among chef server and cloud providers.
* [ironfan-pantry](https://github.com/infochimps-labs/ironfan-pantry): Our collection of industrial-strength, cloud-ready recipes for Hadoop, HBase, Cassandra, Elasticsearch, Zabbix and more.
* [silverware cookbook](https://github.com/infochimps-labs/ironfan-homebase/tree/master/cookbooks/silverware): coordinate discovery of services ("list all the machines for `awesome_webapp`, that I might load balance them") and aspects ("list all components that write logs, that I might logrotate them, or that I might monitor the free space on their volumes".

### Documentation

* [Index of wiki pages](https://github.com/infochimps-labs/ironfan/wiki/_pages)
* [Ironfan wiki](https://github.com/infochimps-labs/ironfan/wiki): high-level documentation
* [Ironfan issues](https://github.com/infochimps-labs/ironfan/issues): bugs, questions and feature requests for *any* part of the ironfan toolset.
* [Ironfan gem docs](http://rdoc.info/gems/ironfan): rdoc docs for Ironfan
* [Ironfan Screencast](http://bit.ly/ironfan-hadoop-in-20-minutes) -- build a Hadoop cluster from scratch in 20 minutes.
* Ironfan powers the [Infochimps Platform](http://www.infochimps.com/how-it-works), our scalable enterprise big data platform. Ironfan Enterprise adds zero-configuration logging, monitoring and a compelling UI.

**Note**: Ironfan is [not compatible with Ruby 1.8](https://github.com/infochimps-labs/ironfan/issues/127). All versions later than 1.9.2-p136 should work fine.

### The Ironfan Way

* [Core Concepts](https://github.com/infochimps-labs/ironfan/wiki/core_concepts)     -- Components, Announcements, Amenities and more.
* [Philosophy](https://github.com/infochimps-labs/ironfan/wiki/Philosophy)            -- Best practices and lessons learned
* [Style Guide](https://github.com/infochimps-labs/ironfan/wiki/style_guide)         -- Common attribute names, how and when to include other cookbooks, and more
* [Homebase Layout](https://github.com/infochimps-labs/ironfan/wiki/homebase-layout) -- How this homebase is organized, and why


## Support for Multi Cloud Providers

Currently VMware Serengeti Ironfan supports two kinds of cloud providers: vSphere and EC2.

### vSphere Cloud

vSphere Cloud Provider uses a RubyGem cloud-manager (created by VMware Serengeti project) instead of RubyGem Fog (used by EC2 Cloud Provider) to talk to vSphere vCenter server.
RubyGem cloud-manager provides the function for IaaS like cluster management, and it uses an enhanced RubyGem Fog (created by VMware Serengeti project) to talk to vSphere vCenter server.

### EC2 Cloud

Original Infochimps Ironfan mainly supports EC2 cloud. This fork of Ironfan still provide support for EC2 cloud the same as the Infochimps Ironfan does. The only change is we must specify the cloud provider in cluster definition file, e.g. in ironfan-homebase/clusters/hadoopdemo.rb, change "Ironfan.cluster 'hadoopdemo' do" to "Ironfan.cluster :ec2, 'hadoopdemo' do" .

Please be noted that we have been focusing on vSphere support, and haven't done full test for the EC2 support.

### vSphere
One outstanding change to all these commands (only when executed on a vSphere cluster) requires an additional param '-f /path/to/cluster_definition.json'.
This param specifies a json file containing the cluster definition and RabbitMQ server configuration (used by Ironfan), and configuration for connecting to vCenter (used by cloud-manager).
Take spec/data/cluster_definition.json as an example of the cluster defintion file.

#### Create a vSphere cluster

Assume you've setup a Hosted Chef Server or Open Source Chef Server and have a configured .chef/knife.rb .
<pre>
1. Copy spec/data/cluster_definition.json to ~/hadoopcluster.json
2. Open ~/hadoopcluster.json, modify the cluster definition:
     change "name", "template_id", "distro_map", "port_group" in section "cluster_definition",
     change vCenter connection configuration in section "cloud_provider", and
     don't need to change section "system_properties".
3. Append "knife[:monitor_disabled] = true" to .chef/knife.rb to disable the Ironfan monitor function.
4. Execute cluster create command:  knife cluster create hadoopcluster -f ~/hadoopcluster.json --yes --bootstrap [-V]
   This command will create VMs in vCenter for this Hadoop cluster and install specified Hadoop packages on the VMs.
5. After the cluster is created successfully, navigate to http://ip_of_hadoopcluster-master-0:50070/ to see the status of the Hadoop cluster.
6. Then, you can use other Knife commands to manage the cluster (e.g. show, bootstrap, stop, start, kill etc.).
</pre>

#### Contact VMware for vSphere support

Please send email to our mailing lists for [developers](https://groups.google.com/group/serengeti-dev) or for [users](https://groups.google.com/group/serengeti-user) if you have any questions.

### Support more Cloud Providers

Each cloud provider has a seperate folder to contain the necessary model classes: Cloud, Cluster, Facet, Server, ServerSlice.
For example, cloud provider for vSphere has a folder (lib/ironfan/vsphere) which contains 5 files, and each file defines a model class for vSphere cloud.
If you want to add a new cloud provider, create a folder and the model classes for it, override necessary methods defined in the base model classes. Please take vSphere cloud provider as an example when writing new cloud provider.


## Getting Help
* Feel free to contact us at info@infochimps.com or 855-DATA-FUN
* Also, you invited to a [private consultation](http://www.infochimps.com/free-big-data-consultation?utm_source=git&utm_medium=referral&utm_campaign=consult) with Infochimps founders on your big data project.