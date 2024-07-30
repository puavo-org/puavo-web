pipeline {
  agent {
    dockerfile {
      filename 'Dockerfile'

      // XXX could you do most operations as normal user?
      args '-u root --mount type=bind,source=/etc/jenkins-docker-config,destination=/etc/jenkins-docker-config,readonly --env-file=/etc/jenkins-docker-config/environment --privileged --tmpfs /run --tmpfs /run/lock --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw'
    }
  }

  stages {
    stage('Fix repository permissions') {
      steps { sh 'chown -R root:root .' }
    }

    stage('Enable service startup') {
      steps {
        // Debian Docker container contains a policy to not start services
        // when packages are installed, but we want that to work, so remove
        // the 'exit 101' policy when starting services.
        sh 'ln -fns /bin/true /usr/sbin/policy-rc.d'
      }
    }

    stage('Prepare') {
      steps {
        sh '''
          apt-get update
          apt-get -y dist-upgrade
          apt-get install -y devscripts dpkg-dev locales make rsync wget

          # setup en_US.UTF-8 locale (needed by Ansible)
          echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
          locale-gen
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

          // must wait a while before puavo-rest is ready (?!?)
          // ("PUAVO_WEB_CUCUMBER_TESTS"-environment variable not effective otherwise)
          sh 'sleep 5'

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
