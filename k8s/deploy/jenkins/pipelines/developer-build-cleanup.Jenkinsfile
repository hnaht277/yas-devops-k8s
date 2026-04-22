pipeline {
  agent { label 'k8s-default' }

  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout(true)
  }

  parameters {
    booleanParam(name: 'REMOVE_YAS_CONFIGURATION', defaultValue: false, description: 'Also remove yas-configuration release in yas-dev namespace')
    booleanParam(name: 'DELETE_NAMESPACE', defaultValue: false, description: 'Delete target namespace after uninstalling releases')
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Cleanup developer_build') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail
chmod +x k8s/deploy/cleanup-developer-build.sh
export REMOVE_YAS_CONFIGURATION="${REMOVE_YAS_CONFIGURATION}"
export DELETE_NAMESPACE="${DELETE_NAMESPACE}"
k8s/deploy/cleanup-developer-build.sh
'''
      }
    }
  }
}
