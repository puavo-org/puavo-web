pipeline {
  agent {
    docker {
      image 'debian:stretch'
      // XXX could you do most operations as normal user?
      args '-u root'
    }
  }

  stages {
    stage('Prepare') {
      steps {
        sh '''
          apt-get update
          apt-get -y dist-upgrade
          apt-get install -y devscripts dpkg-dev make
          make install-build-deps
        '''
      }
    }

    stage('Build') {
      steps {
        sh 'make deb'
      }
    }

    stage('Test') {
      steps {
        sh 'make test'
        sh 'make test-rest'
        cucumber fileIncludePattern: 'logs/cucumber-tests-*.json',
                 sortingMethod: 'ALPHABETICAL'
      }
    }

    stage('Upload') {
      steps {
        withCredentials([file(credentialsId: 'dput.cf',
                              variable: 'DPUT_CONFIG_FILE')]) {
          sh 'install -o root -g root -m 644 "$DPUT_CONFIG_FILE" /etc/dput.cf'
        }
        withCredentials([file(credentialsId: 'ssh_known_hosts',
                              variable: 'SSH_KNOWN_HOSTS')]) {
          sh '''
            mkdir -m 700 -p ~/.ssh
            cp -p "$SSH_KNOWN_HOSTS" ~/.ssh/known_hosts
          '''
        }
        withCredentials([sshUserPrivateKey(credentialsId: 'puavo-deb-upload',
                                           keyFileVariable: 'ID_RSA',
                                           passphraseVariable: '',
                                           usernameVariable: '')]) {
          sh 'cp -p "$ID_RSA" ~/.ssh/id_rsa'
          sh 'make upload-deb'
        }
      }
    }
  }
}
