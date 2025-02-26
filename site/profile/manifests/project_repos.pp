class profile::project_repos {
  $users = lookup('profile::users::ldap::users', Hash, 'deep', {})
  $repos = lookup('profile::project_repos', Hash, 'deep', {})

  $users.each |$username, $user_data| {
    $repo_url = $repos['custom_repos'][$username] ? {
      undef   => $repos['default_repo'],
      default => $repos['custom_repos'][$username]
    }

    file { "/project/${username}/repo":
      ensure => directory,
      owner  => $username,
      group  => $user_data['groups'][0],
      mode   => '0750',
    }

    vcsrepo { "/project/${username}/repo":
      ensure    => latest,
      provider  => git,
      source    => $repo_url,
      user      => $username,
      require   => File["/project/${username}/repo"],
      before    => Exec["set_project_permissions_${username}"],
    }

    exec { "set_project_permissions_${username}":
      command     => "/bin/chmod -R g+rX /project/${username}",
      refreshonly => true,
    }
  }
}
