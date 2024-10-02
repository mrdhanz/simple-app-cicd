pipeline {
    agent any

    environment {
        KUBE_CONFIG = credentials('kubeconfig')
        DOCKER_CREDENTIALS_ID = 'docker-credentials'
        REPO_JSON_FILE = 'apps/repositories.json'
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
                    def anyRepoHasChanges = false // Flag to track if any repository has changes

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
                        def terraformFile = repo.terraform_file

                        // Use 'dir' to isolate each repository workspace
                        dir(repoName) {
                            // Checkout the repository
                            def hasChanges = '0'
                            if (fileExists('.git')) {
                                withCredentials([gitUsernamePassword(credentialsId: 'Git', gitToolName: 'Default')]) {
                                    // Fetch the latest changes from the remote repository
                                    sh "git fetch origin ${repoBranch}"
                                    // Get the local and remote commit hashes
                                    def localCommit = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
                                    def remoteCommit = sh(script: "git rev-parse origin/${repoBranch}", returnStdout: true).trim()

                                    // Compare commit hashes and set hasChange flag
                                    if (localCommit != remoteCommit) {
                                        hasChanges = '1'
                                        // Pull the latest changes from the remote repository
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

                            // If changes are found, add the repository build to the parallel stages
                            if (hasChanges != '0') {
                                anyRepoHasChanges = true // Set flag to true if any repo has changes
                                parallelStages[repoName] = {
                                    stage("Building ${repoName}") {
                                        script {
                                            // parse repo.env. for withEnv
                                            def envVars = []
                                            if (environment != null) {
                                                echo "Setting environment variables for ${repoName}"
                                                envVars = environment.collect { key, value -> "${key}=${value}" }
                                                if (environment.ENV_FILE != null) {
                                                    sh "cp ${environment.ENV_FILE} ${repoName}/.env"
                                                }
                                            }
                                            withEnv(envVars) {
                                                // Build steps for the repository
                                                dir(repoName) {
                                                    // Install dependencies and build the project
                                                    echo "Installing dependencies for ${repoName}"
                                                    sh "${installCommand}"
                                                    echo "Building project for ${repoName}"
                                                    sh "${buildCommand}"
                                                    echo "Building Docker image for ${repoName}"
                                                    // Docker build using the current directory context
                                                    sh "docker build -t ${dockerImage}:${env.BUILD_ID} -f ${dockerFile} ."

                                                    // Docker login and push the image
                                                    withCredentials([usernamePassword(credentialsId: "${DOCKER_CREDENTIALS_ID}", usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                                                        echo "Pushing Docker image for ${repoName} to Docker Hub on Blue"
                                                        sh "echo ${DOCKER_PASSWORD} | docker login -u ${DOCKER_USERNAME} --password-stdin"
                                                        sh "docker push ${dockerImage}:${env.BUILD_ID}"
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    stage("Deploying ${repoName} to Blue") {
                                        script {
                                            // Deploy the application to Kubernetes
                                            echo "Deploying ${repoName} to Kubernetes using Terraform"
                                            // Use 'dir' to isolate each repository workspace
                                            dir(repoName) {
                                                // Copy main.tf to the repository directory
                                                sh "cp ../${terraformFile} main.tf"
                                                // Check if terraform has init or not
                                                if (!fileExists('.terraform')) {
                                                    sh 'terraform init'
                                                }
                                                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                                                    echo "Deploying to Kubernetes for repository: ${repoName} on Blue"
                                                    sh """
                                                        terraform workspace select -or-create=true ${repoName}-blue
                                                        terraform apply -auto-approve \
                                                        -var 'app_name=${repoName}' \
                                                        -var 'namespace_name=${repoName}-blue' \
                                                        -var 'public_port=${publicPort}' \
                                                        -var 'docker_image=${dockerImage}:${env.BUILD_ID}' \
                                                        -var 'build_number=${env.BUILD_ID}' \
                                                        -var 'app_version=blue' \
                                                        --lock=false
                                                    """
                                                }
                                            }
                                        }
                                    }
                                    stage("Smoke Test ${repoName} on Blue") {
                                        script {
                                            // Smoke test the application
                                            echo "Running smoke tests for ${repoName}"
                                            // Use 'dir' to isolate each repository workspace
                                            dir(repoName) {
                                                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                                                    // Run tests on Blue environment
                                                    def SVC_EXTERNAL_IP = script {
                                                        return sh(script: "kubectl get svc ${repoName}-service -n ${repoName}-blue -o jsonpath='{.status.loadBalancer.ingress[0].ip}'", returnStdout: true).trim()
                                                    }
                                                    def SVC_PORT = script {
                                                        return sh(script: "kubectl get svc ${repoName}-service -n ${repoName}-blue -o jsonpath='{.spec.ports[0].port}'", returnStdout: true).trim()
                                                    }

                                                    echo "Service is available at http://${SVC_EXTERNAL_IP}:${SVC_PORT}"

                                                    def isServiceAvailable = sh(script: "curl -s -o /dev/null -w '%{http_code}' http://${SVC_EXTERNAL_IP}:${SVC_PORT}", returnStatus: true)
                                                    if (isServiceAvailable == 0) {
                                                        echo "Smoke test passed for ${repoName} on Blue"
                                                        env."${repoName}_BLUE_SMOKE_TEST" = 'true'
                                                    } else {
                                                        error "Smoke test failed for ${repoName} on Blue"
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    // Switch the traffic to Green when the smoke test passes
                                    stage("Switch Traffic to Green for ${repoName}") {
                                        script {
                                            // Use 'dir' to isolate each repository workspace
                                            dir(repoName) {
                                                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                                                    echo "Switching traffic to Green for ${repoName}"
                                                    // Only patch the service and deployment container image if the smoke test passed
                                                    if (env."${repoName}_BLUE_SMOKE_TEST" == 'true') {
                                                        // Tag Docker image with Green and push to Docker Hub
                                                        sh "docker tag ${dockerImage}:${env.BUILD_ID} ${dockerImage}:green-${env.BUILD_ID}"
                                                        // Docker login and push the image
                                                        withCredentials([usernamePassword(credentialsId: "${DOCKER_CREDENTIALS_ID}", usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                                                            echo "Pushing Docker image for ${repoName} to Docker Hub on Green"
                                                            sh "echo ${DOCKER_PASSWORD} | docker login -u ${DOCKER_USERNAME} --password-stdin"
                                                            sh "docker push ${dockerImage}:green-${env.BUILD_ID}"
                                                        }
                                                        echo "Deploying to Kubernetes for repository: ${repoName} on Green"
                                                        sh """
                                                            terraform workspace select -or-create=true ${repoName}
                                                            terraform apply -auto-approve \
                                                            -var 'app_name=${repoName}' \
                                                            -var 'namespace_name=${repoName}' \
                                                            -var 'public_port=${publicPort}' \
                                                            -var 'docker_image=${dockerImage}:green-${env.BUILD_ID}' \
                                                            -var 'build_number=${env.BUILD_ID}' \
                                                            -var 'app_version=green' \
                                                            --lock=false
                                                        """
                                                        // Run tests on Green environment
                                                        def SVC_EXTERNAL_IP = script {
                                                            return sh(script: "kubectl get svc ${repoName}-service -n ${repoName} -o jsonpath='{.status.loadBalancer.ingress[0].ip}'", returnStdout: true).trim()
                                                        }
                                                        def SVC_PORT = script {
                                                            return sh(script: "kubectl get svc ${repoName}-service -n ${repoName} -o jsonpath='{.spec.ports[0].port}'", returnStdout: true).trim()
                                                        }

                                                        echo "Service is available at http://${SVC_EXTERNAL_IP}:${SVC_PORT}"

                                                        def isServiceAvailable = sh(script: "curl -s -o /dev/null -w '%{http_code}' http://${SVC_EXTERNAL_IP}:${SVC_PORT}", returnStatus: true)
                                                        if (isServiceAvailable == 0) {
                                                            echo "Smoke test passed for ${repoName} on Green"
                                                            env."${repoName}_GREEN_SMOKE_TEST" = 'true'
                                                            echo "Traffic switched to Green for ${repoName}"
                                                        } else {
                                                            error "Smoke test failed for ${repoName} on Green"
                                                        }
                                                    } else {
                                                        error "Smoke test failed for ${repoName} on Blue. Traffic not switched to Green."
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    // Clean up the resources on Blue
                                    stage("Clean Up Resources on Blue for ${repoName}") {
                                        script {
                                            // Use 'dir' to isolate each repository workspace
                                            dir(repoName) {
                                                if (env."${repoName}_GREEN_SMOKE_TEST" == 'true') {
                                                    withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                                                        echo "Cleaning up resources on Blue for ${repoName}"
                                                        sh """
                                                            terraform workspace select -or-create=true ${repoName}-blue
                                                            terraform destroy -auto-approve \
                                                            -var 'app_name=${repoName}' \
                                                            -var 'namespace_name=${repoName}-blue' \
                                                            -var 'public_port=${publicPort}' \
                                                            -var 'docker_image=${dockerImage}:${env.BUILD_ID}' \
                                                            -var 'build_number=${env.BUILD_ID}' \
                                                            -var 'app_version=blue' \
                                                            --lock=false
                                                        """
                                                    }
                                                } else {
                                                    echo "Smoke test failed for ${repoName} on Green. Skipping cleanup on Blue."
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                echo "No changes detected in ${repoName}, skipping build."
                            }
                        }
                    }

                    // Run the builds in parallel for the repositories with changes
                    if (parallelStages.size() > 0) {
                        parallel parallelStages
                    } else {
                        echo 'No repositories had changes. No builds to run.'
                    }

                    // Set the environment variable to indicate if any repo had changes
                    env.ANY_REPO_HAS_CHANGES = anyRepoHasChanges.toString()
                }
            }
        }
    }
}
