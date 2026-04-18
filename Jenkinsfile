pipeline {
  agent { label 'kaniko' }

  parameters {
    booleanParam(
      name: 'FORCE_ALL_SERVICES',
      defaultValue: false,
      description: 'Build and push images for all services regardless of code changes'
    )
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout(true)
  }

  environment {
    REGISTRY = 'docker.io'
    DOCKERHUB_NAMESPACE = 'hnaht277'
    IMAGE_PREFIX = 'yas'
    CHANGED_SERVICES = ''
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Detect Changed Services') {
      steps {
        script {
          def serviceListOutput = sh(
            script: "find . -maxdepth 2 -name Dockerfile -printf '%h\\n' | sed 's#^\\./##' | sort -u",
            returnStdout: true
          ).trim()

          if (!serviceListOutput) {
            error('No services with Dockerfile were found at repository root level.')
          }

          def services = serviceListOutput.split('\n') as List
          echo "Detected services: ${services.join(', ')}"

          def baseCommit = env.GIT_PREVIOUS_SUCCESSFUL_COMMIT?.trim()
          if (!baseCommit) {
            def hasHeadParent = sh(script: 'git rev-parse --verify HEAD~1 >/dev/null 2>&1', returnStatus: true) == 0
            baseCommit = hasHeadParent ? 'HEAD~1' : ''
          }

          def diffCmd = baseCommit
            ? "git diff --name-only ${baseCommit}..HEAD"
            : 'git ls-tree -r --name-only HEAD'

          def changedFilesOutput = sh(script: diffCmd, returnStdout: true).trim()
          def changedFiles = changedFilesOutput ? changedFilesOutput.split('\n') : []

          def selected = [] as Set
          if (params.FORCE_ALL_SERVICES) {
            selected.addAll(services)
            echo 'FORCE_ALL_SERVICES=true: building all services.'
          } else {
            changedFiles.each { filePath ->
              def topDir = filePath.tokenize('/')[0]
              if (services.contains(topDir)) {
                selected.add(topDir)
              }
            }
          }

          env.CHANGED_SERVICES = selected.join(',')
          if (env.CHANGED_SERVICES) {
            echo "Services to build: ${env.CHANGED_SERVICES}"
          } else {
            echo 'No service changes detected. CI image build will be skipped.'
          }
        }
      }
    }

    stage('Build & Push Images') {
      when {
        expression { return env.CHANGED_SERVICES?.trim() }
      }
      steps {
        withCredentials([
          usernamePassword(
            credentialsId: 'docker-registry-creds',
            usernameVariable: 'DOCKERHUB_USER',
            passwordVariable: 'DOCKERHUB_PASS'
          )
        ]) {
          script {
            def commitSha = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
            def isMain = (env.BRANCH_NAME == 'main')
            def services = env.CHANGED_SERVICES.split(',') as List

            services.each { serviceName ->
              def imageBase = "${env.REGISTRY}/${env.DOCKERHUB_NAMESPACE}/${env.IMAGE_PREFIX}-${serviceName}"
              echo "Building image for ${serviceName}: ${imageBase}:${commitSha}"

              container('kaniko') {
                sh """#!/busybox/sh
set -eu
cd "${WORKSPACE}"
mkdir -p /kaniko/.docker
AUTH_B64=\$(printf '%s:%s' "\$DOCKERHUB_USER" "\$DOCKERHUB_PASS" | base64 | tr -d '\\n')
cat > /kaniko/.docker/config.json <<EOF
{"auths":{"docker.io":{"auth":"\$AUTH_B64"}}}
EOF

DEST_ARGS="--destination=${imageBase}:${commitSha}"
if [ "${isMain}" = "true" ]; then
  DEST_ARGS="\$DEST_ARGS --destination=${imageBase}:main"
fi

/kaniko/executor \
  --context "\${PWD}/${serviceName}" \
  --dockerfile "\${PWD}/${serviceName}/Dockerfile" \
  \$DEST_ARGS
"""
              }
            }
          }
        }
      }
    }
  }

  post {
    always {
      echo "Branch: ${env.BRANCH_NAME}"
      echo "Built services: ${env.CHANGED_SERVICES ?: 'none'}"
    }
  }
}
