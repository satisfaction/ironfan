Ironfan.cluster :vsphere, "hadoopcluster" do

  cloud :vsphere do
    image_name "centos5"
    flavor "default"
  end

  facet :master do
    instances 1
    
    role "hadoop_namenode"
    role "hadoop_jobtracker"
  end
  
  facet :worker do
    instances 3
    
    role "hadoop_datanode"
    role "hadoop_tasktracker"
  end
  
  facet :client do
    instances 1
    
    role "hadoop_client"
    role "hive"
    role "pig"
  end


  hadoop_distro "apache"

  cluster_role.override_attributes({
    :hadoop => {
      :distro_name => "apache"
    }
  })
end
