pipeline {
  agent { label 'k8s-default' }

  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout(true)
  }

  parameters {
    string(name: 'BACKOFFICE_BRANCH', defaultValue: 'main', description: 'Branch for backoffice service')
    string(name: 'BACKOFFICE_BFF_BRANCH', defaultValue: 'main', description: 'Branch for backoffice-bff service')
    string(name: 'CART_BRANCH', defaultValue: 'main', description: 'Branch for cart service')
    string(name: 'CUSTOMER_BRANCH', defaultValue: 'main', description: 'Branch for customer service')
    string(name: 'INVENTORY_BRANCH', defaultValue: 'main', description: 'Branch for inventory service')
    string(name: 'LOCATION_BRANCH', defaultValue: 'main', description: 'Branch for location service')
    string(name: 'MEDIA_BRANCH', defaultValue: 'main', description: 'Branch for media service')
    string(name: 'ORDER_BRANCH', defaultValue: 'main', description: 'Branch for order service')
    string(name: 'PAYMENT_BRANCH', defaultValue: 'main', description: 'Branch for payment service')
    string(name: 'PAYMENT_PAYPAL_BRANCH', defaultValue: 'main', description: 'Branch for payment-paypal service')
    string(name: 'PRODUCT_BRANCH', defaultValue: 'main', description: 'Branch for product service')
    string(name: 'PROMOTION_BRANCH', defaultValue: 'main', description: 'Branch for promotion service')
    string(name: 'RATING_BRANCH', defaultValue: 'main', description: 'Branch for rating service')
    string(name: 'RECOMMENDATION_BRANCH', defaultValue: 'main', description: 'Branch for recommendation service')
    string(name: 'SAMPLEDATA_BRANCH', defaultValue: 'main', description: 'Branch for sampledata service')
    string(name: 'SEARCH_BRANCH', defaultValue: 'main', description: 'Branch for search service')
    string(name: 'STOREFRONT_BRANCH', defaultValue: 'main', description: 'Branch for storefront service')
    string(name: 'STOREFRONT_BFF_BRANCH', defaultValue: 'main', description: 'Branch for storefront-bff service')
    string(name: 'TAX_BRANCH', defaultValue: 'main', description: 'Branch for tax service')
    string(name: 'WEBHOOK_BRANCH', defaultValue: 'main', description: 'Branch for webhook service')
    booleanParam(name: 'DEPLOY_YAS_CONFIGURATION', defaultValue: true, description: 'Deploy or update yas-configuration in target namespace')
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Deploy developer_build') {
      steps {
        withCredentials([
          usernamePassword(
            credentialsId: 'github-credentials',
            usernameVariable: 'GITHUB_USER',
            passwordVariable: 'GITHUB_TOKEN'
          )
        ]) {
          sh '''#!/usr/bin/env bash
set -euo pipefail
chmod +x k8s/deploy/developer-build.sh
export GITHUB_USER
export GITHUB_TOKEN
export DEPLOY_YAS_CONFIGURATION="${DEPLOY_YAS_CONFIGURATION}"
k8s/deploy/developer-build.sh
'''
        }
      }
    }

    stage('Show service URLs') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail
RESULT_FILE="k8s/deploy/developer-build-result.txt"
if [[ -f "$RESULT_FILE" ]]; then
  echo "Service access summary:"
  if command -v column >/dev/null 2>&1; then
    column -t -s '|' "$RESULT_FILE"
  else
    cat "$RESULT_FILE"
  fi
else
  echo "Result file not found: $RESULT_FILE" >&2
  exit 1
fi
'''
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'k8s/deploy/developer-build-result.txt', allowEmptyArchive: true, onlyIfSuccessful: false
    }
  }
}
