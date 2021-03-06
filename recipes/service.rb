# encoding: UTF-8
# Cookbook Name:: apache_kafka
# Recipe:: service
#
# based on the work by Simple Finance Technology Corp.
# https://github.com/SimpleFinance/chef-zookeeper/blob/master/recipes/service.rb
#
# Copyright 2013, Simple Finance Technology Corp.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

version_tag = "kafka_#{node['apache_kafka']['scala_version']}-#{node['apache_kafka']['version']}"
do_restart = node['apache_kafka']['restart_on_change']
enable_service_filename = ::File.join(node['apache_kafka']['config_dir'], 'chef-enable-service')
enable_service = ::File.exist?(enable_service_filename)

template "/etc/default/kafka" do
  source "kafka_env.erb"
  owner "kafka"
  action :create
  mode "0644"
  variables(
    :kafka_home => ::File.join(node["apache_kafka"]["install_dir"], version_tag),
    :kafka_config => node["apache_kafka"]["config_dir"],
    :kafka_bin => node["apache_kafka"]["bin_dir"],
    :kafka_user => node["apache_kafka"]["user"],
    :scala_version => node["apache_kafka"]["scala_version"],
    :kafka_heap_opts => node["apache_kafka"]["kafka_heap_opts"],
    :kafka_jvm_performance_opts => node["apache_kafka"]["kafka_jvm_performance_opts"],
    :kafka_opts => node["apache_kafka"]["kafka_opts"],
    :jmx_port => node["apache_kafka"]["jmx"]["port"],
    :jmx_opts => node["apache_kafka"]["jmx"]["opts"],
    :java_home => node["apache_kafka"]["java_home"]
  )
  notifies :restart, "service[kafka]", :delayed if do_restart
end

if enable_service
  case node["apache_kafka"]["service_style"]
  when "systemd"
    template "/etc/systemd/system/kafka.service" do
      source "kafka.service.erb"
      owner "root"
      group "root"
      action :create
      mode "0644"
      variables(
        :kafka_bin_dir => node['apache_kafka']['bin_dir'],
        :kafka_config_dir => node['apache_kafka']['config_dir']
      )
    end
    service "kafka" do
      supports :status => true, :restart => true, :reload => true
      action [:start, :enable]
    end
  when "upstart"
    template "/etc/init/kafka.conf" do
      source "kafka.init.erb"
      owner "root"
      group "root"
      action :create
      mode "0644"
      variables(
        :kafka_umask => sprintf("%#03o", node["apache_kafka"]["umask"]),
        :pd_generate_certs => node["apache_kafka"]["ssl"]["pd_generate_certs"],
        :kafka_bin_dir => node['apache_kafka']['bin_dir']
      )
      notifies :restart, "service[kafka]", :delayed if do_restart
    end
    service "kafka" do
      provider Chef::Provider::Service::Upstart
      supports :status => true, :restart => true, :reload => true
      action [:start, :enable]
    end
  when "init.d"
    if enable_service
      template "/etc/init.d/kafka" do
        source "kafka.initd.erb"
        owner "root"
        group "root"
        action :create
        mode "0744"
        notifies :restart, "service[kafka]", :delayed if do_restart
      end
      service "kafka" do
        provider Chef::Provider::Service::Init
        supports :status => true, :restart => true, :reload => true
        action [:start]
      end
    end
  when "runit"
    include_recipe "runit"

    runit_service "kafka" do
      default_logger true
      action [:enable, :start]
    end
  else
    Chef::Log.error("You specified an invalid service style for Kafka, but I am continuing.")
  end
else
  Chef::Log.info("Kafka service was not enabled because #{enable_service_filename} does not exist. Create it manually when ready.")
end
