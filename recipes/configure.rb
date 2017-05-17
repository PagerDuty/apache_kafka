# encoding: UTF-8
# Cookbook Name:: apache_kafka
# Recipe:: configure
#

[
  node["apache_kafka"]["config_dir"],
  node["apache_kafka"]["bin_dir"],
  node["apache_kafka"]["data_dir"],
  node["apache_kafka"]["log_dir"]
].each do |dir|
  directory dir do
    recursive true
    owner node["apache_kafka"]["user"]
  end
end

do_restart = node['apache_kafka']['restart_on_change']

%w{ kafka-server-start.sh kafka-run-class.sh kafka-topics.sh }.each do |bin|
  template ::File.join(node["apache_kafka"]["bin_dir"], bin) do
    source "bin/#{bin}.erb"
    owner "kafka"
    action :create
    mode "0755"
    variables(
      :config_dir => node["apache_kafka"]["config_dir"],
      :bin_dir => node["apache_kafka"]["bin_dir"]
    )
    notifies :restart, "service[kafka]", :delayed if do_restart
  end
end

broker_id = node["apache_kafka"]["broker.id"]
broker_id = 0 if broker_id.nil?

zookeeper_connect = node["apache_kafka"]["zookeeper.connect"]
zookeeper_connect = "localhost:2181" if zookeeper_connect.nil?

# read keystore_pass from vault if pd_generate_certs is true
keystore_pass = nil
if node["apache_kafka"]["ssl"]["pd_generate_certs"]
  vault_app_id = node["apache_kafka"]["ssl"]["vault_app_id"]
  begin
    node.pd_helper.with_vault_availability(vault_app_id) do |vault_client|
      keystore_pass = vault_client.read("secret/#{vault_app_id}/keystore", "password")
    end
  rescue PagerDuty::V2::VaultAuthError => e
    Chef::Log.warn("Unable to authenticate with Vault: #{e.message}")
  end
end

template ::File.join(node["apache_kafka"]["config_dir"],
                     node["apache_kafka"]["conf"]["server"]["file"]) do
  source "properties/server.properties.erb"
  owner "kafka"
  action :create
  mode "0644"
  variables(
    :broker_id => broker_id,
    :port => node["apache_kafka"]["port"],
    :zookeeper_connect => zookeeper_connect,
    :log_dirs => node["apache_kafka"]["data_dir"],
    :entries => node["apache_kafka"]["conf"]["server"]["entries"],
    :keystore_pass => keystore_pass
  )
  notifies :restart, "service[kafka]", :delayed if do_restart
  sensitive true
end

template ::File.join(node["apache_kafka"]["config_dir"],
                     node["apache_kafka"]["conf"]["log4j"]["file"]) do
  source "properties/log4j.properties.erb"
  owner "kafka"
  action :create
  mode "0644"
  variables(
    :log_dir => node["apache_kafka"]["log_dir"],
    :entries => node["apache_kafka"]["conf"]["log4j"]["entries"]
  )
  notifies :restart, "service[kafka]", :delayed if do_restart
end
