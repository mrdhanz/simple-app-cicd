pipeline {
    agent any
    parameters {
        booleanParam(defaultValue: false, description: 'Destroy the infrastructure', name: 'DESTROY')
    }

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
            when {
                not { equals expected: true, actual: params.DESTROY }
            }
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

                        // Use 'dir' to isolate each repository workspace
                        dir(repoName) {
                            // Checkout the repository
                            def hasChanges = '0'
                            if (fileExists('.git')) {
                                // Check if there are new commits since the last build
                                hasChanges = sh(script: "git rev-list HEAD ^origin/${repoBranch} --count", returnStdout: true).trim()
                            } else {
                                git branch: repoBranch, url: repoUrl, credentialsId: 'Git'
                                hasChanges = '1'
                            }

                            // If changes are found, add the repository build to the parallel stages
                            if (hasChanges != '0') {
                                anyRepoHasChanges = true // Set flag to true if any repo has changes
                                parallelStages[repoName] = {
                                    stage("Building ${repoName}") {
                                        steps {
                                            script {
                                                // parse repo.env. for withEnv
                                                def envVars = repo.env.collect { key, value -> "${key}=${value}" }
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
                                                            echo "Pushing Docker image for ${repoName}"
                                                            sh "echo ${DOCKER_PASSWORD} | docker login -u ${DOCKER_USERNAME} --password-stdin"
                                                            sh "docker push ${dockerImage}:${env.BUILD_ID}"
                                                            // remove the image from the local machine after pushing it to the registry
                                                            sh "docker rmi ${dockerImage}:${env.BUILD_ID}"
                                                        }
                                                    }
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

        stage('Deploy to Kubernetes using Terraform') {
            when {
                not { equals expected: true, actual: params.DESTROY }
                expression { return env.ANY_REPO_HAS_CHANGES == 'true' }
            }
            steps {
                script {
                    // Read the JSON file
                    def jsonText = readFile(file: REPO_JSON_FILE)
                    def repos = readJSON text: jsonText

                    // Loop through each repository
                    for (repo in repos) {
                        def repoName = repo.name
                        def dockerImage = repo.docker_image
                        def publicPort = repo.env.PORT
                        def terraformFile = repo.terraform_file
                        // Use 'dir' to isolate each repository workspace
                        dir(repoName) {
                            // Copy main.tf to the repository directory
                            sh "cp ../${terraformFile} main.tf"
                            echo "Deploying to Kubernetes for repository: ${repoName}"
                            withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                                sh """
                                    terraform init
                                    terraform workspace select -or-create=true ${repoName}
                                    terraform apply -auto-approve \
                                    -var 'app_name=${repoName}' \
                                    -var 'namespace_name=${repoName}' \
                                    -var 'public_port=${publicPort}' \
                                    -var 'docker_image=${dockerImage}:${env.BUILD_ID}' \
                                    -var 'build_number=${env.BUILD_ID}'
                                """
                            }
                        }
                    }
                }
            }
        }

        stage('Destroy Infrastructure') {
            when { equals expected: true, actual: params.DESTROY }
            steps {
                script {
                    // Read the JSON file
                    def jsonText = readFile(file: REPO_JSON_FILE)
                    def repos = readJSON text: jsonText

                    // Loop through each repository
                    for (repo in repos) {
                        def repoName = repo.name
                        def dockerImage = repo.docker_image
                        def publicPort = repo.env.PORT
                        // Use 'dir' to isolate each repository workspace
                        dir(repoName) {
                            echo "Destroying infrastructure for repository: ${repoName}"
                            withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                                sh """
                                    terraform workspace select -or-create=true ${repoName}
                                    terraform destroy -auto-approve \
                                    -var 'app_name=${repoName}' \
                                    -var 'namespace_name=${repoName}' \
                                    -var 'public_port=${publicPort}' \
                                    -var 'docker_image=${dockerImage}:${env.BUILD_ID}' \
                                    -var 'build_number=${env.BUILD_ID}'
                                """
                            }
                        }
                    }
                }
            }
        }
    }
}
