def deployRelease(host, simulateFailure) {
    withEnv([
        "TARGET_HOST=${host}",
        "SIMULATE_FAILURE=${simulateFailure ? '1' : '0'}"
    ]) {
        sh '''
            ssh -i "$DEPLOY_KEY" \
                -o BatchMode=yes \
                -o IdentitiesOnly=yes \
                -o StrictHostKeyChecking=yes \
                -o ConnectTimeout=10 \
                "deploy@$TARGET_HOST" \
                "mkdir -p /home/deploy/releases/$RELEASE"

            scp -i "$DEPLOY_KEY" \
                -o BatchMode=yes \
                -o IdentitiesOnly=yes \
                -o StrictHostKeyChecking=yes \
                -o ConnectTimeout=10 \
                release/* scripts/deploy.sh \
                "deploy@$TARGET_HOST:/home/deploy/releases/$RELEASE/"

            ssh -i "$DEPLOY_KEY" \
                -o BatchMode=yes \
                -o IdentitiesOnly=yes \
                -o StrictHostKeyChecking=yes \
                -o ConnectTimeout=10 \
                "deploy@$TARGET_HOST" \
                "bash /home/deploy/releases/$RELEASE/deploy.sh '$IMAGE_TAG' '$SIMULATE_FAILURE'"
        '''
    }
}

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    parameters {
        booleanParam(
            name: 'TEST_ROLLBACK',
            defaultValue: false,
            description: 'Fail after the production switch to test rollback'
        )
    }

    environment {
        STAGING_HOST = '172.31.12.50'
        PROD_HOST = '172.31.14.25'
        DEPLOY_KEY = '/var/lib/jenkins/.ssh/web-demo'
    }

    stages {
        stage('Checkout') {
            steps {
                deleteDir()
                checkout scm

                script {
                    def commit = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()

                    env.RELEASE = "b${env.BUILD_NUMBER}-${commit}"
                    env.IMAGE_TAG = "web-demo:${env.RELEASE}"
                }
            }
        }

        stage('Parallel checks') {
            parallel {
                stage('Check source') {
                    steps {
                        sh '''
                            bash -n scripts/deploy.sh
                            test -s Dockerfile
                            grep -q '</html>' index.html
                            grep -q '__BUILD_NUMBER__' index.html
                            grep -q '__GIT_COMMIT__' index.html
                        '''
                    }
                }

                stage('Check connections') {
                    steps {
                        sh '''
                            docker info > /dev/null

                            for host in "$STAGING_HOST" "$PROD_HOST"; do
                                ssh -i "$DEPLOY_KEY" \
                                    -o BatchMode=yes \
                                    -o IdentitiesOnly=yes \
                                    -o StrictHostKeyChecking=yes \
                                    -o ConnectTimeout=10 \
                                    "deploy@$host" \
                                    'docker info >/dev/null && command -v flock && sudo -n /usr/sbin/nginx -t'
                            done
                        '''
                    }
                }
            }
        }

        stage('Build release image') {
            steps {
                sh '''
                    mkdir -p site release
                    COMMIT=$(git rev-parse --short HEAD)

                    sed \
                        -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/g" \
                        -e "s/__GIT_COMMIT__/$COMMIT/g" \
                        index.html > site/index.html

                    if grep -qE '__BUILD_NUMBER__|__GIT_COMMIT__' site/index.html; then
                        echo "Unreplaced placeholders found"
                        exit 1
                    fi

                    docker build --pull -t "$IMAGE_TAG" .

                    docker image inspect --format '{{.Id}}' \
                        "$IMAGE_TAG" > release/image.id

                    docker save -o release/image.tar "$IMAGE_TAG"
                    cp site/index.html release/index.html

                    (
                        cd release
                        sha256sum image.tar > image.tar.sha256
                    )
                '''

                archiveArtifacts(
                    artifacts: 'release/index.html,release/image.id,release/image.tar.sha256',
                    fingerprint: true
                )
            }
        }

        stage('Deploy staging') {
            steps {
                script {
                    deployRelease(env.STAGING_HOST, false)
                }
            }
        }

        stage('Approve production') {
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input(
                        message: "Inspect staging. Promote ${env.IMAGE_TAG} to production?",
                        ok: 'Promote',
                        submitter: 'rob'
                    )
                }
            }
        }

        stage('Deploy production') {
            steps {
                script {
                    deployRelease(env.PROD_HOST, params.TEST_ROLLBACK)
                }
            }
        }
    }

    post {
        success {
            echo 'The same release image is live in staging and production.'
        }

        failure {
            echo 'Check the failed stage and deployment rollback messages.'
        }

        always {
            sh 'rm -f release/image.tar'
        }
    }
}
