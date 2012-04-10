current_dir   = File.expand_path('~/.chef')
organization  = 'infochimps'
username      = 'mrflip'

cookbook_root = ENV['PATH_TO_COOKBOOK_REPOS'] || File.expand_path('../../ironfan-homebase', File.dirname(__FILE__))

ironfan_path       File.expand_path(cookbook_root + '/../ironfan')
keypair_path       File.expand_path(current_dir + "/keypairs")

cookbook_path    [
  "cookbooks", "vendor/vmware/cookbooks"
  ].map{|path| File.join(cookbook_root, path) }

cluster_path     [
  "spec/data/clusters",
  ].map{|path| File.join(ironfan_path, path) }

node_name                username
validation_client_name   "chef-validator"
validation_key           "#{keypair_path}/#{organization}-validator.pem"
client_key               "#{keypair_path}/#{username}-client_key.pem"
chef_server_url          "https://api.opscode.com/organizations/#{organization}"
