properties([
    parameters([
        reactiveChoice(choiceType: 'PT_SINGLE_SELECT', description: 'Select the deployment environment (Blue or Green).', filterLength: 1, filterable: false, 
        name: 'DEPLOY_ENV', randomName: 'choice-parameter-1795658162080615', referencedParameters: '', 
        script: groovyScript(fallbackScript: [classpath: [], oldScript: '', sandbox: false, script: 'return [\'blue\', \'green\']'], 
        script: [classpath: [], oldScript: '', sandbox: false, script: '''def deployEnvFile = new File(\'/var/lib/jenkins/workspace/DEPLOY_ENV\')
            def currentEnv = \'blue\'
            if (deployEnvFile.exists()) {
                currentEnv = deployEnvFile.text.trim()
            }
            def nextEnv = currentEnv == \'blue\' ? \'green\' : \'blue\'
            return [nextEnv, currentEnv]'''
            ]))
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
        DEPLOY_ENV = "${params.DEPLOY_ENV}"
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
                                if(env."${repoName}_HAS_CHANGES" == 'true' || hasChanges == '1') {
                                    stage("Building ${repoName}") {
                                        script {
                                            def envVars = []
                                            if (environment != null) {
                                                echo "Setting environment variables for ${repoName}"
                                                envVars = environment.collect { key, value -> "${key}=${value}" }
                                                if (environment.ENV_FILE != null) {
                                                    sh "cp ${environment.ENV_FILE} ${repoName}/.env"
                                                }
                                            }
                                            withEnv(envVars) {
                                                dir(repoName) {
                                                    def deployEnv = getActiveDeployEnvironment()
                                                    echo "Installing dependencies for ${repoName}"
                                                    sh "${installCommand}"
                                                    echo "Building project for ${repoName}"
                                                    sh "${buildCommand}"
                                                    echo "Building Docker image for ${repoName}"
                                                    sh "docker build -t ${dockerImage}:${deployEnv} -f ${dockerFile} ."

                                                    withCredentials([usernamePassword(credentialsId: "${DOCKER_CREDENTIALS_ID}", usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                                                        echo "Pushing Docker image for ${repoName} to Docker Hub"
                                                        sh "echo ${DOCKER_PASSWORD} | docker login -u ${DOCKER_USERNAME} --password-stdin"
                                                        sh "docker push ${dockerImage}:${deployEnv}"
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    echo "No changes detected in ${repoName}. Skipping build."
                                }
                                stage("Deploying ${repoName}") {
                                    script {
                                        dir(repoName) {
                                            def deployEnv = getActiveDeployEnvironment()
                                            sh "cp -f ../${terraformFile} ."
                                            if (!fileExists('.terraform')) {
                                                sh 'terraform init'
                                            }
                                            withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                                                echo "Deploying to Kubernetes for repository: ${repoName} on ${deployEnv} using Terraform"
                                                sh """
                                                    kubectl create namespace ${repoName} --dry-run=client -o yaml | kubectl apply -f -
                                                """
                                                sh """ if ! kubectl get svc ${repoName}-service -n ${repoName}; then
                                                        kubectl create service loadbalancer ${repoName}-service --tcp=${publicPort}:${targetPort} --selector=app=${repoName}-${deployEnv},version=${deployEnv} --dry-run=client -o yaml | kubectl apply -f - -n ${repoName}
                                                    fi
                                                """
                                                sh """
                                                    terraform workspace select -or-create=true ${repoName}-${deployEnv}
                                                    terraform apply -auto-approve \
                                                    -var 'app_name=${repoName}-${deployEnv}' \
                                                    -var 'namespace_name=${repoName}' \
                                                    -var 'docker_image=${dockerImage}:${deployEnv}' \
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
                                if (params.SWITCH_TRAFFIC == true){
                                    stage("Switch Traffic Between Blue & Green Environment for ${repoName}") {
                                        script {
                                            dir(repoName) {
                                                def deployEnv = getActiveDeployEnvironment()
                                                deployEnv = (deployEnv == 'blue') ? 'green' : 'blue'
                                                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                                                    echo "Switching traffic to ${deployEnv} for ${repoName}"
                                                    sh """
                                                        kubectl patch service ${repoName}-service -n ${repoName} -p '{"spec":{"selector":{"app":"${repoName}-${deployEnv}", "version":"${deployEnv}"}}}'
                                                    """
                                                    sh "echo ${deployEnv} > DEPLOY_ENV"
                                                    echo "Traffic switched to ${deployEnv} for ${repoName}"
                                                }
                                            }
                                        }
                                    }
                                }
                                stage("Verify Deployment for ${repoName}") {
                                    script {
                                        dir(repoName) {
                                            def deployEnv = getActiveDeployEnvironment()
                                            withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                                                def SVC_EXTERNAL_IP = sh(script: "kubectl get svc ${repoName}-service -n ${repoName} -o jsonpath='{.status.loadBalancer.ingress[0].ip}'", returnStdout: true).trim()
                                                def SVC_PORT = sh(script: "kubectl get svc ${repoName}-service -n ${repoName} -o jsonpath='{.spec.ports[0].port}'", returnStdout: true).trim()

                                                def isServiceAvailable = sh(script: "curl -s -o /dev/null -w '%{http_code}' http://${SVC_EXTERNAL_IP}:${SVC_PORT}", returnStatus: true)
                                                if (isServiceAvailable == 0) {
                                                    echo "[${repoName}] Service is available at http://${SVC_EXTERNAL_IP}:${SVC_PORT}"
                                                } else {
                                                    error "[${repoName}] Service is not available at http://${SVC_EXTERNAL_IP}:${SVC_PORT}"
                                                }
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

private def getActiveDeployEnvironment() {
    if (!fileExists('DEPLOY_ENV')) {
        echo "Creating DEPLOY_ENV file"
        sh "echo ${env.DEPLOY_ENV} > DEPLOY_ENV"
    }
    return readFile('DEPLOY_ENV').trim()
}
