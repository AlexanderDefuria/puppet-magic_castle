node default {
  include profile::consul::client
  include profile::base
  include profile::rsyslog::client
  include profile::freeipa::client
  include profile::metrics::exporter
}

node /^login\d+$/ {
  include profile::consul::client
  include profile::base
  include profile::metrics::exporter
  include profile::fail2ban
  include profile::cvmfs::client
  include profile::rsyslog::client
  include profile::slurm::submitter
  include profile::globus::base
  include profile::singularity
  include jupyterhub
  include profile::nfs::client
  include profile::freeipa::client
}

node /^mgmt01$/ {
  include profile::consul::server
  include profile::metrics::server
  include profile::metrics::exporter
  include profile::rsyslog::server
  include profile::freeipa::server
  include profile::squid::server
  include profile::nfs::server
  include profile::slurm::controller

  include profile::base
  include profile::freeipa::guest_accounts
  include profile::slurm::accounting
}

node /^mgmt0*(?:[2-9]|[1-9]\d\d*)$/ {
  include profile::consul::client
  include profile::base
  include profile::rsyslog::client
  include profile::freeipa::client
  include profile::metrics::exporter
}

node /^node\d+$/ {
  include profile::consul::client
  include profile::base
  include profile::metrics::exporter
  include profile::rsyslog::client
  include profile::cvmfs::client
  include profile::gpu
  include profile::singularity
  include jupyterhub::node

  include profile::nfs::client
  include profile::slurm::node
  include profile::freeipa::client
}
