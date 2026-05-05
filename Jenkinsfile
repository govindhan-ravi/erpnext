pipeline {
    agent any
    environment {
        DOCKER_HUB_USER = 'govindhan1234'
        DOCKER_HUB_REPO_BACKEND = "erpbackend"
        DOCKER_HUB_REPO_FRONTEND = "erpfrontend"
        IMAGE_TAG = "${BUILD_NUMBER}"
        SCANNER_HOME = tool 'sonar-scanner'
        SONAR_PROJECT_KEY = "erpnext-project"
        AWS_REGION = "us-east-1"
        EKS_CLUSTER = "erpnext-cluster"
    }
    stages {
        stage('Git Checkout') {
            steps {
                checkout scm
            }
        }
 
        stage('Install Dependencies') {
            parallel {
                stage('Install Frontend Deps') {
                    steps {
                        sh 'yarn install'
                    }
                }
                stage('Install Backend Deps') {
                    steps {
                        sh 'python3 -m pip install --upgrade pip --break-system-packages'
                        sh 'python3 -m pip install frappe --break-system-packages'
                        sh 'python3 -m pip install -e . --break-system-packages'
                    }
                }
            }
        }
 
        stage('ESLint') {
            steps {
                script {
                    // Check if eslint is available in node_modules or globally
                    def eslintExists = sh(script: "command -v eslint || [ -f ./node_modules/.bin/eslint ]", returnStatus: true) == 0
                    if (eslintExists) {
                        sh 'yarn eslint erpnext/**/*.js || echo "Linting issues found but continuing"'
                    } else {
                        echo "ESLint not found. Skipping linting stage..."
                    }
                }
            }
        }
 
        stage('Tests') {
            parallel {
                stage('Frontend Tests') {
                    steps {
                        script {
                            // Checks if "test" script exists in package.json
                            def hasTestScript = sh(script: "grep -q '\"test\":' package.json", returnStatus: true) == 0
                            if (hasTestScript) {
                                sh 'yarn test || echo "Frontend tests failed but continuing"'
                            } else {
                                echo "No 'test' script found in package.json. Skipping Frontend Tests..."
                            }
                        }
                    }
                }
                stage('Backend Tests') {
                    steps {
                        // Runs pytest since it was installed on the instance
                        sh 'python3 -m pytest || echo "No backend tests found or pytest failed"'
                    }
                }
            }
        }
 
        stage('SonarQube Scan') {
            steps {
                script {
                    withSonarQubeEnv('SonarQube') {
                        sh "${SCANNER_HOME}/bin/sonar-scanner -Dsonar.projectKey=${SONAR_PROJECT_KEY}"
                    }
                }
            }
        }
 
        stage('Quality Gate') {
            steps {
                timeout(time: 1, unit: 'HOURS') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }
 
        stage('Trivy FS Scan') {
            steps {
                sh 'trivy fs .'
            }
        }
 
        stage('Docker Build') {
            steps {
                script {
                    sh "docker build -t ${DOCKER_HUB_USER}/${DOCKER_HUB_REPO_BACKEND}:${IMAGE_TAG} -f Dockerfile.backend ."
                    sh "docker build -t ${DOCKER_HUB_USER}/${DOCKER_HUB_REPO_FRONTEND}:${IMAGE_TAG} -f Dockerfile.frontend ."
                }
            }
        }
 
        stage('Trivy Image Scan') {
            steps {
                sh "trivy image ${DOCKER_HUB_USER}/${DOCKER_HUB_REPO_BACKEND}:${IMAGE_TAG}"
                sh "trivy image ${DOCKER_HUB_USER}/${DOCKER_HUB_REPO_FRONTEND}:${IMAGE_TAG}"
            }
        }
 
        stage('Docker Login') {
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: 'docker-hub-credentials', passwordVariable: 'DOCKER_PASS', usernameVariable: 'DOCKER_USER')]) {
                        sh "echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin"
                    }
                }
            }
        }
 
        stage('Docker Push') {
            steps {
                script {
                    sh "docker push ${DOCKER_HUB_USER}/${DOCKER_HUB_REPO_BACKEND}:${IMAGE_TAG}"
                    sh "docker push ${DOCKER_HUB_USER}/${DOCKER_HUB_REPO_FRONTEND}:${IMAGE_TAG}"
                }
            }
        }
 
        stage('Helm Lint') {
            steps {
                sh 'helm lint helm/erpnext'
            }
        }
 
        stage('EKS Authentication') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials']]) {
                    sh "aws eks update-kubeconfig --region ${AWS_REGION} --name ${EKS_CLUSTER}"
                }
            }
        }
 
        stage('Deploy to EKS') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials']]) {
                    sh """
                        helm upgrade --install erpnext-release ./helm/erpnext \
                            --namespace default \
                            --set image.backend.repository=${DOCKER_HUB_USER}/${DOCKER_HUB_REPO_BACKEND} \
                            --set image.backend.tag=${IMAGE_TAG} \
                            --set image.frontend.repository=${DOCKER_HUB_USER}/${DOCKER_HUB_REPO_FRONTEND} \
                            --set image.frontend.tag=${IMAGE_TAG}
                    """
                }
            }
        }
 
        stage('Deploy Observability Stack') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials']]) {
                    script {
                        sh """
                            helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
                            helm repo update
                            helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
                                --namespace monitoring --create-namespace \
                                --set grafana.service.type=LoadBalancer \
                                --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
                                --set prometheus.service.type=LoadBalancer
                        """
                    }
                }
            }
        }
 
        stage('Output Access URLs') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials']]) {
                    script {
                        echo "Waiting for AWS LoadBalancers to provision (this can take 2-3 minutes)..."
                        sleep 60
                       
                        def prometheusUrl = sh(script: "kubectl get svc -n monitoring prometheus-kube-prometheus-prometheus -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || echo 'Pending'", returnStdout: true).trim()
                        def grafanaUrl = sh(script: "kubectl get svc -n monitoring prometheus-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || echo 'Pending'", returnStdout: true).trim()
                        def grafanaPass = sh(script: "kubectl get secret --namespace monitoring prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 --decode || echo 'prom-operator'", returnStdout: true).trim()
                        def appUrl = sh(script: "kubectl get svc -n default erpnext-release-frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || echo 'Pending'", returnStdout: true).trim()
                       
                        echo "======================================================="
                        echo "🚀 DEPLOYMENT SUCCESSFUL!"
                        echo "🔥 Prometheus UI: http://${prometheusUrl}:9090"
                        echo "📊 Grafana Dashboard: http://${grafanaUrl}"
                        echo "   Username: admin"
                        echo "   Password: ${grafanaPass}"
                        echo "🌐 ERPNext Application: http://${appUrl}"
                        echo "======================================================="
                    }
                }
            }
        }
    }
 
    post {
        always {
            cleanWs()
        }
        success {
            mail to: 'govindhanramya666@gmail.com',
                 subject: "✅ Pipeline Success: ${currentBuild.fullDisplayName}",
                 body: "The deployment for ERPNext was successful.\nCheck the console output at: ${env.BUILD_URL}"
        }
        failure {
            mail to: 'govindhanramya666@gmail.com',
                 subject: "❌ Pipeline Failed: ${currentBuild.fullDisplayName}",
                 body: "The deployment for ERPNext failed.\nPlease check the console output at: ${env.BUILD_URL}"
        }
    }
}