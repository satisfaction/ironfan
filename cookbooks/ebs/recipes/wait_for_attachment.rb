if cluster_ebs_volumes
  cluster_ebs_volumes.each do |conf|
    bash "Wait for ebs volumes to attach" do

      code <<EOF
  echo #{conf.to_hash.inspect}:
  while true ; do
    sleep 2
    echo -n "$i "
    i=$[$i+1]
    test -c #{conf[:device]} || continue
    echo "#{conf[:device]} mounted for #{conf.to_hash.inspect}" >> /tmp/wait_for_attachment_err.log
    break;
  done
  true
EOF
    end

  end

end