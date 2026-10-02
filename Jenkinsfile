def deployPage(host, sourceFile) {
    withEnv(["TARGET_HOST=${host}", "SOURCE_FILE=${sourceFile}"]) {
        sh '''
            scp -i "$DEPLOY_KEY" \
                -o BatchMode=yes \
                -o IdentitiesOnly=yes \
                -o StrictHostKeyChecking=yes \
                -o ConnectTimeout=10 \
                "$SOURCE_FILE" \
                "deploy@$TARGET_HOST:$WEB_ROOT/index.html.next"

            ssh -i "$DEPLOY_KEY" \
                -o BatchMode=yes \
                -o IdentitiesOnly=yes \
                -o StrictHostKeyChecking=yes \
                -o ConnectTimeout=10 \
                "deploy@$TARGET_HOST" \
                "chmod 644 '$WEB_ROOT/index.html.next' && mv '$WEB_ROOT/index.html.next' '$WEB_ROOT/index.html'"
        '''
    }
}

def verifyPage(host, expectedFile) {
    withEnv(["TARGET_HOST=${host}", "EXPECTED_FILE=${expectedFile}"]) {
        sh '''
            curl --fail --silent --show-error \
                --connect-timeout 5 \
                --max-time 15 \
                "http://$TARGET_HOST/" > live-response.html

            cmp "$EXPECTED_FILE" live-response.html
            echo "Verified: $TARGET_HOST serves the expected page"
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
            description: 'Simulate a failure after production deployment to test rollback'
        )
    }

    environment {
        STAGING_HOST = '172.31.12.50'
        PROD_HOST = '172.31.14.25'
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

        stage('Build and validate') {
            steps {
                sh '''
                    mkdir -p site
                    COMMIT=$(git rev-parse --short HEAD)

                    sed \
                        -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/g" \
                        -e "s/__GIT_COMMIT__/$COMMIT/g" \
                        index.html > site/index.html

                    test -s site/index.html
                    grep -q '</html>' site/index.html
                    grep -q "jenkins-build-${BUILD_NUMBER}" site/index.html

                    if grep -qE '__BUILD_NUMBER__|__GIT_COMMIT__' site/index.html; then
                        echo "Unreplaced placeholders found"
                        exit 1
                    fi
                '''

                archiveArtifacts artifacts: 'site/index.html',
                                 fingerprint: true
            }
        }

        stage('Deploy and test staging') {
            steps {
                script {
                    deployPage(env.STAGING_HOST, 'site/index.html')
                    verifyPage(env.STAGING_HOST, 'site/index.html')
                }
            }
        }

        stage('Approve production') {
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input(
                        message: "Inspect staging. Deploy build #${env.BUILD_NUMBER} to production?",
                        ok: 'Deploy',
                        submitter: 'rob'
                    )
                }
            }
        }

        stage('Back up production') {
            steps {
                sh '''
                    mkdir -p backup

                    scp -i "$DEPLOY_KEY" \
                        -o BatchMode=yes \
                        -o IdentitiesOnly=yes \
                        -o StrictHostKeyChecking=yes \
                        -o ConnectTimeout=10 \
                        "deploy@$PROD_HOST:$WEB_ROOT/index.html" \
                        backup/index.html

                    test -s backup/index.html
                '''

                archiveArtifacts artifacts: 'backup/index.html',
                                 fingerprint: true
            }
        }

        stage('Deploy and test production') {
            steps {
                script {
                    try {
                        deployPage(env.PROD_HOST, 'site/index.html')
                        verifyPage(env.PROD_HOST, 'site/index.html')

                        if (params.TEST_ROLLBACK) {
                            error('Simulated production failure')
                        }

                        echo 'Production deployment passed!'
                    } catch (Exception deploymentError) {
                        echo "Deployment failed: ${deploymentError.message}"
                        echo 'Restoring the previous production page...'

                        try {
                            deployPage(env.PROD_HOST, 'backup/index.html')
                            verifyPage(env.PROD_HOST, 'backup/index.html')
                        } catch (Exception rollbackError) {
                            error("ROLLBACK FAILED: ${rollbackError.message}. Check production manually.")
                        }

                        error('Previous page restored and verified. This deployment is marked FAILED.')
                    }
                }
            }
        }
    }

    post {
        success {
            echo 'Staging and production now serve the new build.'
        }
        failure {
            echo 'Check the console for the failure and any rollback result.'
        }
        aborted {
            echo 'Build aborted. Check the console for its last completed action.'
        }
    }
}
