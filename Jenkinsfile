properties([
    parameters([
        reactiveChoice(choiceType: 'PT_SINGLE_SELECT', description: 'Current traffic on:', filterLength: 1, filterable: false, 
        name: 'CURRENT_TRAFFIC', randomName: 'choice-parameter-1795658162080615', referencedParameters: '', 
        script: groovyScript(fallbackScript: [classpath: [], oldScript: '', sandbox: false, script: 'return [\'blue\']'], 
        script: [classpath: [], oldScript: '', sandbox: false, script: '''def currentDir = pwd()
            def deployEnvFile = "${currentDir}/DEPLOY_ENV"
            echo "Deploy Env File: ${deployEnvFile}" > param.log
            return (fileExists(deployEnvFile)) ? [readFile(deployEnvFile).trim()] : ['blue']
            ''']
        ])
    ])

pipeline {
    agent any

    parameters {
        booleanParam(name: 'SWITCH_TRAFFIC', defaultValue: false, description: 'Switch traffic between Blue and Green')
    }

    environment {
        KUBE_CONFIG = credentials('kubeconfig')
        DOCKER_CREDENTIALS_ID = 'docker-credentials'
        REPO_JSON_FILE = 'apps/repositories.json'
        DEPLOY_ENV = "blue"
    }

    tools {
        nodejs 'nodejs-22'
        terraform 'terraform'
    }

    triggers {
        githubPush()  // Triggers the pipeline on GitHub push
    }

    stages {
        stage('Pull Environment Repositories') {
            steps {
                git branch: 'master', url: 'https://github.com/mrdhanz/simple-app-cicd.git', credentialsId: 'Git'
            }
        }

        stage('Detect Changes and Build Repositories') {
            steps {
                script {
                    // Read the JSON file
                    def jsonText = readFile(file: REPO_JSON_FILE)
                    def repos = readJSON text: jsonText

                    // Create a map for parallel stages
                    def parallelStages = [:]
                    def anyRepoHasChanges = false

                    // Loop through each repository
                    for (repo in repos) {
                        def repoName = repo.name
                        def repoUrl = repo.url
                        def repoBranch = repo.branch
                        def installCommand = repo.install_command
                        def buildCommand = repo.build_command
                        def dockerImage = repo.docker_image
                        def dockerFile = repo.docker_file
                        def environment = repo.env
                        def publicPort = repo.env.PORT
                        def targetPort = repo.env.LOCAL_PORT
                        def terraformFile = repo.terraform_file
                        def repoEnv = getActiveDeployFromRepoName(repoName, params.SWITCH_TRAFFIC)

                        dir(repoName) {
                            def hasChanges = '0'
                            if (fileExists('.git')) {
                                withCredentials([gitUsernamePassword(credentialsId: 'Git', gitToolName: 'Default')]) {
                                    sh "git fetch origin ${repoBranch}"
                                    def localCommit = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
                                    def remoteCommit = sh(script: "git rev-parse origin/${repoBranch}", returnStdout: true).trim()

                                    if (localCommit != remoteCommit) {
                                        hasChanges = '1'
                                        echo "Changes detected in ${repoName}, pulling the latest changes."
                                        sh "git pull origin ${repoBranch}"
                                        env."${repoName}_HAS_CHANGES" = 'true'
                                    } else {
                                        hasChanges = '0'
                                    }
                                }
                            } else {
                                echo "Cloning repository: ${repoName}"
                                git branch: repoBranch, url: repoUrl, credentialsId: 'Git'
                                hasChanges = '1'
                            }

                            parallelStages[repoName] = {
                                if(!isDeployedToKubernetes(repoName, repoEnv) || (env."${repoName}_HAS_CHANGES" == 'true' || hasChanges == '1') || 
                                    (params.SWITCH_TRAFFIC != true || repoEnv == 'green')) {
                                    stage("Building ${repoName} on ${repoEnv}") {
                                        script {
                                            def envVars = []
                                            if (environment != null) {
                                                echo "Setting environment variables for ${repoName}"
                                                envVars = environment.collect { key, value -> 
                                                    if (key.contains("CLIENT_ID")){
                                                        return "${key}=${value} | build-${env.BUILD_ID}-${repoEnv}"
                                                    } else {
                                                        return "${key}=${value}"
                                                    }}
                                                if (environment.ENV_FILE != null) {
                                                    sh "cp -f ${environment.ENV_FILE} ${repoName}/.env"
                                                }
                                            }
                                            withEnv(envVars) {
                                                dir(repoName) {
                                                    def deployEnv = getActiveDeployEnvironment(params.SWITCH_TRAFFIC)
                                                    env."${repoName}_DEPLOY_ENV" = deployEnv
                                                    echo "Installing dependencies for ${repoName}"
                                                    sh "${installCommand}"
                                                    echo "Building project for ${repoName}"
                                                    sh "${buildCommand}"
                                                    // add key value or replace value to env file
                                                    if (environment.ENV_FILE != null) {
                                                        sh "printf '\\nBUILD_VERSION=${deployEnv}-${env.BUILD_ID}' >> .env"
                                                    }
                                                    echo "Building Docker image for ${repoName}"
                                                    sh "docker build -t ${dockerImage}:${deployEnv}-${env.BUILD_ID} -f ${dockerFile} ."

                                                    withCredentials([usernamePassword(credentialsId: "${DOCKER_CREDENTIALS_ID}", usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                                                        echo "Pushing Docker image for ${repoName} to Docker Hub"
                                                        sh "echo ${DOCKER_PASSWORD} | docker login -u ${DOCKER_USERNAME} --password-stdin"
                                                        sh "docker push ${dockerImage}:${deployEnv}-${env.BUILD_ID}"
                                                        sh "docker logout"
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    echo "No changes detected in ${repoName}. Skipping build."
                                }
                                if (params.SWITCH_TRAFFIC != true || repoEnv == 'green' || !isDeployedToKubernetes(repoName, repoEnv)) {
                                    stage("Deploying ${repoName} to Kubernetes on ${repoEnv}") {
                                        script {
                                            dir(repoName) {
                                                def deployEnv = getActiveDeployEnvironment(params.SWITCH_TRAFFIC)
                                                sh "cp -f ../${terraformFile} ."
                                                if (!fileExists('.terraform')) {
                                                    sh 'terraform init'
                                                }
                                                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                                                    echo "Deploying to Kubernetes for repository: ${repoName} on ${deployEnv} using Terraform"
                                                    sh """
                                                        kubectl create namespace ${repoName} --dry-run=client -o yaml | kubectl apply -f -
                                                    """
                                                    sh """
                                                        if ! kubectl get svc ${repoName}-service -n ${repoName}; then
                                                            kubectl create service loadbalancer ${repoName}-service --tcp=${publicPort}:${targetPort} --dry-run=client -o yaml | \\
                                                            kubectl apply -f - -n ${repoName}
                                                            kubectl patch service ${repoName}-service -n ${repoName} -p '{"spec":{"selector":{"app":"${repoName}-${deployEnv}", "version":"${deployEnv}"}}}'
                                                        fi
                                                    """
                                                    sh """
                                                        terraform workspace select -or-create=true ${repoName}-${deployEnv}
                                                        terraform apply -auto-approve \
                                                        -var 'app_name=${repoName}-${deployEnv}' \
                                                        -var 'namespace_name=${repoName}' \
                                                        -var 'docker_image=${dockerImage}:${deployEnv}-${env.BUILD_ID}' \
                                                        -var 'build_number=${env.BUILD_ID}' \
                                                        -var 'app_version=${deployEnv}' \
                                                        -var 'service_name=${repoName}-service' \
                                                        -var 'public_port=${publicPort}' \
                                                        --lock=false
                                                    """
                                                }
                                            }
                                        }
                                    }
                                }
                                if (params.SWITCH_TRAFFIC == true){
                                    stage("Switch Traffic Between Blue & Green Environment for ${repoName}") {
                                        script {
                                            dir(repoName) {
                                                def deployEnv = getActiveDeployEnvironment(params.SWITCH_TRAFFIC)
                                                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                                                    echo "Switching traffic to ${deployEnv} for ${repoName}"
                                                    sh """
                                                        kubectl patch service ${repoName}-service -n ${repoName} -p '{"spec":{"selector":{"app":"${repoName}-${deployEnv}", "version":"${deployEnv}"}}}'
                                                    """
                                                    sh "echo ${deployEnv} > DEPLOY_ENV"
                                                    sh "echo ${deployEnv} > ../DEPLOY_ENV"
                                                    echo "Traffic switched to ${deployEnv} for ${repoName}"
                                                }
                                            }
                                        }
                                    }
                                }
                                stage("Verify Deployment for ${repoName} on ${repoEnv}") {
                                    script {
                                        dir(repoName) {
                                            def deployEnv = getActiveDeployEnvironment(false)
                                            withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                                                sh """
                                                    kubectl get pods -n ${repoName} -l app=${repoName}-${deployEnv}
                                                    kubectl describe pods -n ${repoName} -l app=${repoName}-${deployEnv}
                                                    kubectl describe svc ${repoName}-service -n ${repoName}
                                                """
                                            }
                                        }
                                    }
                                }
                            }
                            
                        }
                    }

                    if (parallelStages.size() > 0) {
                        parallel parallelStages
                    } else {
                        echo 'No repositories had changes. No builds to run.'
                    }

                }
            }
        }
    }
}

private def getActiveDeployEnvironment(switchTraffic) {
    if (!fileExists('DEPLOY_ENV')) {
        echo "Creating DEPLOY_ENV file"
        sh "echo ${env.DEPLOY_ENV} > DEPLOY_ENV"
        sh "echo ${env.DEPLOY_ENV} > ../DEPLOY_ENV"
    }
    def currentEnv = readFile('DEPLOY_ENV').trim()
    if(switchTraffic){
        return (currentEnv == 'blue') ? 'green' : 'blue'
    }
    return currentEnv
}

private def getActiveDeployFromRepoName(repoName, switchTraffic) {
    def currentDir = pwd()
    def repoDir = "${currentDir}/${repoName}"
    if (!fileExists(repoDir)) {
        echo "Creating directory for ${repoName}"
        sh "mkdir -p ${repoDir}"
    }
    if (!fileExists("${repoDir}/DEPLOY_ENV")) {
        echo "Creating DEPLOY_ENV file for ${repoName}"
        sh "echo ${env.DEPLOY_ENV} > ${repoDir}/DEPLOY_ENV"
    }
    def currentEnv = readFile("${repoDir}/DEPLOY_ENV").trim()
    if (switchTraffic) {
        return (currentEnv == 'blue') ? 'green' : 'blue'
    }
    return currentEnv
}

private def isDeployedToKubernetes(repoName, deployEnv) {
    withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
        def result = sh(script: "kubectl get pods -n ${repoName} -l app=${repoName}-${deployEnv}", returnStatus: true)
        return result == 0
    }
}