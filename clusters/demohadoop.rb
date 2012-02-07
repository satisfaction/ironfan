ClusterChef.cluster 'demohadoop' do
  setup_role_implications
  # mounts_ephemeral_volumes

  cloud :vsphere do
    backing "instance"   # "ebs"
    #image_name "oneiric"
    image_name "maverick"
    availability_zones  ['us-east-1a']
  end

  #role "big_package"
  #role "nfs_client"

  cluster_role # add specific role for this cluster

  facet :master do
    instances 1
    cloud.flavor "m1.small" # "m2.xlarge"
    
    facet_role # add specific role for this facet

    role "hadoop"
    role "hadoop_namenode"
    role "hadoop_jobtracker"
    role "hadoop_datanode"
    role "hadoop_tasktracker"
  end

  facet :worker do
    instances 2
    cloud.flavor "m1.small" # "m1.large"

    facet_role

    role "hadoop"
    role "hadoop_worker"
  end

  chef_attributes({
    :cluster_size => facet('worker').instances,
    :hadoop => {
      :dfs_replication => facet('worker').instances,
    }
  })
end

