pipeline {
  agent {
    docker {
      image 'debian:stretch'
      // XXX could you do most operations as normal user?
      args '-u root --mount type=bind,source=/etc/jenkins-docker-config,destination=/etc/jenkins-docker-config,readonly --env-file=/etc/jenkins-docker-config/environment'
    }
  }

  stages {
    stage('Setup APT repositories') {
      steps {
        sh '''
          # XXX s/archive-internal.opinsys.fi/archive.opinsys.fi/ !!!
          cat <<'EOF' > /etc/apt/sources.list.d/puavo.list
deb http://archive-internal.opinsys.fi/puavo stretch main
deb-src http://archive-internal.opinsys.fi/puavo stretch main
EOF
        '''

        // Apt key for Puavo.
        sh '''
          base64 -d <<'EOF' > /etc/apt/trusted.gpg.d/puavo.gpg
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
/Ifxkpv5n2nSa6IeiNAUAFiwAgAD
EOF
        '''

        // "nodejs" in Stretch does not have "npm", must install the upstream
        // deb-packages. ("npm" in a build-dependency for puavo-users)
        sh '''
          cat <<'EOF' > /etc/apt/sources.list.d/nodesource.list
deb http://deb.nodesource.com/node_4.x stretch main
deb-src http://deb.nodesource.com/node_4.x stretch main
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
          apt-get install -y devscripts dpkg-dev make wget
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
          wget -qO - https://github.com/opinsys/puavo-standalone/raw/master/setup.sh | sh
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
