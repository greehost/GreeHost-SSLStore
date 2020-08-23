# GreeHost SSLStore

## Description

Register & Renew Let's Encrypt SSL Certificates

This program should be run from a dedicated machine and access should be restricted to processes requesting SSL Certificates,

## Limitations

This currently only works with Let's Encrypt + Linode DNS

## Installation

This document assumes you have a CentOS 7 machine freshly provisioned, with root access.

```bash
# Install Docker & Docker Compose
yum install -y yum-utils epel-release; yum update -y
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce docker-compose
systemctl start docker; systemctl enable docker

# Make Saner Perl & Install GreeHost::SSLStore
yum install -y perl-core perl-IPC-Run3 perl-App-cpanminus
cpanm GreeHost-SSLStore-0.001.tar.gz
```

## Usage

### Adding a domain

Once installed, add a domain name with the `greehost-sslstore` command:

```bash
greehost-sslstore add --name example.com --domain '*.example.com' --domain '*.prd.example.com' --key <linode_dns_api_key>
```

### Arguments

| Setting  | Description                                                                                   |
|----------|-----------------------------------------------------------------------------------------------|
| --name   | The root of the domain name, like example.com                                                 |
| --domain | Any other domain names to have this key work on, for example api.example.com or *.example.com |
| --key    | Linode API Key for DNS-01 Challenges                                                          |


### Updating SSL Certificates

Run `greehost-sslstore renew`

This command should be run from cron on a regular basis.


### Listing Domains

Run `greehost-sslstore list`
