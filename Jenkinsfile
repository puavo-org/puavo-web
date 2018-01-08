pipeline {
  agent {
    docker {
      image 'debian:stretch'
      // XXX could you do most operations as normal user?
      args '-u root --mount type=bind,source=/etc/jenkins-docker-config,destination=/etc/jenkins-docker-config,readonly --env-file=/etc/jenkins-docker-config/environment'
    }
  }

  stages {
    stage('Prepare') {
      steps {
        sh '''
          apt-get update
          apt-get -y dist-upgrade
          apt-get install -y devscripts dpkg-dev make
        '''
      }
    }

    stage('Install deb-package build dependencies') {
      steps { sh 'make install-build-deps' }
    }

    stage('Build') {
      steps { sh 'make deb' }
    }

    stage('Test') {
      steps {
        // Install puavo-client and puavo-standalone dependencies.
        sh '''
          cat <<'EOF' > /etc/apt/sources.list.d/puavo.list
deb http://archive.opinsys.fi/puavo stretch main contrib non-free
deb-src http://archive.opinsys.fi/puavo stretch main contrib non-free
EOF
           apt-get install -y ansible puavo-client puavo-standalone
           ansible-playbook -i /etc/puavo-standalone/local.inventory /etc/puavo-standalone/standalone.yml
        '''

        // Test installation can be done and works.
        sh 'script/test-install.sh'

        // Force organisations refresh...
        sh 'curl -d foo=bar http://localhost:9292/v3/refresh_organisations'

        // Execute rest tests first as they are more low level
        sh 'make test-rest'
        sh 'make test'

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
