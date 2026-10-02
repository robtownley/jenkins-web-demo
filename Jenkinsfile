pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 5, unit: 'MINUTES')
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    environment {
        WEB_HOST = '172.31.14.25'
        WEB_ROOT = '/usr/share/nginx/html'
        DEPLOY_KEY = '/var/lib/jenkins/.ssh/web-demo'
    }

    stages {
        stage('Checkout Git') {
            steps {
                deleteDir()
                checkout scm
                sh 'git log -1 --oneline'
            }
        }

        stage('Build website') {
            steps {
                sh '''
                    mkdir -p site
                    COMMIT=$(git rev-parse --short HEAD)

                    sed \
                        -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/g" \
                        -e "s/__GIT_COMMIT__/$COMMIT/g" \
                        index.html > site/index.html
                '''
            }
        }

        stage('Validate website') {
            steps {
                sh '''
                    test -s site/index.html
                    grep -q '</html>' site/index.html
                    grep -q "jenkins-build-${BUILD_NUMBER}" site/index.html

                    if grep -qE '__BUILD_NUMBER__|__GIT_COMMIT__' site/index.html; then
                        echo "Unreplaced placeholders found"
                        exit 1
                    fi
                '''
            }
        }

        stage('Deploy to EC2') {
            steps {
                sh '''
                    scp -i "$DEPLOY_KEY" \
                        -o BatchMode=yes \
                        -o IdentitiesOnly=yes \
                        -o StrictHostKeyChecking=yes \
                        -o ConnectTimeout=10 \
                        site/index.html \
                        "deploy@$WEB_HOST:$WEB_ROOT/index.html.next"

                    ssh -i "$DEPLOY_KEY" \
                        -o BatchMode=yes \
                        -o IdentitiesOnly=yes \
                        -o StrictHostKeyChecking=yes \
                        -o ConnectTimeout=10 \
                        "deploy@$WEB_HOST" \
                        "chmod 644 '$WEB_ROOT/index.html.next' && mv '$WEB_ROOT/index.html.next' '$WEB_ROOT/index.html'"
                '''
            }
        }

        stage('Check live website') {
            steps {
                sh '''
                    curl --fail --silent --show-error \
                        --connect-timeout 5 \
                        --max-time 15 \
                        "http://$WEB_HOST/" > live-response.html

                    grep -q "jenkins-build-${BUILD_NUMBER}" live-response.html
                    echo "Verified: build #$BUILD_NUMBER is live"
                '''
            }
        }

        stage('Archive website') {
            steps {
                archiveArtifacts artifacts: 'site/index.html',
                                 fingerprint: true
            }
        }
    }

    post {
        success {
            echo 'Website from Git deployed successfully!'
        }
        failure {
            echo 'Build failed — check the failed stage.'
        }
    }
}
