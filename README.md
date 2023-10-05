# Puppet Magic Castle

This repo contains the Puppet environment and the classes that are used to define
the roles of the instances in a Magic Castle cluster.

Roles are attributed to instance based on their tags. For each tag, a list of
classes to include is define. This mechanism is explained in section
[magic_castle::site](#magic_castlesite).

The parameters of the classes can be customized by defined values in the hieradata.
The `profile::` sections list the available classes, their role and their parameters.
- [profile::accounts](#profileaccounts)
- [profile::base](#profilebase)

For classes with parameters, a folded **default values** subsection provides the default
value of each parameter as it would be defined in hieradata. For some parameters, the value is
displayed as `ENC[PKCS7,...]`. This corresponds to an encrypted random value generated by
[`bootstrap.sh`](https://github.com/ComputeCanada/puppet-magic_castle/blob/main/bootstrap.sh)
on the Puppet server initial boot. These values are stored in
`/etc/puppetlabs/code/environment/data/bootstrap.yaml` - a file also created on Puppet server
initial boot.

## magic_castle::site

### parameters

| Variable        | Description                                                                            | Type                |
| :-------------- | :------------------------------------------------------------------------------------- | :-----------------  |
| `all`           | List of classes that are included by all instances                                     | Array[String]       |
| `tags`          | Mapping tag-classes - instances that **have** the tag include the classes              | Hash[Array[String]] |
| `enable_chaos`  | Shuffle class inclusion order - used for debugging purposes                            | Boolean             |

<details>
<summary>default values</summary>

```yaml
magic_castle::site::all:
  - profile::base
  - profile::consul
  - profile::users::local
  - profile::sssd::client
  - profile::metrics::node_exporter
  - swap_file
magic_castle::site::tags:
  dtn:
    - profile::globus
    - profile::nfs::client
    - profile::freeipa::client
    - profile::rsyslog::client
  login:
    - profile::fail2ban
    - profile::cvmfs::client
    - profile::slurm::submitter
    - profile::ssh::hostbased_auth::client
    - profile::nfs::client
    - profile::freeipa::client
    - profile::rsyslog::client
  mgmt:
    - mysql::server
    - profile::freeipa::server
    - profile::metrics::server
    - profile::metrics::slurm_exporter
    - profile::rsyslog::server
    - profile::squid::server
    - profile::slurm::controller
    - profile::freeipa::mokey
    - profile::slurm::accounting
    - profile::accounts
    - profile::users::ldap
  node:
    - profile::cvmfs::client
    - profile::gpu
    - profile::jupyterhub::node
    - profile::slurm::node
    - profile::ssh::hostbased_auth::client
    - profile::ssh::hostbased_auth::server
    - profile::metrics::slurm_job_exporter
    - profile::nfs::client
    - profile::freeipa::client
    - profile::rsyslog::client
  nfs:
    - profile::nfs::server
    - profile::cvmfs::alien_cache
  proxy:
    - profile::jupyterhub::hub
    - profile::reverse_proxy
    - profile::freeipa::client
    - profile::rsyslog::client
```
</details>

<details>
<summary>example 1: enabling CephFS client in a complete Magic Castle cluster</summary>

```yaml
magic_castle::site::tags:
  cephfs:
    - profile::ceph::client
```
Require adding `cephfs` tag  in `main.tf` to all instances that should mount the Ceph fileystem.
</details>

<details>
<summary>example 2: barebone Slurm cluster with external LDAP authentication</summary>

```yaml
magic_castle::site::all:
  - profile::base
  - profile::consul
  - profile::sssd::client
  - profile::users::local
  - swap_file

magic_castle::site::tags:
  mgmt:
    - profile::slurm::controller
    - profile::nfs::server
  login:
    - profile::slurm::submitter
    - profile::nfs::client
  node:
    - profile::slurm::node
    - profile::nfs::client
    - profile::gpu
```

</details>

## profile::accounts

This class configures two services to bridge LDAP users, Slurm accounts and users' folders in filesystems. The services are:
- `mkhome`: monitor new uid entries in slapd access logs and create their corresponding /home and optionally /scratch folders.
- `mkproject`: monitor new gid entries in slapd access logs and create their corresponding /project folders and Slurm accounts if it matches the project regex.

### parameters

| Variable        | Description                                                   | Type       |
| :-------------- | :------------------------------------------------------------ | :--------  |
| `project_regex` | Regex identifying FreeIPA groups that require a corresponding Slurm account | String     |
| `skel_archives` | Archives extracted in each FreeIPA user's home when created | Array[Struct[{filename => String[1], source => String[1]}]] |

<details>
<summary>default values</summary>

```yaml
profile::accounts::project_regex: '(ctb\|def\|rpp\|rrg)-[a-z0-9_-]*'
profile::accounts::skel_archives: []
```
</details>

<details>
<summary>example</summary>

```yaml
profile::accounts::project_regex: '(slurm)-[a-z0-9_-]*'
profile::accounts::skel_archives:
  - filename: hss-programing-lab-2022.zip
    source: https://github.com/ComputeCanada/hss-programing-lab-2022/archive/refs/heads/main.zip
  - filename: hss-training-topic-modeling.tar.gz
    source: https://github.com/ComputeCanada/hss-training-topic-modeling/archive/refs/heads/main.tar.gz
```
</details>

### optional dependencies
This class works at its full potential if these classes are also included:
- [`profile::freeipa::server`](#profilefreeipaserver)
- [`profile::nfs::server`](#profilenfsserver)
- [`profile::slurm::base`](#profileslurmbase)

## profile::base

This class install packages, creates files and install services that have yet
justified the creation of a class of their own but are very useful to Magic Castle
cluster operations.

### parameters

| Variable       | Description                                                                            | Type   |
| :------------- | :------------------------------------------------------------------------------------- | :----- |
| `version`      | Current version number of Magic Castle                                                 | String |
| `admin_email`  | Email of the cluster administrator, use to send log and report cluster related issues  | String |

<details>
<summary>default values</summary>

```yaml
profile::base::version: '13.0.0'
profile::base::admin_emain: ~ #undef
```
</details>

<details>
<summary>example</summary>

```yaml
profile::base::version: '13.0.0-rc.2'
profile::base::admin_emain: "you@email.com"
```
</details>

### dependencies

When `profile::base` is included, these classes are included too:
- [`epel`](https://forge.puppet.com/modules/puppet/epel/readme)
- [`selinux`](https://forge.puppet.com/modules/puppet/selinux/readme)
- [`stdlib`](https://forge.puppet.com/modules/puppetlabs/stdlib/readme)
- [`profile::base::azure`](#profilebaseazure) (only when running in Microsoft Azure Cloud)
- [`profile::base::etc_hosts`](#profilebaseetc_hosts)
- [`profile::base::powertools`](#profilebasepowertools)
- `profile::ssh::base`
- `profile::mail::server` (when parameter `admin_email` is defined)

## profile::base::azure

This class ensures Microsoft Azure Linux Guest Agent is not installed as it tends to interfere
with Magic Castle configuration. The class also install Azure udev storage rules that would
normally be provided by the Linux Guest Agent.

### parameters

None

## profile::base::etc_hosts

This class ensures that each instance declared in Magic Castle `main.tf` have an entry
in `/etc/hosts`. The ip addresses, fqdns and short hostnames are taken from the `terraform.instances`
datastructure provided by `/etc/puppetlabs/data/terraform_data.yaml`.

### parameters

None

## profile::base::powertools

This class ensures the DNF Powertools repo is enabled when using EL8. For all other EL versions, this
class does nothing.

### parameters

None

## profile::ceph::client

> [Ceph](https://ceph.io/en/) is a free and open-source software-defined storage platform
that provides object storage, block storage, and file storage built on a common distributed
cluster foundation.
[reference](https://en.wikipedia.org/wiki/Ceph_(software))

This class install Ceph packages, and configure and mount a CephFS share.

### parameters

| Variable                     | Description                                                 | Type          |
| :--------------------------- | :---------------------------------------------------------- | ------------- |
| `share_name`                 | CEPH share name                                             | String        |
| `access_key`                 | CEPH share access key                                       | String        |
| `export_path`                | Path of the share as exported by the monitors               | String        |
| `mon_host`                   | List of CEPH monitor hostnames                              | Array[String] |
| `mount_binds`                | List of CEPH share folders that will bind mounted under `/` | Array[String] |
| `mount_name`                 | Name to give to the CEPH share once mounted under `/mnt`    | String        |
| `binds_fcontext_equivalence` | SELinux file context equivalence for the CEPH share         | String        |

<details>
<summary>default values</summary>

```yaml
profile::ceph::client::mount_binds: []
profile::ceph::client::mount_name: 'cephfs01'
profile::ceph::client::binds_fcontext_equivalence: '/home'
```
</details>

<details>
<summary>example</summary>

```yaml
profile::ceph::client::share_name: "your-project-shared-fs"
profile::ceph::client::access_key: "MTIzNDU2Nzg5cHJvZmlsZTo6Y2VwaDo6Y2xpZW50OjphY2Nlc3Nfa2V5"
profile::ceph::client::export_path: "/volumes/_nogroup/"
profile::ceph::client::mon_host:
  - 192.168.1.3:6789
  - 192.168.2.3:6789
  - 192.168.3.3:6789
profile::ceph::client::mount_binds:
  - home
  - project
  - software
profile::ceph::client::mount_name: 'cephfs'
profile::ceph::client::binds_fcontext_equivalence: '/home'
```
</details>

## profile::consul

> [Consul](https://www.consul.io/) is a service networking platform developed by HashiCorp.
[reference](https://en.wikipedia.org/wiki/Consul_(software))

This class install consul and configure the service. An instance becomes a
[Consul server agent](https://developer.hashicorp.com/consul/docs/architecture#server-agents)
if its local ip address is declared in `profile::consul::servers`. Otherwise, it becomes a
[Consul client agent](https://developer.hashicorp.com/consul/docs/architecture#client-agents).

### parameters

| Variable  | Description                         | Type          |
| :-------- | :---------------------------------- | ------------- |
| `servers` | IP addresses of the consul servers  | Array[String] |

<details>
<summary>default values</summary>

```yaml
profile::consul::servers: "%{alias('terraform.tag_ip.puppet')}"
```
</details>

<details>
<summary>example</summary>

```yaml
profile::consul::servers:
  - 10.0.1.2
  - 10.0.1.3
  - 10.0.1.4
```
</details>

### dependencies

When `profile::consul` is included, these classes are included too:
- [puppet-consul](https://forge.puppet.com/modules/puppet/consul)
- [puppet-consul_template](https://github.com/cmd-ntrf/puppet-consul_template)
- [profile::consul::puppet_watch]()

## profile::consul::puppet_watch

This class configure a consul watch event that when triggered restart the Puppet agent.
It is used mainly by Terraform to restart all Puppet agents across the cluster when
the hieradata source files uploaded by Terraform are updated.

### parameters

None


### dependencies

When `profile::consul::puppet_watch` is included, this class is included too:
- [`epel`](https://forge.puppet.com/modules/puppet/epel/readme)

## profile::cvmfs::client

> The [CernVM File System (CVMFS)](https://cernvm.cern.ch/fs/) provides a scalable, reliable and
low-maintenance software distribution service. It was developed to assist High Energy Physics (HEP)
collaborations to deploy software on the worldwide-distributed computing infrastructure used to run
data processing applications. CernVM-FS is implemented as a POSIX read-only file system in
user space (a FUSE module). Files and directories are hosted on standard web servers and mounted
in the universal namespace `/cvmfs`.
[reference](https://cernvm.cern.ch/fs/)

This class installs CVMFS client and configure repositories. Since CVMFS is providing the scientific
software stack, this class also configures the initial shell profile that user will load on login and
the default set of Lmod modules that will be loaded.

### parameters

| Variable                  | Description                                    | Type        |
| :------------------------ | :--------------------------------------------- | -------------- |
| `quota_limit`             | Instance local cache directory soft quota (MB) | Integer |
| `initial_profile`         | Path to shell script initializing software stack environment variables | String |
| `extra_site_env_vars`     | Map of environment variables that will be exported before sourcing profile shell scripts. | Hash[String, String] |
| `repositories`            | List of CVMFS repositories to mount  | Array[String] |
| `alien_cache_repositories`| List of CVMFS repositories that need an alien cache | Array[String] |
| `lmod_default_modules`    | List of lmod default modules |Array[String] |

<details>
<summary>default values</summary>

```yaml
profile::cvmfs::client::quota_limit: 4096
profile::cvmfs::client::extra_site_env_vars: { }
profile::cvmfs::client::alien_cache_repositories: [ ]
```

#### computecanada software stack

```yaml
profile::cvmfs::client::repositories:
  - cvmfs-config.computecanada.ca
  - soft.computecanada.ca
profile::cvmfs::client::initial_profile: "/cvmfs/soft.computecanada.ca/config/profile/bash.sh"
profile::cvmfs::client::lmod_default_modules:
  - gentoo/2020
  - imkl/2020.1.217
  - gcc/9.3.0
  - openmpi/4.0.3
```

#### eessi software stack

```yaml
profile::cvmfs::client::repositories:
  - pilot.eessi-hpc.org
profile::cvmfs::client::initial_profile: "/cvmfs/pilot.eessi-hpc.org/latest/init/Magic_Castle/bash"
profile::cvmfs::client::lmod_default_modules:
  - GCC
```


</details>

<details>
<summary>example</summary>

```yaml
profile::cvmfs::client::quota_limit: 8192
profile::cvmfs::client::initial_profile: "/cvmfs/soft.computecanada.ca/config/profile/bash.sh"
profile::cvmfs::client::extra_site_env_vars:
  CC_CLUSTER: beluga
profile::cvmfs::client::repositories:
  - atlas.cern.ch
profile::cvmfs::client::alien_cache_repositories:
  - grid.cern.ch
profile::cvmfs::client::lmod_default_modules:
  - gentoo/2020
  - imkl/2020.1.217
  - gcc/9.3.0
  - openmpi/4.0.3
```
</details>

### dependencies

When `profile::cvmfs::client` is included, these classes are included too:
- [profile::consul](#profileconsul)
- [profile::cvmfs::local_user](#profilecvmfslocal_user)

## profile::cvmfs::local_user

This class configures a `cvmfs` local user.
This guarantees a consistent UID and GID for user cvmfs across
the cluster when using CVMFS Alien Cache.

### parameters

| Variable      | Description      | Type    |
| :------------ | :--------------- | :------ |
| `cvmfs_uid`   | cvmfs user id  	 | Integer |
| `cvmfs_gid`   | cvmfs group id   | Integer |
| `cvmfs_group` | cvmfs group name | String  |

<details>
<summary>default values</summary>

```yaml
profile::cvmfs::local_user::cvmfs_uid: 13000004
profile::cvmfs::local_user::cvmfs_gid: 8000131
profile::cvmfs::local_user::cvmfs_group: "cvmfs-reserved"
```
</details>

## profile::cvmfs::alien_cache

This class determines the location of the CVMFS alien cache.

### parameters

| Variable           | Description      | Type    |
| :----------------- | :--------------- | :------ |
| `alien_fs_root`    | Shared file system where the alien cache will be create | String |
| `alien_folder_name`| Alien cache folder name                                 | String |

<details>
<summary>default values</summary>

```yaml
profile::cvmfs::alien_cache::alien_fs_root: "/scratch"
profile::cvmfs::alien_cache::alien_folder_name: "cvmfs_alien_cache"
```
</details>

## profile::fail2ban

> [Fail2ban](https://github.com/fail2ban/fail2ban) is an intrusion prevention software framework.
Written in the Python programming language, it is designed to prevent brute-force attacks.
[reference](https://en.wikipedia.org/wiki/Fail2ban)

This class installs and configures fail2ban.

### parameters

| Variable          | Description      | Type    |
| :---------------- | :--------------- | :------ |
| `ignoreip`        | List of IP addresses that can never be banned (compatible with CIDR notation)  | Array[String]              |
| `service_ensure`  | Enable fail2ban service                                                        | Enum['running', 'stopped'] |

<details>
<summary>default values</summary>

```yaml
profile::fail2ban::ignoreip: []
profile::fail2ban::service_ensure: "running"
```
</details>

<details>
<summary>example</summary>

```yaml
profile::fail2ban::ignoreip:
  - 132.203.0.0/16
  - 10.0.0.0/8
```
</details>

### dependencies

When `profile::fail2ban` is included, these classes are included too:
- [puppet-fail2ban](https://github.com/voxpupuli/puppet-fail2ban)

## profile::freeipa::base

> [FreeIPA](https://www.freeipa.org/) is a free and open source identity management system.
FreeIPA is the upstream open-source project for Red Hat Identity Management.
[reference](https://en.wikipedia.org/wiki/FreeIPA)

This class configures files and services that are common to FreeIPA client and FreeIPA server.

### parameters

| Variable      | Description            | Type    |
| :------------ | :--------------------- | :------ |
| `domain_name` | FreeIPA primary domain | String  |

<details>
<summary>default values</summary>

```yaml
profile::freeipa::base::domain_name: "%{alias('terraform.data.domain_name')}"
```
</details>

## profile::freeipa::client

This class install packages, and configures files and services of a FreeIPA client.

### parameters

| Variable     | Description               | Type    |
| :----------- | :------------------------ | :------ |
| `server_ip`  | FreeIPA server ip address | String  |

<details>
<summary>default values</summary>

By default, the FreeIPA server ip address corresponds to the local ip address of the
first instance with the tag `mgmt`.

```yaml
profile::freeipa::client::server_ip: "%{alias('terraform.tag_ip.mgmt.0')}"
```
</details>

## profile::freeipa::server

This class configures files and services of a FreeIPA server.

### parameters

| Variable         | Description                                 | Type           |
| :--------------  | :------------------------------------------ | :------------- |
| `admin_password` | Password of the FreeIPA admin account       | String         |
| `ds_password`    | Password of the directory server            | String         |
| `hbac_services`  | Name of services to control with HBAC rules | Array[String]  |

<details>
<summary>default values</summary>

```yaml
profile::freeipa::server::admin_password: ENC[PKCS7,...]
profile::freeipa::server::ds_password: ENC[PKCS7,...]
profile::freeipa::server::hbac_services: ["sshd", "jupyterhub-login"]
```

</details>

## profile::freeipa::mokey

> [mokey](https://github.com/ubccr/mokey) is web application that provides self-service
user account management tools for FreeIPA. [reference](https://github.com/ubccr/mokey)

This class installs mokey, configures its files and manage its service.

### parameters

| Variable               | Description                                                    | Type          |
| :--------------------- | :------------------------------------------------------------- | :------------ |
| `password`             | Password of Mokey table in MariaDB                             | String        |
| `port`                 | Mokey internal web server port                                 | Integer       |
| `enable_user_signup`   | Allow users to create an account on the cluster                | Boolean       |
| `require_verify_admin` | Require a FreeIPA to enable Mokey created account before usage | Boolean       |
| `access_tags`          | HBAC rule access tags for users created via mokey self-signup  | Array[String] |

<details>
<summary>default values</summary>

```yaml
profile::freeipa::mokey::password: ENC[PKCS7,...]
profile::freeipa::mokey::port: 12345
profile::freeipa::mokey::enable_user_signup: true
profile::freeipa::mokey::require_verify_admin: true
profile::freeipa::mokey::access_tags: "%{alias('profile::users::ldap::access_tags')}"
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

## profile::jupyterhub::hub

> JupyterHub is a multi-user server for Jupyter Notebooks. It is designed to support many users by
spawning, managing, and proxying many singular Jupyter Notebook servers.
[reference](https://en.wikipedia.org/wiki/Project_Jupyter)

This class installs and configure the _hub_ part of JupyterHub.

### parameters

| Variable       | Description                                                                | Type   |
| :------------- | :------------------------------------------------------------------------- | :----- |
| `register_url` | URL that links to register page. Empty string means no visible link.       | String |
| `reset_pw_url` | URL that links to reset password page. Empty string means no visible link. | String |

<details>
<summary>default values</summary>

```yaml
profile::jupyterhub::hub::register_url: "https://mokey.%{lookup('terraform.data.domain_name')}/auth/signup"
profile::jupyterhub::hub::reset_pw_url: "https://mokey.%{lookup('terraform.data.domain_name')}/auth/forgotpw"
```
</details>

### dependency

When `profile::jupyterhub::hub` is included, this class is included too:
- [jupyterhub](https://github.com/computecanada/puppet-jupyterhub)

## profile::jupyterhub::node

This class installs and configure the _single-user notebook_ part of JupyterHub.

### parameters

None

### dependency

When `profile::jupyterhub::node` is included, these classes are included too:
- [jupyterhub::node](https://github.com/computecanada/puppet-jupyterhub)
- [jupyterhub::kernel::venv](https://github.com/computecanada/puppet-jupyterhub)

## profile::nfs::client

> Network File System (NFS) is a distributed file system protocol [...]
allowing a user on a client computer to access files over a computer
network much like local storage is accessed.
[reference](https://en.wikipedia.org/wiki/Network_File_System)

This class install NFS and configure the client to mount all shares exported
by a single NFS server identified via its ip address.

### parameters

| Variable      | Description                  | Type    |
| ------------- | :--------------------------- | :------ |
| `server_ip`   | IP address of the NFS server | String  |

<details>
<summary>default values</summary>

```yaml
profile::nfs::client::server_ip: "%{alias('terraform.tag_ip.nfs.0')}"
```
</details>

### dependency

When `profile::nfs::client` is included, these classes are included too:
- [nfs](https://forge.puppet.com/modules/derdanne/nfs/readme) (`client_enabled => true`)

## profile::nfs::server

This class install NFS and configure an NFS server that will export all provided devices.
The class also make sure that devices sharing a common export name form an LVM volume group
that is exported as a single LVM logical volume formated as XFS.

If a volume's size associated with an NFS server device is expanded after the initial configuration,
the class will not expand the LVM volume automatically. These operations currently have to be
accomplished manually.

### parameters

| Variable  | Description                                      | Type                          |
| :-------- | :----------------------------------------------- | :---------------------------- |
| `devices` | Mapping between NFS share and devices to export. | Hash[String, Array[String]]   |


<details>
<summary>default values</summary>

```yaml
profile::nfs::server::devices: "%{alias('terraform.volumes.nfs')}"
```
</details>

<details>
<summary>example</summary>

```yaml
profile::nfs::server::devices:
  home:
    - /dev/disk/by-id/b0b686f6-62c8-11ee-8c99-0242ac120002
    - /dev/disk/by-id/b65acc52-62c8-11ee-8c99-0242ac120002
  scratch:
    - bfd50252-62c8-11ee-8c99-0242ac120002
  project:
    - c3b99e00-62c8-11ee-8c99-0242ac120002
```
</details>

### dependency

When `profile::nfs::server` is included, these classes are included too:
- [nfs](https://forge.puppet.com/modules/derdanne/nfs/readme) (`server_enabled => true`)

## profile::reverse_proxy

> [Caddy](https://caddyserver.com/) is an extensible, cross-platform, open-source web
server written in Go. [...] It is best known for its automatic HTTPS features.
[reference](https://en.wikipedia.org/wiki/Caddy_(web_server))

This class installs and configure Caddy as a reverse proxy to expose Magic Castle cluster
internal services to the Internet.

### parameters

| Variable         | Description                                                                          | Type                        |
| :--------------- | :---------------------------------------------------------------------------------   | :-------------------------- |
| `domain_name`    | Domain name corresponding to the main DNS record A registered                        | String                      |
| `main2sub_redir` | Subdomain to redirect to when hitting domain name directly. Empty means no redirect. | String                      |
| `subdomains`     | Subdomain names used to create vhosts to internal http endpoints                     | Hash[String, String]        |
| `remote_ips`     | List of allowed ip addresses per subdomain. Undef mean no restrictions.              | Hash[String, Array[String]] |

<details>
<summary>default values</summary>

```yaml
profile::reverse_proxy::domain_name: "%{alias('terraform.data.domain_name')}"
profile::reverse_proxy::subdomains:
  ipa: "ipa.int.%{lookup('terraform.data.domain_name')}"
  mokey: "%{lookup('terraform.tag_ip.mgmt.0')}:%{lookup('profile::freeipa::mokey::port')}"
  jupyter: "https://127.0.0.1:8000"
profile::reverse_proxy::main2sub_redit: "jupyter"
profile::reverse_proxy::remote_ips: {}
```
</details>

<details>
<summary>example</summary>

```yaml
profile::reverse_proxy::remote_ips:
  ipa:
    - 132.203.0.0/16
```
</details>

## profile::rsyslog::base

> [Rsyslog](https://www.rsyslog.com/) is an open-source software utility
used on UNIX and Unix-like computer systems for forwarding log messages
in an IP network.
[reference](https://en.wikipedia.org/wiki/Rsyslog)

This class installs rsyslog and launch the service.

## profile::rsyslog::client

This class install and configures rsyslog service to forward the instance's
logs to rsyslog servers. The rsyslog servers are discovered by the instance
via Consul.

### parameters

None

### dependencies

When `profile::rsyslog::client` is included, these classes are included too:
- [profile::consul](#profileconsul)
- [profile::rsyslog::base](#profilersyslogbase)

## profile::rsyslog::server

This class install and configures rsyslog service to receives forwarded logs
from all rsyslog client in the cluster.

### parameters

None

### dependencies

When `profile::rsyslog::server` is included, these classes are included too:
- [profile::consul](#profileconsul)
- [profile::rsyslog::base](#profilersyslogbase)

## profile::slurm::base

> The [Slurm](https://github.com/schedmd/slurm) Workload Manager, formerly
known as Simple Linux Utility for Resource Management, or simply Slurm,
is a free and open-source job scheduler for Linux and Unix-like kernels,
used by many of the world's supercomputers and computer clusters.
[reference](https://en.wikipedia.org/wiki/Slurm_Workload_Manager)

> [MUNGE](https://github.com/dun/munge) (MUNGE Uid 'N' Gid Emporium) is
an authentication service for creating and validating credentials. It is
designed to be highly scalable for use in an HPC cluster environment.
[reference](https://dun.github.io/munge/)

This class installs base packages and config files that are essential
to all Slurm's roles. It also installs and configure Munge service.

### parameters

| Variable                | Description              | Type    |
| :---------------------- | :----------------------- | :------ |
| `cluster_name`          | Name of the cluster      | String  |
| `munge_key`             | Base64 encoded Munge key | String  |
| `slurm_version`         | Slurm version to install | Enum[20.11, 21.08, 22.05, 23.02] |
| `os_reserved_memory`    | Memory in MB reserved for the operating system on the compute nodes | Integer |
| `suspend_time`          | Idle time (seconds) for nodes to becomes eligible for suspension. | Integer |
| `resume_timeout`        | Maximum time permitted (seconds) between a node resume request and its availability. | Integer |
| `force_slurm_in_path`   | Enable Slurm's bin path in all users (local and LDAP) PATH environment variable | Boolean |
| `enable_x11_forwarding` | Enable Slurm's built-in X11 forwarding capabilities | Boolean |

<details>
<summary>default values</summary>

```yaml
profile::slurm::base::cluster_name: "%{alias('terraform.data.cluster_name')}"
profile::slurm::base::munge_key: ENC[PKCS7, ...]
profile::slurm::base::slurm_version: '21.08'
profile::slurm::base::os_reserved_memory: 512
profile::slurm::base::suspend_time: 3600
profile::slurm::base::resume_timeout: 3600
profile::slurm::base::force_slurm_in_path: false
profile::slurm::base::enable_x11_forwarding: true
```
</details>

### dependencies

When `profile::slurm::base` is included, these classes are included too:
- [`epel`](https://forge.puppet.com/modules/puppet/epel/readme)
- [`profile::consul`](#profileconsul)
- [`profile::base::powertools`](#profilebasepowertools)


## profile::slurm::accounting

This class installs and configure the Slurm database daemon - **slurmdbd**.
This class also installs and configures MariaDB for slurmdbd to store its
tables.

### parameters

| Variable   | Description                                         | Type    |
| :-------   | :-------------------------------------------------  | :------ |
| `password` | Password used by for SlurmDBD to connect to MariaDB | String  |
| `admins`   | List of Slurm administrator usernames               | Array[String] |
| `accounts` | Define Slurm account name and [specifications](https://slurm.schedmd.com/sacctmgr.html#SECTION_GENERAL-SPECIFICATIONS-FOR-ASSOCIATION-BASED-ENTITIES) | Hash[String, Hash] |
| `users`    | Define association between usernames and accounts    | Hash[String, Array[String]] |
| `options`  | Define additional cluster's global [Slurm accounting options](https://slurm.schedmd.com/sacctmgr.html#SECTION_GENERAL-SPECIFICATIONS-FOR-ASSOCIATION-BASED-ENTITIES) | Hash[String, Any] |
| `dbd_port` | SlurmDBD service listening port | Integer |

<details>
<summary>default values</summary>

```yaml
profile::slurm::accounting::password: ENC[PKCS7, ...]
profile::slurm::accounting::admin: ["centos"]
profile::slurm::accounting::accounts: {}
profile::slurm::accounting::users: {}
profile::slurm::accounting::options: {}
profile::slurm::accounting::dbd_port: 6869
```
</details>

<details>
<summary>example</summary>

Example of the definition of Slurm accounts and their association with users:
```yaml
profile::slurm::accounting::admins: ['oppenheimer']

profile::slurm::accounting::accounts:
  physics:
    Fairshare: 1
    MaxJobs: 100
  engineering:
    Fairshare: 2
    MaxJobs: 200
  humanities:
    Fairshare: 1
    MaxJobs: 300

profile::slurm::accounting::users:
  oppenheimer: ['physics']
  rutherford: ['physics', 'engineering']
  sartre: ['humanities']
```

Each username in `profile::slurm::accounting::users` and `profile::slurm::accounting::admins` have to correspond
to an LDAP or a local users. Refer to [profile::users::ldap::users](#profileusersldapusers) and
[profile::users::local::users](#profileuserslocalusers) for more information.

</details>

### dependencies

When `profile::slurm::accounting` is included, these classes are included too:
- [`logrotate::rule`](https://forge.puppet.com/modules/puppet/logrotate/readme)
- [`mysql::server`](https://forge.puppet.com/modules/puppetlabs/mysql/readme)
- [`profile::slurm::base`](#profileslurmbase)

## profile::slurm::controller

This class installs and configure the Slurm controller daemon - **slurmctld**.

### parameters

| Variable            | Description                                                    | Type   |
| :------------------ | :------------------------------------------------------------  | :----- |
| `autoscale_version` | Version of Slurm Terraform cloud autoscale software to install | String |
| `tfe_token`         | Terraform Cloud API Token. Required to enable autoscaling.     | String |
| `tfe_workspace`     | Terraform Cloud workspace id. Required to enable autoscaling.  | String |
| `tfe_var_pool`      | Variable name in Terraform Cloud workspace to control autoscaling pool | String |
| `selinux_context`   | SELinux context for jobs (Slurm > 20.11) | String |

<details>
<summary>default values</summary>

```yaml
profile::slurm::controller::autoscale_version: "0.4.0"
profile::slurm::controller::selinux_context: "user_u:user_r:user_t:s0"
profile::slurm::controller::tfe_token: ""
profile::slurm::controller::tfe_workspace: ""
profile::slurm::controller::tfe_var_pool: "pool"
```
</details>

<details>
<summary>example</summary>

```yaml
profile::slurm::controller::tfe_token: "7bf4bd10-1b62-4389-8cf0-28321fcb9df8"
profile::slurm::controller::tfe_workspace: "ws-jE6Lq2hggNPyRJcJ"
```

For more information on how to configure Slurm autoscaling with Terraform cloud,
refer to the [Terraform Cloud](https://github.com/ComputeCanada/magic_castle/blob/main/docs/terraform_cloud.md) section of Magic Castle manual.

</details>

### dependencies

When `profile::slurm::accounting` is included, these classes are included too:
- [`logrotate::rule`](https://forge.puppet.com/modules/puppet/logrotate/readme)
- [`profile::slurm::base`](#profileslurmbase)
- [`profile::mail::server`](#profilemailserver)

## profile::squid::server

> Squid is a caching and forwarding HTTP web proxy. It has a wide variety
of uses, including speeding up a web server by caching repeated requests
[reference](https://en.wikipedia.org/wiki/Squid_(software))

This class configures and installs the Squid service. Its main usage is to
act as an HTTP cache for CVMFS clients in the cluster.

### parameters

| Variable          | Description                               | Type          |
| :---------------- | :---------------------------------------- | :------------ |
| `port`            | Squid service listening port              | Integer       |
| `cache_size`      | Amount of disk space (MB)                 | Integer       |
| `cvmfs_acl_regex` | List of allowed CVMFS stratums as regexes | Array[String] |


<details>
<summary>default values</summary>

```yaml
profile::squid::server::port: 3128
profile::squid::server::cache_size: 4096
```

#### computecanada software stack
```yaml
profile::squid::server::cvmfs_acl_regex:
  - '^(cvmfs-.*\.computecanada\.ca)$'
  - '^(cvmfs-.*\.computecanada\.net)$'
  - '^(.*-cvmfs\.openhtc\.io)$'
  - '^(cvmfs-.*\.genap\.ca)$'
```

#### eessi software stack
```yaml
profile::squid::server::cvmfs_acl_regex:
  - '^(.*\.cvmfs\.eessi-infra\.org)$'
```
</details>

### dependencies

When `profile::squid::server` is included, these classes are included too:
- [`squid`](https://forge.puppet.com/modules/puppet/squid/readme)
- [`profle::consul`](#profileconsul)

## profile::sssd::client

> The System Security Services Daemon is software originally developed
for the Linux operating system that provides a set of daemons to manage
access to remote directory services and authentication mechanisms.
[reference](https://en.wikipedia.org/wiki/System_Security_Services_Daemon)

This class configures external authentication domains

### parameters

| Variable      | Description                                                       | Type  |
| :------------ | :---------------------------------------------------------------- | :---- |
| `domains`     | Config dictionary of domains that can authenticate                | Hash[String, Any]  |
| `access_tags` | List of host tags that domain user can connect to                 | Array[String] |
| `deny_access` | Deny access to the domains on the host including this class, if undef, the access is defined by tags. | Optional[Boolean] |

<details>
<summary>default values</summary>

```yaml
profile::sssd::client::domains: { }
profile::sssd::client::access_tags: ['login', 'node']
profile::sssd::client::deny_access: ~
```
</details>

<details>
<summary>example</summary>

```yaml
profile::sssd::client::domains:
  MyOrgLDAP:
    id_provider: ldap
    auth_provider: ldap
    ldap_schema: rfc2307
    ldap_uri:
      - ldaps://server01.ldap.myorg.net
      - ldaps://server02.ldap.myorg.net
      - ldaps://server03.ldap.myorg.net
    ldap_search_base: ou=People,dc=myorg,dc=net
    ldap_group_search_base: ou=Group,dc=myorg,dc=net
    ldap_id_use_start_tls: False
    cache_credentials: true
    ldap_tls_reqcert: never
    access_provider: ldap
    filter_groups: 'cvmfs-reserved'
```

The domain's keys in this example are on an indicative basis and may not be mandatory.
Some SSSD domain keys might also be missing. Refer to
[domain sections in sssd.conf manual](https://man.archlinux.org/man/sssd.conf.5.en#DOMAIN_SECTIONS)
for more informations.
</details>

## profile::users

| Variable                              | Type           | Description                                                                 | Default  |
| ------------------------------------- | :------------- | :-------------------------------------------------------------------------- | -------- |
| `profile::users::ldap::users` | Hash[Hash] | Dictionary of users to be created in LDAP | |
| `profile::users::ldap::access_tags` | Array[String] | List of string of the form `'tag:service'` that LDAP user can connect to  | `['login:sshd', 'node:sshd', 'proxy:jupyterhub-login']` |
| `profile::users::local::users` | Hash[Hash] | Dictionary of users to be created locally | |

<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

### profile::users::ldap::users

A batch of 10 LDAP users, user01 to user10, can be defined in hieradata as:
```yaml
profile::users::ldap::users:
  user:
    count: 10
    passwd: user.password.is.easy.to.remember
    groups: ['def-sponsor00']
```

A single LDAP user can be defined as:
```yaml
profile::users::ldap::users:
  alice:
    passwd: user.password.is.easy.to.remember
    groups: ['def-sponsor00']
    public_keys: ['ssh-rsa ... user@local', 'ssh-ecdsa ...']
```

By default, Puppet will manage the LDAP user(s) password and change it in ldap if it no
longer corresponds to what is prescribed in the hieradata. To disable this feature, add
`manage_password: false` to the user(s) definition.

### profile::users::local::users

A local user `bob` can be defined in hieradata as:
```yaml
profile::users::local::users:
  bob:
    groups: ['group1', 'group2']
    public_keys: ['ssh-rsa...', 'ssh-dsa']
    # sudoer: false
    # selinux_user: 'unconfined_u'
    # mls_range: ''s0-s0:c0.c1023'
```
