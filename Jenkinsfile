pipeline {
  agent {
    dockerfile {
      filename 'Dockerfile'

      // XXX could you do most operations as normal user?
      args '-u root --mount type=bind,source=/etc/jenkins-docker-config,destination=/etc/jenkins-docker-config,readonly --env-file=/etc/jenkins-docker-config/environment --cap-add=SYS_ADMIN --tmpfs /run --tmpfs /run/lock -v /sys/fs/cgroup:/sys/fs/cgroup:ro'
    }
  }

  stages {
    stage('Setup APT repositories') {
      steps {
        // Debian Docker container contains a policy to not start services
        // when packages are installed, but we want that to work, so remove
        // the 'exit 101' policy when starting services.
        sh 'ln -fns /bin/true /usr/sbin/policy-rc.d'

        // "nodejs" in Stretch does not have "npm", must install the upstream
        // deb-packages. ("npm" in a build-dependency for puavo-users)
        // XXX Perhaps this should be done by puavo-standalone?
        sh '''
          cat <<'EOF' > /etc/apt/sources.list.d/nodesource.list
deb http://deb.nodesource.com/node_14.x buster main
deb-src http://deb.nodesource.com/node_14.x buster main
EOF
        '''

        // Apt key for nodesource.
        sh '''
          base64 -d <<'EOF' > /etc/apt/trusted.gpg.d/nodesource.gpg
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
EOF
        '''
      }
    }

    stage('Prepare') {
      steps {
        sh '''
          apt-get update
          apt-get -y dist-upgrade
          apt-get install -y devscripts dpkg-dev make rsync wget
        '''
      }
    }

    stage('Prepare the puavo-standalone environment') {
      // XXX Why does the build need this environment to work?
      // XXX (This should only be necessary for testing puavo-users etc.)
      steps {
        // Setup puavo-standalone.  Use the wget-to-shell mechanism, because,
        // even though installing "ansible"- and "puavo-standalone"-packages
        // and running "ansible-playbook -i /etc/puavo-standalone/local.inventory /etc/puavo-standalone/standalone.yml"
        // should work, we probably want to test that this works as well:
        sh '''
          wget -qO - https://github.com/puavo-org/puavo-standalone/raw/master/setup.sh | sh
        '''
      }
    }

    stage('Install deb-package build dependencies') {
      steps {
        sh 'make install-build-deps'
      }
    }

    stage('Build') {
      steps { sh 'make deb' }
    }

    stage('Test') {
      steps {
        wrap([$class: 'AnsiColorBuildWrapper', 'colorMapName': 'xterm']) {
          // Setup puavo-rest in production mode to do tests for puavo-web
          sh '''
            mkdir -p /etc/systemd/system/puavo-rest.service.d
            cat <<'EOF' > /etc/systemd/system/puavo-rest.service.d/cucumber_test_environment.conf
[Service]
Environment="PUAVO_WEB_CUCUMBER_TESTS=true"
EOF
          '''

          // make the above trick effective
          sh 'systemctl daemon-reload'

          // Test installation can be done and works
          // (as a side-effect restarts puavo-rest and puavo-web).
          sh 'script/test-install.sh'

          // Force organisations refresh...
          sh '''
            curl --noproxy localhost -d foo=bar \
              http://localhost:9292/v3/refresh_organisations
          '''

          // Execute rest tests first as they are more low level
          sh '''
            make test-rest
            make test
          '''
        }

        cucumber fileIncludePattern: 'logs/cucumber-tests-*.json',
                 sortingMethod: 'ALPHABETICAL'
      }
    }

    stage('Upload') {
      steps {
        sh '''
          install -o root -g root -m 644 /etc/jenkins-docker-config/dput.cf \
            /etc/dput.cf
          install -o root -g root -m 644 \
            /etc/jenkins-docker-config/ssh_known_hosts \
            /etc/ssh/ssh_known_hosts
          install -d -o root -g root -m 700 ~/.ssh
          install -o root -g root -m 600 \
            /etc/jenkins-docker-config/sshkey_puavo_deb_upload \
            ~/.ssh/id_rsa
        '''

        sh 'make upload-debs'
      }
    }
  }
}
