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
                                                    dir(repoName) {
                                                        sh "cp ../${environment.ENV_FILE} > .env"
                                                    }
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
                                                    echo "Building Docker image for ${repoName} on Blue and Green"
                                                    // Docker build using the current directory context
                                                    sh "docker build -t ${dockerImage}:blue -f ${dockerFile} ."
                                                    sh "docker build -t ${dockerImage}:green -f ${dockerFile} ."

                                                    // Docker login and push the image
                                                    withCredentials([usernamePassword(credentialsId: "${DOCKER_CREDENTIALS_ID}", usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                                                        echo "Pushing Docker image for ${repoName} to Docker Hub on Blue and Green"
                                                        sh "echo ${DOCKER_PASSWORD} | docker login -u ${DOCKER_USERNAME} --password-stdin"
                                                        sh "docker push ${dockerImage}:blue"
                                                        sh "docker push ${dockerImage}:green"
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    stage("Deploying ${repoName} to Blue-Green") {
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
                                                        -var 'app_name=${repoName}-blue' \
                                                        -var 'namespace_name=${repoName}-blue' \
                                                        -var 'public_port=${publicPort}' \
                                                        -var 'docker_image=${dockerImage}:blue' \
                                                        -var 'build_number=${env.BUILD_ID}' \
                                                        -var 'version=blue' \
                                                        --lock=false
                                                    """
                                                    echo "Deploying to Kubernetes for repository: ${repoName} on Green"
                                                    sh """
                                                        terraform workspace select -or-create=true ${repoName}
                                                        terraform apply -auto-approve \
                                                        -var 'app_name=${repoName}' \
                                                        -var 'namespace_name=${repoName}' \
                                                        -var 'public_port=${publicPort}' \
                                                        -var 'docker_image=${dockerImage}:green' \
                                                        -var 'build_number=${env.BUILD_ID}' \
                                                        -var 'version=green' \
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
                                                    sh "kubectl run smoke-test --image=busybox --rm -it --restart=Never -- wget -qO- http://${repoName}-blue-service"
                                                }
                                            }
                                        }
                                    }
                                    stage("Smoke Test ${repoName} on Green") {
                                        script {
                                            // Smoke test the application
                                            echo "Running smoke tests for ${repoName}"
                                            // Use 'dir' to isolate each repository workspace
                                            dir(repoName) {
                                                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                                                    // Run tests on Green environment
                                                    sh "kubectl run smoke-test --image=busybox --rm -it --restart=Never -- wget -qO- http://${repoName}-service"
                                                }
                                            }
                                        }
                                    }
                                    stage("Clean Up ${repoName} on Blue"){
                                        script {
                                            // Clean up the resources
                                            echo "Cleaning up resources for ${repoName} on Blue"
                                            // Use 'dir' to isolate each repository workspace
                                            dir(repoName) {
                                                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                                                    sh """
                                                        terraform workspace select ${repoName}-blue
                                                        terraform destroy -auto-approve \
                                                        -var 'app_name=${repoName}-blue' \
                                                        -var 'namespace_name=${repoName}-blue' \
                                                        -var 'public_port=${publicPort}' \
                                                        -var 'docker_image=${dockerImage}:blue' \
                                                        -var 'build_number=${env.BUILD_ID}' \
                                                        -var 'version=blue' \
                                                        --lock=false
                                                    """
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

    post {
        always {
            // Archive logs or clean up workspace
            cleanWs()
        }
    }
}
