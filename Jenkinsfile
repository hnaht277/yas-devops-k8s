def normalizeDockerTag(String rawValue) {
  def value = (rawValue ?: 'detached').toLowerCase()
  value = value.replaceAll('[^a-z0-9_.-]+', '-')
  value = value.replaceAll('^[.-]+', '')
  value = value.replaceAll('[.-]+$', '')
  value = value.replaceAll('-{2,}', '-')

  if (!value) {
    value = 'detached'
  }

  if (!(value ==~ /^[a-z0-9_].*/)) {
    value = "b-${value}"
  }

  if (value.length() > 128) {
    value = value.substring(0, 128).replaceAll('[.-]+$', '')
  }

  return value ?: 'detached'
}

def resolveReleaseTag(String branchName, String tagName) {
  def tag = (tagName ?: '').trim()
  if (tag) {
    return tag
  }

  def branch = (branchName ?: '').trim()
  if (branch ==~ /^v\d+\.\d+\.\d+([-+][0-9A-Za-z.-]+)?$/) {
    return branch
  }

  if (branch ==~ /^rc_v\d+\.\d+\.\d+([-+][0-9A-Za-z.-]+)?$/) {
    return branch.replaceFirst(/^rc_/, '')
  }

  return ''
}

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
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.COMMIT_SHA = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
        }
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

          echo "DEBUG raw serviceListOutput: '${serviceListOutput}'"

          def services = serviceListOutput.split('\n') as List
          def essentialServices = [
            'product',
            'cart',
            'order',
            'customer',
            'inventory',
            'tax',
            'media',
            'search',
            'storefront-bff',
            'storefront',
            'backoffice-bff',
            'backoffice'
          ] as Set

          services = services.findAll { essentialServices.contains(it) }
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

          def changedServicesStr = ''
          def releaseTag = resolveReleaseTag(env.BRANCH_NAME, env.TAG_NAME)
          def isRelease = releaseTag?.trim()

          env.RELEASE_TAG = releaseTag
          env.IS_RELEASE = isRelease ? 'true' : 'false'

          if (isRelease) {
            changedServicesStr = services
              .collect { it.trim() }
              .findAll { it }
              .join(',')

            echo "Release build detected (${releaseTag}). Building all services."
          } else if (params.FORCE_ALL_SERVICES) {
            changedServicesStr = services
              .collect { it.trim() }
              .findAll { it }
              .join(',')

            echo "FORCE_ALL_SERVICES=true: building all services (${services})."
          } else {
            def selected = [] as Set
            def commonLibraryChanged = changedFiles.any { it == 'common-library' || it.startsWith('common-library/') }

            changedFiles.each { filePath ->
              echo "DEBUG changed file path: ${filePath}"
              def topDir = filePath.tokenize('/')[0]
              echo "DEBUG topDir: ${topDir}"
              if (services.contains(topDir)) {
                selected.add(topDir)
              }
            }

            if (commonLibraryChanged) {
              echo 'Detected changes in common-library. Resolving dependent services only...'
              services.each { serviceName ->
                if (fileExists("${serviceName}/pom.xml")) {
                  def pomContent = readFile("${serviceName}/pom.xml")
                  if (pomContent.contains('<artifactId>common-library</artifactId>')) {
                    selected.add(serviceName)
                  }
                }
              }
            }

            changedServicesStr = selected ? selected.join(',') : ''
          }

          def normalizedServices = (changedServicesStr ? changedServicesStr.split(',') : [])
            .collect { it.trim() }
            .findAll { it } as Set

          if (normalizedServices.remove('payment-paypal')) {
            echo 'Detected change in payment-paypal (library). Mapping build target to payment service image.'
            normalizedServices.add('payment')
          }

          changedServicesStr = normalizedServices ? normalizedServices.toList().sort().join(',') : ''

          echo "DEBUG changedServicesStr raw: ${changedServicesStr}"
          echo "DEBUG changedServicesStr class: ${changedServicesStr?.getClass()}"

          // assign 1 lần duy nhất
          env.CHANGED_SERVICES = changedServicesStr

          echo "DEBUG CHANGED_SERVICES='${env.CHANGED_SERVICES}'"

          if (env.CHANGED_SERVICES?.trim()) {
            echo "Services to build: ${env.CHANGED_SERVICES}"
          } else {
            echo 'No service changes detected. CI image build will be skipped.'
          }
        }
      }
    }

    stage('Build Java Services') {
      when {
        expression { return (env.CHANGED_SERVICES ?: '').trim() != '' }
      }
      steps {
        script {
          def services = (env.CHANGED_SERVICES ?: '').split(',').findAll { it } as List

          def javaServices = [] as List
          sh 'chmod +x ./mvnw'

          services.each { serviceName ->
            def serviceDir = "${WORKSPACE}/${serviceName}"
            if (fileExists("${serviceDir}/pom.xml")) {
              javaServices.add(serviceName)
            } else {
              echo "Skipping ${serviceName}: not a Java service (no pom.xml)"
            }
          }

          if (javaServices) {
            def serviceList = javaServices.join(',')
            echo "Building Java modules in one reactor run: ${serviceList}"
            sh "./mvnw -pl ${serviceList} -am clean package -DskipTests"

            javaServices.each { serviceName ->
              sh """#!/bin/sh
set -eu
if [ -d "${serviceName}/target" ]; then
  find "${serviceName}/target" -maxdepth 1 -type f -name '*-tests.jar' -delete
fi
"""
            }
          } else {
            echo 'No Java services to build.'
          }
        }
      }
    }

    stage('Build & Push Images') {
      when {
        expression { return (env.CHANGED_SERVICES ?: '').trim() != '' }
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
            def commitSha = env.COMMIT_SHA ?: sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
            def isMain = (env.BRANCH_NAME == 'main')
            def branchTag = normalizeDockerTag(env.BRANCH_NAME)
            def releaseTag = env.RELEASE_TAG?.trim()
            def isRelease = releaseTag ? true : false
            def isReleaseFlag = isRelease ? 'true' : 'false'
            def services = (env.CHANGED_SERVICES ?: '').split(',').findAll { it } as List

            if (isRelease) {
              echo "Image tag strategy for this run: releaseTag=${releaseTag}"
            } else {
              echo "Image tag strategy for this run: commitSha=${commitSha}, branchTag=${branchTag}, mainAlias=${isMain}"
            }

            services.each { serviceName ->
              def imageBase = "${env.REGISTRY}/${env.DOCKERHUB_NAMESPACE}/${env.IMAGE_PREFIX}-${serviceName}"
              if (isRelease) {
                echo "Building image for ${serviceName}: ${imageBase}:${releaseTag}"
              } else {
                echo "Building image for ${serviceName}: ${imageBase}:${commitSha}, ${imageBase}:${branchTag}${isMain ? ', ' + imageBase + ':main' : ''}"
              }

              sh """#!/bin/sh
set -eu
if [ -f "${serviceName}/pom.xml" ]; then
  echo "[JAR-CHECK] Checking ${serviceName}"
  ls -la "${serviceName}/target" || true
  if ls "${serviceName}/target"/*.jar 2>/dev/null | grep -v '\\-tests\\.jar\$' >/dev/null 2>&1; then
    echo "[JAR-CHECK] OK: jar exists for ${serviceName}"
  else
    echo "[JAR-CHECK] ERROR: jar not found for ${serviceName}"
    exit 1
  fi
fi
"""

              container('kaniko') {
                sh """#!/busybox/sh
set -eu
cd "${WORKSPACE}"
mkdir -p /kaniko/.docker
AUTH_B64=\$(printf '%s:%s' "\$DOCKERHUB_USER" "\$DOCKERHUB_PASS" | base64 | tr -d '\\n')
cat > /kaniko/.docker/config.json <<EOF
{
  "auths": {
    "https://index.docker.io/v1/": {
      "auth": "\$AUTH_B64"
    }
  }
}
EOF

echo "===== DOCKER CONFIG ====="
cat /kaniko/.docker/config.json
echo "========================="

echo "DEBUG DOCKER USER: \$DOCKERHUB_USER"
echo "DEBUG AUTH_B64 length: \$(echo -n "\$AUTH_B64" | wc -c)"
echo "DEBUG IMAGE: ${imageBase}:${commitSha}"

DEST_ARGS="--destination=${imageBase}:${commitSha} --destination=${imageBase}:${branchTag}"
if [ "${isReleaseFlag}" = "true" ]; then
  DEST_ARGS="--destination=${imageBase}:${releaseTag}"
elif [ "${isMain}" = "true" ] && [ "${branchTag}" != "main" ]; then
  DEST_ARGS="\$DEST_ARGS --destination=${imageBase}:main"
fi

echo "Cleaning Kaniko workspace before building ${serviceName}..."
rm -rf /kaniko/cache || true
rm -rf /kaniko/0 || true

/kaniko/executor \
  --context "\${PWD}/${serviceName}" \
  --dockerfile "\${PWD}/${serviceName}/Dockerfile" \
  --snapshot-mode=redo \
  --cleanup \
  --use-new-run \
  --single-snapshot \
  --ignore-path node_modules/.bin \
  --ignore-path /app/node_modules/.bin \
  --ignore-path /kaniko/0/app/node_modules/.bin \
  \$DEST_ARGS
"""
              }
            }
          }
        }
      }
    }

    stage('Update GitOps Manifests') {
      when {
        expression {
          def services = (env.CHANGED_SERVICES ?: '').trim()
          def isRelease = (env.IS_RELEASE == 'true')
          def isMain = (env.BRANCH_NAME == 'main')
          return services && (isRelease || isMain)
        }
      }
      steps {
        withCredentials([
          usernamePassword(
            credentialsId: 'github-credentials',
            usernameVariable: 'GIT_USER',
            passwordVariable: 'GIT_TOKEN'
          )
        ]) {
          script {
            def isRelease = (env.IS_RELEASE == 'true')
            def targetEnv = isRelease ? 'staging' : 'dev'
            def targetBranch = isRelease ? 'staging' : 'main'
            def imageTag = isRelease ? env.RELEASE_TAG : env.COMMIT_SHA
            def servicesCsv = (env.CHANGED_SERVICES ?: '')

            sh """#!/usr/bin/env bash
set -euo pipefail

git config user.email "ci-bot@local"
git config user.name "ci-bot"

git fetch origin "${targetBranch}" || true
if git show-ref --quiet "refs/remotes/origin/${targetBranch}"; then
  git checkout -B "${targetBranch}" "origin/${targetBranch}"
else
  git checkout -B "${targetBranch}"
fi

CONFIG_FILE="k8s/deploy/developer-build-config.yaml"
VALUES_DIR="k8s/deploy/argocd/values/${targetEnv}"

IFS=',' read -r -a services <<< "${servicesCsv}"
for svc in "\${services[@]}"; do
  chart="\$(yq -r ".services[] | select(.name==\\\"\${svc}\\\") | .chart" "\${CONFIG_FILE}")"
  values_key="\$(yq -r ".services[] | select(.name==\\\"\${svc}\\\") | .valuesKey" "\${CONFIG_FILE}")"

  if [ -z "\${chart}" ] || [ "\${chart}" = "null" ]; then
    echo "Missing chart mapping for \${svc}" >&2
    exit 1
  fi

  values_file="\${VALUES_DIR}/\${chart}.yaml"
  if [ ! -f "\${values_file}" ]; then
    echo "Missing values file: \${values_file}" >&2
    exit 1
  fi

  repo="docker.io/${DOCKERHUB_NAMESPACE}/${IMAGE_PREFIX}-\${svc}"
  yq -i ".\${values_key}.image.repository = \\\"\${repo}\\\"" "\${values_file}"
  yq -i ".\${values_key}.image.tag = \\\"${imageTag}\\\"" "\${values_file}"
done

if git diff --quiet; then
  echo "No GitOps changes to commit."
  exit 0
fi

git add "\${VALUES_DIR}"
git commit -m "chore(argocd): update ${targetEnv} image tags to ${imageTag}"

REMOTE_URL="\$(git config --get remote.origin.url)"
if [[ "\${REMOTE_URL}" == git@* ]]; then
  REMOTE_URL="https://github.com/\${REMOTE_URL#git@github.com:}"
fi
PUSH_URL="https://\${GIT_USER}:\${GIT_TOKEN}@\${REMOTE_URL#https://}"

git fetch origin "${targetBranch}" || true
git rebase "origin/${targetBranch}"

git push "\${PUSH_URL}" HEAD:"${targetBranch}"
"""
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
