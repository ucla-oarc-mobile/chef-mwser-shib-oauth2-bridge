#
# Cookbook Name:: mwser-shib-oauth2-bridge
# Recipe:: default
#
# Copyright (C) 2016 UC Regents
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# require chef-vault
chef_gem 'chef-vault'
require 'chef-vault'

# additional packages/repos needed.
yum_repository 'remi' do
  description 'Les RPM de Remi - Repository'
  mirrorlist 'http://rpms.famillecollet.com/enterprise/6/remi/mirror'
  gpgkey 'http://rpms.famillecollet.com/RPM-GPG-KEY-remi'
  action :create
end

yum_repository 'remi-php55' do
  description 'Les RPM de Remi PHP55 - Repository'
  mirrorlist 'http://rpms.famillecollet.com/enterprise/6/php55/mirror'
  gpgkey 'http://rpms.famillecollet.com/RPM-GPG-KEY-remi'
  action :create
end

%w(git php php-mcrypt php-mysql php-mbstring).each do |pkg|
  package pkg
end

# shib config
include_recipe 'shib-oauth2-bridge::shibd'
include_recipe 'shib-oauth2-bridge::shib-ds'

fqdn = node['fqdn'] # quick variable accessor

# db config
db_root_obj = ChefVault::Item.load("passwords", "db_root")
db_root = db_root_obj[fqdn]
mysql_connection = {
  :host => '127.0.0.1',
  :port => 3306,
  :username => 'root',
  :password => db_root
}

db_bridge_obj = ChefVault::Item.load('passwords', 'bridge')
db_bridge = db_bridge_obj[fqdn]

mysql_database 'bridge' do
  connection mysql_connection
  action :create
end
mysql_database_user 'bridge' do
  connection mysql_connection
  password db_bridge
  database_name 'bridge'
  action [:create,:grant]
end

# shib keys
sp_ssl = ChefVault::Item.load('shibboleth', fqdn) # gets ssl cert from chef-vault
file '/etc/shibboleth/sp-cert.pem' do
  owner 'shibd'
  group 'shibd'
  mode '0777'
  content sp_ssl['cert']
  notifies :reload, 'service[shibd]', :delayed
end
file '/etc/shibboleth/sp-key.pem' do
  owner 'shibd'
  group 'shibd'
  mode '0600'
  content sp_ssl['key']
  notifies :reload, 'service[shibd]', :delayed
end

# shib bridge setup
bridge_secrets = ChefVault::Item.load('secrets', 'oauth2')

case fqdn
when 'ucnext.org'
  shib_oauth2_bridge 'default' do
    db_user 'bridge'
    db_name 'bridge'
    hostname 'ucnext.org'
    db_password db_bridge
    clients [
      { id: 'next', name: 'next', secret: bridge_secrets['next'], redirect_uri: 'https://ucnext.org/auth/oauth2/shibboleth' },
      { id: 'staging_next', name: 'staging_next', secret: bridge_secrets['staging_next'], redirect_uri: 'https://staging.ucnext.org/auth/oauth2/shibboleth' }
    ]
  end
when 'onlinepoll.ucla.edu'
  shib_oauth2_bridge 'default' do
    db_user 'bridge'
    db_name 'bridge'
    hostname 'onlinepoll.ucla.edu'
    db_password db_bridge
    clients [
      { id: 'opt', name: 'opt', secret: bridge_secrets['opt'], redirect_uri: 'https://onlinepoll.ucla.edu/auth/oauth2/shibboleth/launch' },
      { id: 'staging_opt', name: 'staging_opt', secret: bridge_secrets['staging_opt'], redirect_uri: 'https://staging.onlinepoll.ucla.edu/auth/oauth2/shibboleth/launch' },
      { id: 'casa', name: 'casa', secret: bridge_secrets['casa'], redirect_uri: 'https://casa.m.ucla.edu/session/oauth2/shibboleth' },
      { id: 'staging_casa', name: 'staging_casa', secret: bridge_secrets['staging_casa'], redirect_uri: 'https://casa-staging.m.ucla.edu/session/oauth2/shibboleth' }

    ]
  end
end
