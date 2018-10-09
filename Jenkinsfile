#!groovy

/**
 * This program and the accompanying materials are made available under the terms of the
 * Eclipse Public License v2.0 which accompanies this distribution, and is available at
 * https://www.eclipse.org/legal/epl-v20.html
 *
 * SPDX-License-Identifier: EPL-2.0
 *
 * Copyright IBM Corporation 2018
 */



@Library('zoe-jenkins-library') _

def isPullRequest = env.BRANCH_NAME.startsWith('PR-')

def opts = []
// keep last 20 builds for regular branches, no keep for pull requests
opts.push(buildDiscarder(logRotator(numToKeepStr: (isPullRequest ? '' : '20'))))
// disable concurrent build
opts.push(disableConcurrentBuilds())
// set upstream triggers
if (env.BRANCH_NAME == 'master') {
  opts.push(pipelineTriggers([
    upstream(threshold: 'SUCCESS', upstreamProjects: '/explorer-server-tests,/explorer-jes/master,/explorer-mvs/master,/explorer-uss/master')
  ]))
}

// define custom build parameters
def customParameters = []
customParameters.push(credentials(
  name: 'PAX_SERVER_CREDENTIALS_ID',
  description: 'The server credential used to create PAX file',
  credentialType: 'com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl',
  defaultValue: 'TestAdminzOSaaS2',
  required: true
))
customParameters.push(string(
  name: 'PAX_SERVER_IP',
  description: 'The server IP used to create PAX file',
  defaultValue: '172.30.0.1',
  trim: true
))
customParameters.push(string(
  name: 'ARTIFACTORY_SERVER',
  description: 'Artifactory server, should be pre-defined in Jenkins configuration',
  defaultValue: 'gizaArtifactory',
  trim: true
))
customParameters.push(string(
  name: 'ATLAS_VERSION',
  description: 'Atlas version number',
  defaultValue: '0.0.3',
  trim: true
))
opts.push(parameters(customParameters))

// set build properties
properties(opts)

node ('jenkins-slave') {
  currentBuild.result = 'SUCCESS'

  try {

    stage('checkout') {
      // checkout source code
      checkout scm

      // check if it's pull request
      echo "Current branch is ${env.BRANCH_NAME}"
      if (isPullRequest) {
        echo "This is a pull request"
      }
    }

    stage('prepare') {
      echo 'preparing PAX workspace folder...'

      // download-atlas-war
      def server = Artifactory.server params.ARTIFACTORY_SERVER
      def downloadSpec = readFile "artifactory-download-spec.json"
      server.download(downloadSpec)

      // verify files are correctly downloaded
      if (!fileExists('pax-workspace/content/wlp/usr/servers/Atlas/apps/atlas-server.war')) {
        error 'failed to download atlas-server.war'
      }
      if (!fileExists('pax-workspace/content/wlp/usr/servers/Atlas/apps/explorer-mvs.war')) {
        error 'failed to download explorer-mvs.war'
      }
      if (!fileExists('pax-workspace/content/wlp/usr/servers/Atlas/apps/explorer-uss.war')) {
        error 'failed to download explorer-uss.war'
      }
      if (!fileExists('pax-workspace/content/wlp/usr/servers/Atlas/apps/explorer-jes.war')) {
        error 'failed to download explorer-jes.war'
      }
      if (!fileExists('pax-workspace/wlp-embeddable-zos-17.0.0.2.pax')) {
        error 'failed to download wlp-embeddable-zos-17.0.0.2.pax'
      }

      // prepare folder
      sh 'mkdir -p pax-workspace/content/wlp/usr/servers/Atlas/dropins/languages.war'
      // we didn't run "server create Atlas" because we will put files in /wlp/usr/servers/Atlas folder directly
      // so we manually create this directory which will be required by zoe installation
      sh 'mkdir -p pax-workspace/content/wlp/usr/servers/.classCache/javasharedresources'
      sh 'mkdir -p pax-workspace/content/wlp/usr/servers/.pid'
      // copy-atlas-server-config
      sh 'cp src/main/resources/jvm.options pax-workspace/content/wlp/usr/servers/Atlas'
      // copy-atlas-server-languages
      //sh 'jar cvfM pax-workspace/content/wlp/usr/servers/Atlas/dropins/languages.war -C src/main/resources/languages/ .'
      // languages.war is a directory
      sh 'cp src/main/resources/languages/* pax-workspace/content/wlp/usr/servers/Atlas/dropins/languages.war/'
      // keep empty folders
      // file should not be hidden from chmod command, which may cause failure
      sh 'touch pax-workspace/content/wlp/usr/servers/.classCache/javasharedresources/keep'
      sh 'touch pax-workspace/content/wlp/usr/servers/.pid/keep'

      // debug purpose, list all files in workspace
      sh 'find ./pax-workspace -print'
    }

    stage('package') {
      // scp files and ssh to z/OS to pax workspace
      echo "creating pax file from workspace..."
      timeout(time: 10, unit: 'MINUTES') {
        createPax('atlas-wlp-package', "atlas-wlp-package-${params.ATLAS_VERSION}.pax",
                  params.PAX_SERVER_IP, params.PAX_SERVER_CREDENTIALS_ID,
                  './pax-workspace', '/zaas1/buildWorkspace', '-ppx -o saveext')
        def buildIdentifier = getBuildIdentifier(true, '__EXCLUDE__', true)
        def uniqueVersion = "${params.ATLAS_VERSION}-${buildIdentifier}"

        zip dir: 'pax-workspace',
            glob: 'atlas-wlp-package-*.pax',
            zipFile: "atlas-wlp-package-${uniqueVersion}-installer.zip"
      }
    }

    stage('publish') {
      echo 'publishing pax file to artifactory...'

      def releaseIdentifier = getReleaseIdentifier()

      def server = Artifactory.server params.ARTIFACTORY_SERVER
      def uploadSpec = readFile "artifactory-upload-spec.json"
      uploadSpec = uploadSpec.replaceAll(/\{ARTIFACTORY_VERSION\}/, params.ATLAS_VERSION)
      uploadSpec = uploadSpec.replaceAll(/\{RELEASE_IDENTIFIER\}/, releaseIdentifier)
      def buildInfo = Artifactory.newBuildInfo()
      server.upload spec: uploadSpec, buildInfo: buildInfo
      server.publishBuildInfo buildInfo
    }

    stage('done') {
      // send out notification
      emailext body: "Job \"${env.JOB_NAME}\" build #${env.BUILD_NUMBER} success.\n\nCheck detail: ${env.BUILD_URL}" ,
          subject: "[Jenkins] Job \"${env.JOB_NAME}\" build #${env.BUILD_NUMBER} success",
          recipientProviders: [
            [$class: 'RequesterRecipientProvider'],
            [$class: 'CulpritsRecipientProvider'],
            [$class: 'DevelopersRecipientProvider'],
            [$class: 'UpstreamComitterRecipientProvider']
          ]
    }

  } catch (err) {
    currentBuild.result = 'FAILURE'

    // catch all failures to send out notification
    emailext body: "Job \"${env.JOB_NAME}\" build #${env.BUILD_NUMBER} failed.\n\nError: ${err}\n\nCheck detail: ${env.BUILD_URL}" ,
        subject: "[Jenkins] Job \"${env.JOB_NAME}\" build #${env.BUILD_NUMBER} failed",
        recipientProviders: [
          [$class: 'RequesterRecipientProvider'],
          [$class: 'CulpritsRecipientProvider'],
          [$class: 'DevelopersRecipientProvider'],
          [$class: 'UpstreamComitterRecipientProvider']
        ]

    throw err
  }
}
